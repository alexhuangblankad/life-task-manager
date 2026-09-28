/// 定时/重复任务规则。
///
/// 写进 md 的样子（人类可读，Obsidian 里也能看懂）：
///
///     - [ ] 交房租 🔁 每月15日 ^s-abc123
///     - [ ] 上香 🔁 每月农历十五 ^s-def456
///     - [ ] 周会 🔁 每周一 ⏳ 09:00 ^s-ghi789
///     - [ ] 她的生日 🔁 每年农历八月十五 ^s-jkl012
///
/// 支持：每天 / 每周X / 每月N日 / 每月农历X / 每年M月D日 / 每年农历M月D日
library;

import 'package:lunar/lunar.dart';

enum RepeatKind { daily, weekly, monthly, yearly, lunarMonthly, lunarYearly }

class RepeatRule {
  const RepeatRule({required this.kind, this.day, this.month});

  final RepeatKind kind;

  /// weekly: 1-7（周一=1）；monthly: 1-31；yearly: 日；lunarMonthly/lunarYearly: 农历日 1-30
  final int? day;

  /// yearly / lunarYearly 的月份
  final int? month;

  static const List<String> _weekNames = ['一', '二', '三', '四', '五', '六', '日'];

  // ─────────────────── 解析 ───────────────────

  /// 从 `🔁 每月15日` 里解析出规则；不认识就返回 null（绝不瞎猜）
  static RepeatRule? parse(String raw) {
    var s = raw.trim();
    final idx = s.indexOf('🔁');
    // 注意：不能写 substring(idx + 1) —— emoji 占两个 UTF-16 码元，
    // +1 会切在代理对中间，字符串就烂了（这个坑真踩过）
    if (idx >= 0) s = s.substring(idx + '🔁'.length).trim();
    if (s.isEmpty) return null;
    s = s.replaceAll(' ', '');

    if (s == '每天' || s == '每日' || s == 'daily') return const RepeatRule(kind: RepeatKind.daily);

    // 每周一 / 每周日
    final weekly = RegExp(r'^每?周([一二三四五六日天])$').firstMatch(s);
    if (weekly != null) {
      var w = _weekNames.indexOf(weekly.group(1)!.replaceAll('天', '日')) + 1;
      if (w < 1) w = 7;
      return RepeatRule(kind: RepeatKind.weekly, day: w);
    }

    // 每月农历十五 / 每月农历廿三
    final lunarMonthly = RegExp(r'^每月农历(.+)$').firstMatch(s);
    if (lunarMonthly != null) {
      final d = chineseNumber(lunarMonthly.group(1)!);
      if (d != null && d >= 1 && d <= 30) return RepeatRule(kind: RepeatKind.lunarMonthly, day: d);
      return null;
    }

    // 每月15日 / 每月15号
    final monthly = RegExp(r'^每月(\d{1,2})[日号]$').firstMatch(s);
    if (monthly != null) {
      final d = int.parse(monthly.group(1)!);
      if (d >= 1 && d <= 31) return RepeatRule(kind: RepeatKind.monthly, day: d);
      return null;
    }

    // 每年农历八月十五
    final lunarYearly = RegExp(r'^每年农历(.+?)月(.+)$').firstMatch(s);
    if (lunarYearly != null) {
      final m = chineseNumber(lunarYearly.group(1)!);
      final d = chineseNumber(lunarYearly.group(2)!);
      if (m != null && d != null && m >= 1 && m <= 12 && d >= 1 && d <= 30) {
        return RepeatRule(kind: RepeatKind.lunarYearly, month: m, day: d);
      }
      return null;
    }

    // 每年9月28日 / 每年09-28
    final yearly = RegExp(r'^每年(\d{1,2})月(\d{1,2})[日号]?$').firstMatch(s);
    if (yearly != null) {
      final m = int.parse(yearly.group(1)!);
      final d = int.parse(yearly.group(2)!);
      if (m >= 1 && m <= 12 && d >= 1 && d <= 31) {
        return RepeatRule(kind: RepeatKind.yearly, month: m, day: d);
      }
    }
    final yearly2 = RegExp(r'^每年(\d{2})-(\d{2})$').firstMatch(s);
    if (yearly2 != null) {
      final m = int.parse(yearly2.group(1)!);
      final d = int.parse(yearly2.group(2)!);
      if (m >= 1 && m <= 12 && d >= 1 && d <= 31) {
        return RepeatRule(kind: RepeatKind.yearly, month: m, day: d);
      }
    }

    return null;
  }

