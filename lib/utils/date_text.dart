/// 日期文案工具（中文习惯的写法）
library;

const List<String> _weekdaysCn = ['一', '二', '三', '四', '五', '六', '日'];

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String dateMonthFolder(DateTime d) => '${d.year}${d.month.toString().padLeft(2, '0')}';

/// 2026-09-28
String formatDateCn(DateTime d) => isoDate(d);

/// 2026 年 9 月 28 日 星期一
String dateHeader(DateTime d) =>
    '${d.year} 年 ${d.month} 月 ${d.day} 日 星期${_weekdaysCn[(d.weekday - 1) % 7]}';

/// 9月28日
String shortDate(DateTime d) => '${d.month} 月 ${d.day} 日';

/// 刚刚 / 3 分钟前 / 昨天 14:30 / 2026-09-28 14:30
String relativeTime(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final diff = n.difference(t);
  if (diff.inSeconds < 60) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24 && n.day == t.day) return '${diff.inHours} 小时前';
  if (diff.inDays < 7) return '${diff.inDays} 天前';
  return '${isoDate(t)} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// 216 天 4 小时
String humanDuration(Duration d) {
  if (d.inDays > 0) {
    final h = d.inHours % 24;
    return h > 0 ? '${d.inDays} 天 $h 小时' : '${d.inDays} 天';
  }
  if (d.inHours > 0) return '${d.inHours} 小时 ${d.inMinutes % 60} 分';
  if (d.inMinutes > 0) return '${d.inMinutes} 分';
  return '${d.inSeconds} 秒';
}
