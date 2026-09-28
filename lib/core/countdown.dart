/// 倒计时的时间计算。
///
/// 关键点：**不能用「毫秒 ÷ 86400」算天数**——夏令时和闰年会把这个数晃掉一天。
/// 这里全部走日历运算。
library;

class Countdown {
  const Countdown({
    required this.years,
    required this.days,
    required this.hours,
    required this.minutes,
    required this.seconds,
    required this.totalDays,
    required this.totalSeconds,
    required this.expired,
    required this.percentElapsed,
  });

  /// 「还剩 X 年 Y 天」里的完整年数
  final int years;

  /// 去掉完整年之后剩下的天数（0-365）
  final int days;

  final int hours;
  final int minutes;
  final int seconds;

  /// 换算成总天数（用于"人生只剩 N 天"这种表达）
  final int totalDays;

  final int totalSeconds;

  /// 已到期（期限早于现在）
  final bool expired;

  /// 从起点到终点已经走完的比例 0.0-1.0
  final double percentElapsed;

  /// 紧凑文案：`57 年 112 天 04:12:33`
  String get compact {
    if (expired) return '已到期';
    final t = [
      hours.toString().padLeft(2, '0'),
      minutes.toString().padLeft(2, '0'),
      seconds.toString().padLeft(2, '0'),
    ].join(':');
    if (years > 0) return '$years 年 $days 天 $t';
    if (days > 0) return '$days 天 $t';
    return t;
  }
}

/// 计算 [now] 到 [target] 的倒计时。
///
/// [start] 可选，只用于算进度百分比（比如出生日期）。
Countdown computeCountdown(DateTime now, DateTime target, {DateTime? start}) {
  final totalSeconds = target.difference(now).inSeconds;
  if (totalSeconds <= 0) {
    return Countdown(
      years: 0,
      days: 0,
      hours: 0,
      minutes: 0,
      seconds: 0,
      totalDays: 0,
      totalSeconds: 0,
      expired: true,
      percentElapsed: 1.0,
    );
  }

  // 完整的年：逐年加，直到超过 target
  var years = 0;
  while (true) {
    final next = _addYears(now, years + 1);
    if (next.isAfter(target)) break;
    years++;
  }
  final anchored = _addYears(now, years);
  final rest = target.difference(anchored);

  var percent = 0.0;
  if (start != null) {
    final span = target.difference(start).inSeconds;
    if (span > 0) {
      percent = (1 - totalSeconds / span).clamp(0.0, 1.0);
    }
  }

  return Countdown(
    years: years,
    days: rest.inDays,
    hours: rest.inHours % 24,
    minutes: rest.inMinutes % 60,
    seconds: rest.inSeconds % 60,
    totalDays: target.difference(now).inDays,
    totalSeconds: totalSeconds,
    expired: false,
    percentElapsed: percent,
  );
}

/// 按「日历日期」算两个时间的整天差（忽略时分秒，避免夏令时误差）。
int calendarDaysBetween(DateTime from, DateTime to) {
  final a = DateTime(from.year, from.month, from.day);
  final b = DateTime(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

DateTime _addYears(DateTime dt, int n) => DateTime(
      dt.year + n,
      dt.month,
      dt.day,
      dt.hour,
      dt.minute,
      dt.second,
      dt.millisecond,
    );
