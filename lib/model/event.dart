/// 日历日程（与待办联动的那一半）。
library;

import '../core/ids.dart';
import 'task.dart' show formatDate;

class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.title,
    required this.start,
    this.end,
    this.allDay = false,
    this.done = false,
    this.taskId,
    this.note,
    this.colorIndex = 0,
  });

  final String id;
  final String title;
  final DateTime start;
  final DateTime? end;

  /// 全天事件（只有日期）
  final bool allDay;

  /// 日程也可以标记完成（用于月报统计）
  final bool done;

  /// 关联的大任务（可空）
  final String? taskId;

  final String? note;
  final int colorIndex;

  DateTime get effectiveEnd => end ?? start;

  bool onDay(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(effectiveEnd.year, effectiveEnd.month, effectiveEnd.day);
    return !d.isBefore(s) && !d.isAfter(e);
  }

  CalendarEvent copyWith({
    String? title,
    DateTime? start,
    DateTime? end,
    bool clearEnd = false,
    bool? allDay,
    bool? done,
    String? taskId,
    bool clearTaskId = false,
    String? note,
    int? colorIndex,
  }) =>
      CalendarEvent(
        id: id,
        title: title ?? this.title,
        start: start ?? this.start,
        end: clearEnd ? null : (end ?? this.end),
        allDay: allDay ?? this.allDay,
        done: done ?? this.done,
        taskId: clearTaskId ? null : (taskId ?? this.taskId),
        note: note ?? this.note,
        colorIndex: colorIndex ?? this.colorIndex,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'start': start.toIso8601String(),
        if (end != null) 'end': end!.toIso8601String(),
        'all_day': allDay,
        'done': done,
        if (taskId != null) 'task': taskId,
        if (note != null) 'note': note,
        'color': colorIndex,
      };

  static CalendarEvent fromJson(Map<String, dynamic> json) => CalendarEvent(
        id: (json['id'] ?? newEventId()).toString(),
        title: (json['title'] ?? '').toString(),
        start: DateTime.tryParse((json['start'] ?? '').toString()) ?? DateTime.now(),
        end: DateTime.tryParse((json['end'] ?? '').toString()),
        allDay: json['all_day'] == true,
        done: json['done'] == true,
        taskId: _nullable(json['task']),
        note: _nullable(json['note']),
        colorIndex: int.tryParse((json['color'] ?? '0').toString()) ?? 0,
      );

  /// 给人看的日期范围文案
  String get timeLabel {
    if (allDay) return '全天';
    final s = '${_two(start.hour)}:${_two(start.minute)}';
    if (end == null) return s;
    return '$s-${_two(end!.hour)}:${_two(end!.minute)}';
  }

  String get dateLabel => formatDate(start);
}

String? _nullable(Object? v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

String _two(int n) => n.toString().padLeft(2, '0');
