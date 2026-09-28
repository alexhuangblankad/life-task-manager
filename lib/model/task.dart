/// 大任务 / 小任务的数据模型，以及「任务 Markdown 文件」的解析与修改。
///
/// 文件长这样（一个文件 = 一个大任务，Obsidian Tasks 插件能直接认）：
///
///     ---
///     id: t-7k3m9q
///     type: 大任务
///     title: 草坪机器人毕设
///     deadline: 2027-05-30
///     created: 2026-09-28
///     tags: [毕设, 机器人]
///     ---
///
///     # 草坪机器人毕设
///
///     描述文字……
///
///     ## 子任务
///
///     - [ ] 写完开题报告 📅 2026-10-10 ⏫ ^s-a1b2c3
///     - [x] 选好仿真软件 ✅ 2026-09-20 ^s-d4e5f6
///
/// 设计原则：**一行 = 一个小任务**，行尾 `^s-xxxxxx` 是稳定 ID。
/// 修改只做「行级手术」——只替换命中的那一行，用户手写的其它内容一个字节都不动。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../core/front_matter.dart';
import '../core/ids.dart';

/// 优先级
class Priority {
  static const int none = 0;
  static const int low = 1;
  static const int medium = 2;
  static const int high = 3;

  static const Map<int, String> marks = {low: '🔽', medium: '🔼', high: '⏫'};
  static const Map<int, String> labels = {none: '无', low: '低', medium: '中', high: '高'};
}

class SubTask {
  const SubTask({
    required this.id,
    required this.title,
    this.done = false,
    this.due,
    this.scheduled,
    this.doneAt,
    this.priority = Priority.none,
    this.tags = const [],
  });

  final String id;
  final String title;
  final bool done;

  /// 截止日期 📅（最晚什么时候做完）
  final DateTime? due;

  /// 计划哪天做 ⏳（想做/打算那天做的事，不一定有截止日期）
  final DateTime? scheduled;

  final DateTime? doneAt;
  final int priority;
  final List<String> tags;

  bool isOverdueAt(DateTime now) =>
      !done && due != null && due!.isBefore(DateTime(now.year, now.month, now.day));

  bool isPlannedOn(DateTime day) =>
      scheduled != null &&
      scheduled!.year == day.year &&
      scheduled!.month == day.month &&
      scheduled!.day == day.day;

  bool isDueOn(DateTime day) =>
      due != null && due!.year == day.year && due!.month == day.month && due!.day == day.day;

  SubTask copyWith({
    String? title,
    bool? done,
    DateTime? due,
    bool clearDue = false,
    DateTime? scheduled,
    bool clearScheduled = false,
    DateTime? doneAt,
    bool clearDoneAt = false,
    int? priority,
    List<String>? tags,
  }) =>
      SubTask(
        id: id,
        title: title ?? this.title,
        done: done ?? this.done,
        due: clearDue ? null : (due ?? this.due),
        scheduled: clearScheduled ? null : (scheduled ?? this.scheduled),
        doneAt: clearDoneAt ? null : (doneAt ?? this.doneAt),
        priority: priority ?? this.priority,
        tags: tags ?? this.tags,
      );
}

class BigTask {
  const BigTask({
    required this.id,
    required this.title,
    this.description = '',
    this.deadline,
    this.created,
    this.tags = const [],
    this.subtasks = const [],
    this.filePath = '',
  });

  final String id;
  final String title;
  final String description;
  final DateTime? deadline;
  final DateTime? created;
  final List<String> tags;
  final List<SubTask> subtasks;

  /// vault 相对路径
  final String filePath;

  int get doneCount => subtasks.where((s) => s.done).length;
  int get totalCount => subtasks.length;
  double get progress => subtasks.isEmpty ? 0 : doneCount / subtasks.length;

