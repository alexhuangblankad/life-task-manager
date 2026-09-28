/// 任务自带的提醒规则。
///
/// 写进 md 的样子：
///
///     - [ ] 交材料 📅 2026-10-08 🔔 提前3天 ^s-abc
///     - [ ] 交房租 🔁 每月15日 🔔 到期当天 ^s-def
///     - [ ] 面试 🔔 2026-10-02 09:00 ^s-ghi
///
/// 三种：到期当天 / 提前 N 天 / 指定日期时间。
library;

class RemindRule {
  const RemindRule.onDueDay()
      : kind = RemindKind.onDueDay,
        days = null,
        at = null,
        minutes = null;

  const RemindRule.daysBefore(int n)
      : kind = RemindKind.daysBefore,
        days = n,
        at = null,
        minutes = null;

  const RemindRule.at(DateTime when)
      : kind = RemindKind.atTime,
        days = null,
        at = when,
        minutes = null;

  /// 相对「某个时间点」提前多少分钟（日程用：提前 30 分钟、提前 1 小时）
  const RemindRule.minutesBefore(int m)
      : kind = RemindKind.minutesBefore,
        days = null,
        at = null,
        minutes = m;

  final RemindKind kind;

  /// 提前几天（daysBefore 时有效）
  final int? days;

  /// 指定时刻（atTime 时有效）
  final DateTime? at;

  /// 提前多少分钟（minutesBefore 时有效）
  final int? minutes;

  /// 默认提醒时间：早上 9 点（不打扰睡觉时间）
  static const int defaultHour = 9;

  static RemindRule? parse(String raw) {
    var s = raw.trim();
    final idx = s.indexOf('🔔');
    // emoji 占两个 UTF-16 码元，不能写 +1（踩过这个坑）
    if (idx >= 0) s = s.substring(idx + '🔔'.length).trim();
    if (s.isEmpty) return null;
    s = s.replaceAll(' ', '');

    if (s == '到期当天' || s == '当天') return const RemindRule.onDueDay();

    final before = RegExp(r'^提前(\d{1,3})天$').firstMatch(s);
    if (before != null) {
      final n = int.parse(before.group(1)!);
      if (n >= 0 && n <= 365) return RemindRule.daysBefore(n);
      return null;
    }

    // 日程用：提前30分钟 / 提前1小时 / 开始时
    if (s == '开始时' || s == '开始时提醒') {
      return const RemindRule.minutesBefore(0);
    }
    final mins = RegExp(r'^提前(\d{1,3})小时$').firstMatch(s);
    if (mins != null) return RemindRule.minutesBefore(int.parse(mins.group(1)!) * 60);
    final mins2 = RegExp(r'^提前(\d{1,4})分钟$').firstMatch(s);
    if (mins2 != null) return RemindRule.minutesBefore(int.parse(mins2.group(1)!));

    // 2026-10-02T09:00 或 2026-10-02 09:00（空格已在上面去掉 → 变成 T 形式）
    final at = RegExp(r'^(\d{4}-\d{2}-\d{2})[Tt]?(\d{2}):(\d{2})$').firstMatch(s);
    if (at != null) {
      final d = DateTime.tryParse('${at.group(1)}T${at.group(2)}:${at.group(3)}:00');
      if (d != null) return RemindRule.at(d);
    }
    return null;
  }

  String get label => switch (kind) {
        RemindKind.onDueDay => '到期当天',
        RemindKind.daysBefore => '提前${days ?? 0}天',
        RemindKind.atTime => _fmt(at!),
        RemindKind.minutesBefore => switch (minutes ?? 0) {
            0 => '开始时',
            final m when m % 60 == 0 => '提前${m ~/ 60}小时',
            final m => '提前$m分钟',
          },
      };

  String toMarkdown() => '🔔 $label';

  static String _fmt(DateTime d) =>
      '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}';

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// 相对某个基准时刻的触发时间（日程：基准是开始时间）
  DateTime? fireFrom(DateTime base) => switch (kind) {
        RemindKind.minutesBefore => base.subtract(Duration(minutes: minutes ?? 0)),
        RemindKind.atTime => at,
        RemindKind.onDueDay => DateTime(base.year, base.month, base.day, defaultHour),
        RemindKind.daysBefore => () {
            final d = base.subtract(Duration(days: days ?? 0));
            return DateTime(d.year, d.month, d.day, defaultHour);
          }(),
      };

  /// 该提醒的时刻。任务用：基准是到期日期；算不出来返回 null。
  DateTime? fireAt(DateTime? due) => due == null ? null : fireFrom(due);

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        if (days != null) 'days': days,
        if (at != null) 'at': at!.toIso8601String(),
        if (minutes != null) 'minutes': minutes,
      };

  static RemindRule? fromJson(Map<String, dynamic> j) {
    final kind = j['kind']?.toString();
    switch (kind) {
      case 'onDueDay':
        return const RemindRule.onDueDay();
      case 'daysBefore':
        final n = int.tryParse(j['days'].toString());
        return n == null ? null : RemindRule.daysBefore(n);
      case 'atTime':
        final d = DateTime.tryParse(j['at'].toString());
        return d == null ? null : RemindRule.at(d);
      case 'minutesBefore':
        final m = int.tryParse(j['minutes'].toString());
        return m == null ? null : RemindRule.minutesBefore(m);
    }
    return null;
  }
}

enum RemindKind { onDueDay, daysBefore, atTime, minutesBefore }
