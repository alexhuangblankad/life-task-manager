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
  const RepeatRule({required this.kind, this.day, this.month, this.daysList = const []});

  final RepeatKind kind;

  /// weekly: 1-7（周一=1）；monthly: 1-31；yearly: 日；lunarMonthly/lunarYearly: 农历日 1-30
  final int? day;

  /// yearly / lunarYearly 的月份
  final int? month;

  /// 一个周期里的多个日子，例如「每月农历初一、十五」→ [1, 15]
  /// 有它就以它为准（day 只在单个日子的老写法里用）
  final List<int> daysList;

  /// 实际生效的日子集合（单个或多个统一成列表）
  List<int> get effectiveDays {
    if (daysList.isNotEmpty) return daysList;
    if (day != null) return [day!];
    return const [];
  }

  bool get isMulti => daysList.length > 1;

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

    // 每周一 / 每周日 / 每周一、三、五
    final weekly = RegExp(r'^每?周((?:[一二三四五六日天][、,，]?)+)$').firstMatch(s);
    if (weekly != null) {
      final ws = <int>[];
      for (final p in weekly.group(1)!.split(RegExp(r'[、,，]'))) {
        if (p.isEmpty) continue;
        var w = _weekNames.indexOf(p.replaceAll('天', '日')) + 1;
        if (w < 1) w = 7;
        if (!ws.contains(w)) ws.add(w);
      }
      if (ws.isEmpty) return null;
      return ws.length == 1
          ? RepeatRule(kind: RepeatKind.weekly, day: ws.first)
          : RepeatRule(kind: RepeatKind.weekly, daysList: ws);
    }

    // 每月农历十五 / 每月农历初一、十五
    final lunarMonthly = RegExp(r'^每月农历(.+)$').firstMatch(s);
    if (lunarMonthly != null) {
      final ds = _parseDays(lunarMonthly.group(1)!, max: 30, lunar: true);
      if (ds.isEmpty) return null;
      return ds.length == 1
          ? RepeatRule(kind: RepeatKind.lunarMonthly, day: ds.first)
          : RepeatRule(kind: RepeatKind.lunarMonthly, daysList: ds);
    }

    // 每月15日 / 每月1、15号
    final monthly = RegExp(r'^每月(.+)$').firstMatch(s);
    if (monthly != null) {
      final ds = _parseDays(monthly.group(1)!, max: 31);
      if (ds.isEmpty) return null;
      return ds.length == 1
          ? RepeatRule(kind: RepeatKind.monthly, day: ds.first)
          : RepeatRule(kind: RepeatKind.monthly, daysList: ds);
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

  /// 解析「初一、十五」「1,15」这种一个周期里的多个日子
  static List<int> _parseDays(String raw, {required int max, bool lunar = false}) {
    final out = <int>[];
    for (final part in raw.split(RegExp(r'[、,，和及\s]+'))) {
      var t = part.trim();
      if (t.isEmpty) continue;
      t = t.replaceAll(RegExp(r'[日号]$'), '');
      final v = lunar ? chineseNumber(t) : int.tryParse(t);
      if (v == null || v < 1 || v > max) continue;
      if (!out.contains(v)) out.add(v);
    }
    out.sort();
    return out;
  }

  // ─────────────────── 展示 ───────────────────

  String get label {
    final ds = effectiveDays;
    final multi = isMulti;
    switch (kind) {
      case RepeatKind.daily:
        return '每天';
      case RepeatKind.weekly:
        final names = ds.map((d) => _weekNames[(d - 1).clamp(0, 6)]).join('、');
        return '每周$names';
      case RepeatKind.monthly:
        return '每月${ds.join('、')}日';
      case RepeatKind.lunarMonthly:
        return '每月农历${ds.map(lunarDayLabel).join('、')}';
      case RepeatKind.yearly:
        return '每年${month ?? 1}月${day ?? 1}日';
      case RepeatKind.lunarYearly:
        return '每年农历${chineseMonthLabel(month ?? 1)}月${lunarDayLabel(day ?? 1)}';
    }
    // 上面都 return 了；这行只是让编译器闭嘴
    // ignore: dead_code
    return multi ? ds.join('、') : '';
  }

  String toMarkdown() => '🔁 $label';

  // ─────────────────── 计算 ───────────────────

  bool occursOn(DateTime d) {
    final ds = effectiveDays;
    switch (kind) {
      case RepeatKind.daily:
        return true;
      case RepeatKind.weekly:
        return ds.contains(d.weekday);
      case RepeatKind.monthly:
        return ds.contains(d.day);
      case RepeatKind.yearly:
        return d.month == month && d.day == day;
      case RepeatKind.lunarMonthly:
        final lunar = Solar.fromYmd(d.year, d.month, d.day).getLunar();
        return ds.contains(_lunarDay(lunar));
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