  /// 大任务自动截止日 = 显式 deadline，或未完成小任务里最晚的 due
  DateTime? get effectiveDeadline {
    if (deadline != null) return deadline;
    final dues = subtasks.where((s) => !s.done && s.due != null).map((s) => s.due!).toList()..sort();
    return dues.isEmpty ? null : dues.last;
  }

  SubTask? subtaskById(String id) {
    for (final s in subtasks) {
      if (s.id == id) return s;
    }
    return null;
  }
}

/// 一个任务文件的解析结果
class TaskFile {
  const TaskFile(this.task, this.raw);
  final BigTask task;

  /// 原始文件内容，行级修改要在它上面做
  final String raw;
}

// ────────────────────────────── 解析 ──────────────────────────────

final RegExp _checkboxLine = RegExp(r'^(\s*)- \[([ xX])\]\s+(.*)$');
final RegExp _dueMark = RegExp('📅\\s*(\\d{4}-\\d{2}-\\d{2})');
final RegExp _scheduledMark = RegExp('⏳\\s*(\\d{4}-\\d{2}-\\d{2})');
final RegExp _doneMark = RegExp('✅\\s*(\\d{4}-\\d{2}-\\d{2})');
final RegExp _idMark = RegExp(r'\s+\^([A-Za-z0-9_-]{2,})\s*$');
final RegExp _tagMark = RegExp(r'(?:^|\s)#([^\s#]+)');

TaskFile parseTaskFile(String raw, {String filePath = ''}) {
  final fm = parseFrontMatter(raw);
  final data = fm.data;

  final bodyLines = fm.body.split('\n');
  String? headingTitle;
  for (final line in bodyLines) {
    final t = line.trim();
    if (t.startsWith('# ')) {
      headingTitle = t.substring(2).trim();
      break;
    }
  }

  final subtasks = <SubTask>[];
  for (final line in bodyLines) {
    final st = parseSubtaskLine(line);
    if (st != null) subtasks.add(st);
  }

  final id = (data['id'] as String?)?.trim();
  final title = ((data['title'] as String?)?.trim().isNotEmpty ?? false)
      ? (data['title'] as String).trim()
      : (headingTitle ?? _fallbackTitle(filePath));

  return TaskFile(
    BigTask(
      id: (id == null || id.isEmpty) ? newTaskId() : id,
      title: title,
      description: _extractDescription(bodyLines),
      deadline: parseDate(data['deadline']),
      created: parseDate(data['created']),
      tags: _asStringList(data['tags']),
      subtasks: subtasks,
      filePath: filePath,
    ),
    raw,
  );
}

/// 解析一行小任务；不是任务行就返回 null。
///
/// 用户手写的任务行往往没有 `^id`。这时**不能用随机 ID**：每次解析都会变，
/// 写回文件时按 ID 找不到那一行，表现为「这个勾怎么点都不动」。
/// 用内容哈希生成稳定 ID；第一次被改写时会把 `^id` 正式写进文件（自愈）。
String derivedSubtaskId(String line) {
  final digest = sha1.convert(utf8.encode(line.trim())).toString();
  return 'h-${digest.substring(0, 8)}';
}