  // ─────────────────── 展示 ───────────────────

  String get label => switch (kind) {
        RepeatKind.daily => '每天',
        RepeatKind.weekly => '每周${_weekNames[((day ?? 1) - 1).clamp(0, 6)]}',
        RepeatKind.monthly => '每月${day ?? 1}日',
        RepeatKind.lunarMonthly => '每月农历${lunarDayLabel(day ?? 1)}',
        RepeatKind.yearly => '每年${month ?? 1}月${day ?? 1}日',
        RepeatKind.lunarYearly =>
          '每年农历${chineseMonthLabel(month ?? 1)}月${lunarDayLabel(day ?? 1)}',
      };

  String toMarkdown() => '🔁 $label';

  // ─────────────────── 计算 ───────────────────

  bool occursOn(DateTime d) {
    switch (kind) {
      case RepeatKind.daily:
        return true;
      case RepeatKind.weekly:
        return d.weekday == day;
      case RepeatKind.monthly:
        return d.day == day;
      case RepeatKind.yearly:
        return d.month == month && d.day == day;
      case RepeatKind.lunarMonthly:
        final lunar = Solar.fromYmd(d.year, d.month, d.day).getLunar();
        return _lunarDay(lunar) == day;
      case RepeatKind.lunarYearly:
        final lunar = Solar.fromYmd(d.year, d.month, d.day).getLunar();
        return _lunarMonth(lunar) == month && _lunarDay(lunar) == day;
    }
  }

  /// 从 from（含当天）开始找下一次发生的日子，最多找 400 天
  DateTime? nextOccurrence(DateTime from) {
    final start = DateTime(from.year, from.month, from.day);
    for (var i = 0; i < 400; i++) {
      final d = start.add(Duration(days: i));
      if (occursOn(d)) return d;
    }
    return null;
  }

  /// 距离下次发生还有几天
  int? daysUntilNext(DateTime from) {
    final next = nextOccurrence(from);
    if (next == null) return null;
    final a = DateTime(from.year, from.month, from.day);
    return next.difference(a).inDays;
  }

  /// 一个月里会发生几次（日历打点用；按 31 天估）
  static int _lunarDay(Lunar lunar) => lunar.getDay().abs();
  static int _lunarMonth(Lunar lunar) => lunar.getMonth().abs();
}

/// 农历日 15 → 十五
String lunarDayLabel(int day) {
  const names = [
    '初一', '初二', '初三', '初四', '初五', '初六', '初七', '初八', '初九', '初十',
    '十一', '十二', '十三', '十四', '十五', '十六', '十七', '十八', '十九', '二十',
    '廿一', '廿二', '廿三', '廿四', '廿五', '廿六', '廿七', '廿八', '廿九', '三十',
  ];
  if (day < 1 || day > 30) return '$day';
  return names[day - 1];
}

/// 农历月 8 → 八
String chineseMonthLabel(int m) => const [
      '', '正', '二', '三', '四', '五', '六', '七', '八', '九', '十', '冬', '腊'
    ][m.clamp(1, 12)];

/// 中文数字 → 整数（初一、十五、廿三、三十、一二三…都认）
int? chineseNumber(String s) {
  final t = s.trim().replaceAll('日', '').replaceAll('号', '').replaceAll('月', '');
  final direct = int.tryParse(t);
  if (direct != null) return direct;

  const digits = {'一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6, '七': 7, '八': 8, '九': 9, '十': 10};
  const prefix = {'初': 0, '廿': 20, '卅': 30};
  if (t.isEmpty) return null;

  // 初一…初十
  for (final entry in prefix.entries) {
    if (t.startsWith(entry.key)) {
      final rest = t.substring(1);
      if (rest == '十') return entry.value + 10;
      final v = digits[rest];
      if (v == null) return null;
      return entry.value + v;
    }
  }
  if (t == '十') return 10;
  if (t.startsWith('十')) {
    final rest = t.substring(1);
    return 10 + (digits[rest] ?? 0);
  }
  if (t == '二十' || t == '廿十') return 20;
  if (t == '三十') return 30;
  if (t.length == 2 && digits.containsKey(t[1])) return 10 + digits[t[1]]!;
  return digits[t];
}
