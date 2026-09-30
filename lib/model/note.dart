/// 杂记（两种：任务杂记 / 日记杂记）。
///
/// 存成 md，按「月」分文件夹：
///
///     杂记/202609/日记/2026-09-28.md
///     杂记/202609/任务/2026-09-28_草坪机器人毕设.md
///
/// 任务杂记靠 front-matter 里的 `task` / `subtask` 字段和待办互通；
/// 日记杂记靠文件名里的日期和日历的天互通。
library;

import '../core/front_matter.dart';
import '../core/ids.dart';
import 'task.dart';

enum NoteType {
  diary('日记'),
  task('任务');

  const NoteType(this.label);
  final String label;

  static NoteType fromLabel(String s) {
    for (final t in NoteType.values) {
      if (t.label == s) return t;
    }
    return NoteType.diary;
  }
}

class Note {
  const Note({
    required this.id,
    required this.type,
    required this.date,
    this.body = '',
    this.taskId,
    this.taskTitle,
    this.subtaskId,
    this.subtaskTitle,
    this.mood,
    this.tags = const [],
    this.filePath = '',
  });

  final String id;
  final NoteType type;

  /// 归属日期（日记=当天；任务杂记=完成那天）
  final DateTime date;

  final String body;

  /// 任务杂记：关联的大任务 ID
  final String? taskId;
  final String? taskTitle;

  /// 任务杂记：关联的小任务 ID（老杂记没有这个字段，那时只记了标题）
  final String? subtaskId;

  /// 任务杂记：如果是完成某个小任务时写的，记下它的标题
  final String? subtaskTitle;

  /// 心情 1-5（可选）
  final int? mood;

  final List<String> tags;

  /// vault 相对路径
  final String filePath;

  bool get isEmpty => body.trim().isEmpty;

  /// 这条杂记是不是挂在小任务 [id]（标题叫 [title]）名下。
  /// 有 ID 就按 ID 认（改过名的也能认出来）；老杂记没有 ID，退回按标题认。
  bool belongsToSubtask(String id, String title) {
    if (subtaskId != null) return subtaskId == id;
    return subtaskTitle == title;
  }

  Note copyWith({
    String? body,
    int? mood,
    bool clearMood = false,
    List<String>? tags,
    String? filePath,
    String? subtaskId,
    String? subtaskTitle,
  }) =>
      Note(
        id: id,
        type: type,
        date: date,
        body: body ?? this.body,
        taskId: taskId,
        taskTitle: taskTitle,
        subtaskId: subtaskId ?? this.subtaskId,
        subtaskTitle: subtaskTitle ?? this.subtaskTitle,
        mood: clearMood ? null : (mood ?? this.mood),
        tags: tags ?? this.tags,
        filePath: filePath ?? this.filePath,
      );
}

Note parseNote(String raw, {String filePath = ''}) {
  final fm = parseFrontMatter(raw);
  final data = fm.data;

  var date = parseDate(data['date']);
  if (date == null) {
    // 退路：从文件名 2026-09-28 或 2026-09-28_xxx 里抠
    final name = filePath.split(RegExp(r'[/\\]')).last;
    final m = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(name);
    if (m != null) {
      date = DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
    }
  }
  date ??= DateTime.now();

  final rawId = (data['id'] as String?)?.trim();
  final moodRaw = data['mood'];
  int? mood;
  if (moodRaw is int) {
    mood = moodRaw;
  } else if (moodRaw != null) {
    mood = int.tryParse(moodRaw.toString().trim());
  }

  return Note(
    id: (rawId == null || rawId.isEmpty) ? newNoteId() : rawId,
    type: NoteType.fromLabel((data['type'] as String?)?.trim() ?? '日记'),
    date: DateTime(date.year, date.month, date.day),
    body: fm.body.trimRight(),
    taskId: _nullable(data['task']),
    taskTitle: _nullable(data['task_title']),
    subtaskId: _nullable(data['subtask_id']),
    subtaskTitle: _nullable(data['subtask']),
    mood: mood,
    tags: _asStringList(data['tags']),
    filePath: filePath,
  );
}

String renderNote(Note note) {
  final buf = StringBuffer()
    ..writeln('---')
    ..writeln('id: ${note.id}')
    ..writeln('type: ${note.type.label}')
    ..writeln('date: ${formatDate(note.date)}');
  if (note.taskId != null) buf.writeln('task: ${note.taskId}');
  if (note.taskTitle != null) buf.writeln('task_title: ${_q(note.taskTitle!)}');
  if (note.subtaskId != null) buf.writeln('subtask_id: ${note.subtaskId}');
  if (note.subtaskTitle != null) buf.writeln('subtask: ${_q(note.subtaskTitle!)}');
  if (note.mood != null) buf.writeln('mood: ${note.mood}');
  if (note.tags.isNotEmpty) buf.writeln('tags: [${note.tags.join(', ')}]');
  buf
    ..writeln('---')
    ..writeln();
  final body = note.body.trim();
  if (body.isNotEmpty) {
    buf
      ..writeln(body)
      ..writeln();
  }
  return buf.toString();
}

/// 在已有日记里追加一段（同一天写第二条时不覆盖）
String appendToNote(String raw, String addition) {
  final text = raw.replaceAll('\r\n', '\n');
  final trimmed = text.trimRight();
  final add = addition.trim();
  if (add.isEmpty) return raw;
  return '$trimmed\n\n$add\n';
}

String? _nullable(Object? v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

List<String> _asStringList(Object? value) {
  if (value == null) return const [];
  if (value is List) return value.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
  final s = value.toString().trim();
  return s.isEmpty ? const [] : [s];
}

String _q(String s) {
  if (s.isEmpty) return "''";
  if (s.contains(': ') || s.contains('#') || s.startsWith(' ') || s.endsWith(' ')) {
    return '"${s.replaceAll('"', r'\"')}"';
  }
  return s;
}

// front-matter 的解析统一在 lib/core/front_matter.dart，这里不再重复实现。