SubTask? parseSubtaskLine(String line) {
  final m = _checkboxLine.firstMatch(line);
  if (m == null) return null;

  var rest = m.group(3)!.trim();
  String? id;
  final idMatch = _idMark.firstMatch(rest);
  if (idMatch != null) {
    id = idMatch.group(1);
    rest = rest.substring(0, idMatch.start).trimRight();
  }

  DateTime? due;
  final dueMatch = _dueMark.firstMatch(rest);
  if (dueMatch != null) {
    due = _parseIsoDate(dueMatch.group(1)!);
    rest = (rest.substring(0, dueMatch.start) + rest.substring(dueMatch.end)).trim();
  }

  DateTime? scheduled;
  final schedMatch = _scheduledMark.firstMatch(rest);
  if (schedMatch != null) {
    scheduled = _parseIsoDate(schedMatch.group(1)!);
    rest = (rest.substring(0, schedMatch.start) + rest.substring(schedMatch.end)).trim();
  }

  DateTime? doneAt;
  final doneMatch = _doneMark.firstMatch(rest);
  if (doneMatch != null) {
    doneAt = _parseIsoDate(doneMatch.group(1)!);
    rest = (rest.substring(0, doneMatch.start) + rest.substring(doneMatch.end)).trim();
  }

  var priority = Priority.none;
  for (final entry in Priority.marks.entries) {
    if (rest.contains(entry.value)) {
      priority = entry.key;
      rest = rest.replaceAll(entry.value, '');
    }
  }

  final tags = _tagMark.allMatches(rest).map((e) => e.group(1)!).where((t) => t.length < 40).toList();
  rest = rest.replaceAll(_tagMark, ' ');

  final title = rest.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  if (title.isEmpty) return null;

  return SubTask(
    id: id ?? derivedSubtaskId(line),
    title: title,
    done: m.group(2)!.toLowerCase() == 'x',
    due: due,
    scheduled: scheduled,
    doneAt: doneAt,
    priority: priority,
    tags: tags,
  );
}

// ────────────────────────────── 渲染 ──────────────────────────────

