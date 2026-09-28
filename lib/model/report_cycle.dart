/// 报告周期（周报/双周报/月报/季报/自定义天数）——模型层，AI 配置和报告统计都用它。
library;

enum ReportUnit {
  week('每周', 7, '周报'),
  biweek('每两周', 14, '双周报'),
  month('每月', 0, '月报'),
  quarter('每季度', 0, '季报'),
  custom('自定义天数', 0, '周期报');

  const ReportUnit(this.label, this.fixedDays, this.suffix);

  final String label;

  /// 固定天数的单位（周/双周）用它；月/季/自定义另算
  final int fixedDays;

  /// 文件名后缀：周报 / 双周报 / 月报 / 季报 / 周期报
  final String suffix;

  static ReportUnit fromName(String? s) {
    for (final u in ReportUnit.values) {
      if (u.name == s) return u;
    }
    return ReportUnit.week;
  }
}

/// 报告周期：多久出一期 + 哪天出。
///
/// 按天切分（周/双周/自定义）用「1970-01-05（周一）」当锚点整数倍切，
/// 这样每期首尾固定、不重叠、跨月也不会错位。
class ReportCycle {
  const ReportCycle({
    this.unit = ReportUnit.week,
    this.customDays = 30,
    this.weekday = 1,
    this.monthDay = 1,
  });

  final ReportUnit unit;

  /// unit == custom 时用
  final int customDays;

  /// 周/双周/自定义：周几生成（1=周一 … 7=周日）
  final int weekday;

  /// 月/季：每月几号生成
  final int monthDay;

  static final DateTime _epochMonday = DateTime(1970, 1, 5);

  int get days => unit == ReportUnit.custom ? customDays.clamp(1, 365) : unit.fixedDays;

  bool get isDayBased => unit == ReportUnit.week || unit == ReportUnit.biweek || unit == ReportUnit.custom;

  /// 今天该不该生成
  bool shouldRunOn(DateTime today) {
    switch (unit) {
      case ReportUnit.week:
      case ReportUnit.biweek:
      case ReportUnit.custom:
        return today.weekday == weekday;
      case ReportUnit.month:
        return today.day == monthDay;
      case ReportUnit.quarter:
        // 1/4/7/10 月的那个日子 —— 上一个季度刚结束
        return today.month % 3 == 1 && today.day == monthDay;
    }
  }

  /// 上一期（完整的一期）的范围
  ({DateTime first, DateTime last, String label, String title, String suffix}) previousPeriod(DateTime today) {
    final t = DateTime(today.year, today.month, today.day);

    if (isDayBased) {
      final n = days;
      final since = t.difference(_epochMonday).inDays;
      final idx = since ~/ n - 1; // 上一期
      final first = _epochMonday.add(Duration(days: idx * n));
      final last = first.add(Duration(days: n - 1));
      return (
        first: first,
        last: last,
        label: dayLabel(first),
        title: '${first.year} 年 ${first.month} 月 ${first.day} 日 ~ ${last.month} 月 ${last.day} 日',
        suffix: unit.suffix,
      );
    }

    if (unit == ReportUnit.month) {
      final first = DateTime(t.year, t.month - 1, 1);
      final last = DateTime(t.year, t.month, 0);
      return (
        first: first,
        last: last,
        label: monthLabel(first),
        title: '${first.year} 年 ${first.month} 月',
        suffix: unit.suffix,
      );
    }

    // 季度：当前季度往前推一个
    final q = (t.month - 1) ~/ 3; // 0..3
    final prevStartMonth = (q - 1) * 3 + 1;
    final first = prevStartMonth <= 0 ? DateTime(t.year - 1, 10, 1) : DateTime(t.year, prevStartMonth, 1);
    final last = DateTime(first.year, first.month + 3, 0);
    final qn = ((first.month - 1) ~/ 3) + 1;
    return (
      first: first,
      last: last,
      label: '${first.year}-Q$qn',
      title: '${first.year} 年 Q$qn（${first.month} 月 ~ ${last.month} 月）',
      suffix: unit.suffix,
    );
  }

  /// 人话说明，界面上显示用
  String get description {
    switch (unit) {
      case ReportUnit.week:
        return '每${_weekdayCn(weekday)}总结上一周（上一周的周一 ~ 周日）';
      case ReportUnit.biweek:
        return '每两周的${_weekdayCn(weekday)}总结前两周';
      case ReportUnit.month:
        return '每月 $monthDay 号总结上个月';
      case ReportUnit.quarter:
        return '每季度第一个月的 $monthDay 号总结上一季度';
      case ReportUnit.custom:
        return '每 $days 天总结一次（自定义）';
    }
  }

  static String _weekdayCn(int w) => '周${const ['一', '二', '三', '四', '五', '六', '日'][(w - 1).clamp(0, 6)]}';

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String dayLabel(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
  static String monthLabel(DateTime d) => '${d.year}-${_two(d.month)}';
}