/// 渲染一行小任务（顺序：标题 ⏳计划 📅截止 优先级 ✅完成 #标签 ^id）
String renderSubtaskLine(SubTask st, {String indent = ''}) {
  final buf = StringBuffer('$indent- [${st.done ? 'x' : ' '}] ${st.title}');
  if (st.scheduled != null) buf.write(' ⏳ ${formatDate(st.scheduled!)}');
  if (st.due != null) buf.write(' 📅 ${formatDate(st.due!)}');
  final mark = Priority.marks[st.priority];
  if (mark != null) buf.write(' $mark');
  if (st.done && st.doneAt != null) buf.write(' ✅ ${formatDate(st.doneAt!)}');
  if (st.tags.isNotEmpty) buf.write(' ${st.tags.map((t) => '#$t').join(' ')}');
  buf.write(' ^${st.id}');
  return buf.toString();
}

/// 从零生成一个大任务文件（新建任务时用）
String renderTaskFile(BigTask task) {
  final buf = StringBuffer()
    ..writeln('---')
    ..writeln('id: ${task.id}')
    ..writeln('type: 大任务')
    ..writeln('title: ${_quoteIfNeeded(task.title)}')
    ..writeln('created: ${formatDate(task.created ?? DateTime.now())}');
  if (task.deadline != null) buf.writeln('deadline: ${formatDate(task.deadline!)}');
  if (task.tags.isNotEmpty) buf.writeln('tags: [${task.tags.join(', ')}]');
  buf
    ..writeln('---')
    ..writeln()
    ..writeln('# ${task.title}');
  if (task.description.trim().isNotEmpty) {
    buf
      ..writeln()
      ..writeln(task.description.trim());
  }
  buf
    ..writeln()
    ..writeln('## 子任务')
    ..writeln();
  for (final st in task.subtasks) {
    buf.writeln(renderSubtaskLine(st));
  }
  return buf.toString();
}

// ─────────────────────── 行级手术（保用户原文） ───────────────────────

/// 勾选/取消勾选某个小任务，只改那一行。
String setSubtaskDone(String raw, String subtaskId, bool done, {DateTime? now}) {
  return _replaceSubtaskLine(raw, subtaskId, (st) {
    final date = (now ?? DateTime.now());
    return st.copyWith(
      done: done,
      doneAt: done ? DateTime(date.year, date.month, date.day) : null,
      clearDoneAt: !done,
    );
  });
}

/// 改写某个小任务（改标题/截止/优先级等），只改那一行。
String updateSubtask(String raw, SubTask updated) =>
    _replaceSubtaskLine(raw, updated.id, (_) => updated);

/// 删除某个小任务行。
String removeSubtask(String raw, String subtaskId) {
  final nl = _newlineOf(raw);
  final lines = _normalize(raw).split('\n');
  final out = <String>[];
  var removed = false;
  for (final line in lines) {
    final st = parseSubtaskLine(line);
    if (!removed && st != null && st.id == subtaskId) {
      removed = true;
      continue;
    }
    out.add(line);
  }
  return out.join(nl);
}

/// 追加一个小任务：优先塞进 `## 子任务` 区块，没有该区块就在文件末尾新建。
String appendSubtask(String raw, SubTask st) {
  final nl = _newlineOf(raw);
  final lines = _normalize(raw).split('\n');

  var sectionStart = -1;
  for (var i = 0; i < lines.length; i++) {
    final t = lines[i].trim();
    if (t == '## 子任务' || t == '## 子任务清单' || t == '## Tasks') {
      sectionStart = i;
      break;
    }
  }

  final lineText = renderSubtaskLine(st);

  if (sectionStart < 0) {
    final tail = lines.isNotEmpty && lines.last.trim().isEmpty ? '' : nl;
    return '${lines.join(nl)}$tail## 子任务$nl$nl$lineText$nl';
  }

  // 找到该区块的结尾（下一个 ## 标题 或 文件末尾），插在最后一个任务行之后
  var insertAt = sectionStart + 1;
  for (var i = sectionStart + 1; i < lines.length; i++) {
    final t = lines[i].trim();
    if (t.startsWith('## ')) break;
    if (parseSubtaskLine(lines[i]) != null) insertAt = i + 1;
  }
  lines.insert(insertAt, lineText);
  return lines.join(nl);
}

String _replaceSubtaskLine(String raw, String subtaskId, SubTask Function(SubTask) change) {
  final nl = _newlineOf(raw);
  final lines = _normalize(raw).split('\n');
  for (var i = 0; i < lines.length; i++) {
    final st = parseSubtaskLine(lines[i]);
    if (st != null && st.id == subtaskId) {
      final indent = _checkboxLine.firstMatch(lines[i])?.group(1) ?? '';
      lines[i] = renderSubtaskLine(change(st), indent: indent);
      return lines.join(nl);
    }
  }
  return raw; // 没找到就原样返回，绝不乱改
}

// ────────────────────────────── 工具 ──────────────────────────────

String formatDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? parseDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  final s = value.toString().trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

DateTime? _parseIsoDate(String s) => DateTime.tryParse(s);

List<String> _asStringList(Object? value) {
  if (value == null) return const [];
  if (value is List) return value.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
  final s = value.toString().trim();
  return s.isEmpty ? const [] : [s];
}

String _fallbackTitle(String filePath) {
  if (filePath.isEmpty) return '未命名任务';
  final name = filePath.split(RegExp(r'[/\\]')).last;
  return name.endsWith('.md') ? name.substring(0, name.length - 3) : name;
}

String _extractDescription(List<String> bodyLines) {
  final buf = <String>[];
  var seenHeading = false;
  for (final line in bodyLines) {
    final t = line.trim();
    if (!seenHeading) {
      if (t.startsWith('# ')) seenHeading = true;
      continue;
    }
    if (t.startsWith('## ')) break;
    buf.add(line);
  }
  return buf.join('\n').trim();
}

String _quoteIfNeeded(String s) {
  if (s.isEmpty) return "''";
  if (RegExp(r'^[\s\[{&*#?|<>=!%@`"' + "'" + r':]').hasMatch(s) || s.contains(': ') || s.contains('#')) {
    return '"${s.replaceAll('"', r'\"')}"';
  }
  return s;
}

String _normalize(String s) => s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

String _newlineOf(String s) => s.contains('\r\n') ? '\r\n' : '\n';

// front-matter 的解析统一在 lib/core/front_matter.dart，这里不再重复实现。
