/// vault 的实际读写（唯一碰磁盘的地方，UI 和同步都从这里过）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/ids.dart';
import '../model/event.dart';
import '../model/note.dart';
import '../model/profile.dart';
import '../model/task.dart';
import 'layout.dart';

/// 同步用：vault 里的一个文件
class VaultFile {
  const VaultFile({required this.relPath, required this.size, required this.modified});
  final String relPath;
  final int size;
  final DateTime modified;

  @override
  String toString() => '$relPath ($size B, $modified)';
}

class VaultRepository {
  VaultRepository(this.rootPath);

  final String rootPath;

  String abs(String relPath) => p.join(rootPath, p.joinAll(relPath.split('/')));

  /// 建目录结构
  Future<void> ensureStructure() async {
    for (final d in VaultLayout.baseDirectories()) {
      await Directory(abs(d)).create(recursive: true);
    }
  }

  Future<bool> get exists => Directory(rootPath).exists();

  // ─────────────────────────── 配置 ───────────────────────────

  Future<Profile> loadProfile() async {
    final f = File(abs(VaultLayout.profilePath));
    if (!await f.exists()) return const Profile();
    try {
      final json = jsonDecode(await f.readAsString());
      if (json is Map) return Profile.fromJson(json.cast<String, dynamic>());
    } catch (_) {}
    return const Profile();
  }

  Future<void> saveProfile(Profile profile) async {
    final f = File(abs(VaultLayout.profilePath));
    await f.parent.create(recursive: true);
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(profile.toJson()));
  }

  // ─────────────────────────── 大任务 ───────────────────────────

  Future<List<TaskFile>> loadTasks() async {
    final dir = Directory(abs(VaultLayout.taskDir));
    if (!await dir.exists()) return const [];
    final files = <File>[];
    await for (final e in dir.list()) {
      if (e is File && e.path.toLowerCase().endsWith('.md')) files.add(e);
    }
    files.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

    final out = <TaskFile>[];
    for (final f in files) {
      try {
        final text = await f.readAsString();
        out.add(parseTaskFile(text, filePath: _rel(f.path)));
      } catch (_) {
        // 单个文件坏了不能拖垮整个列表
      }
    }
    return out;
  }

  Future<TaskFile> createTask({
    required String title,
    String description = '',
    DateTime? deadline,
    List<String> tags = const [],
    DateTime? now,
  }) async {
    final created = now ?? DateTime.now();
    final task = BigTask(
      id: newTaskId(),
      title: title,
      description: description,
      deadline: deadline,
      created: DateTime(created.year, created.month, created.day),
      tags: tags,
    );
    final rel = VaultLayout.taskPath(created, title);
    final raw = renderTaskFile(task);
    await writeFile(rel, raw);
    return TaskFile(task.copyWithPath(rel), raw);
  }

  Future<void> saveTaskFile(String relPath, String raw) => writeFile(relPath, raw);

  Future<void> renameTaskFile(String oldRel, String newRel) async {
    if (oldRel == newRel) return;
    final src = File(abs(oldRel));
    if (!await src.exists()) return;
    final dst = File(abs(newRel));
    await dst.parent.create(recursive: true);
    await src.rename(dst.path);
  }

  // ─────────────────────────── 杂记 ───────────────────────────

  /// 读某个月的全部杂记（日记 + 任务）
  Future<List<Note>> loadNotes(DateTime month) async {
    final out = <Note>[];
    for (final rel in [VaultLayout.diaryDir(month), VaultLayout.taskNoteDir(month)]) {
      final dir = Directory(abs(rel));
      if (!await dir.exists()) continue;
      final files = <File>[];
      await for (final e in dir.list()) {
        if (e is File && e.path.toLowerCase().endsWith('.md')) files.add(e);
      }
      files.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
      for (final f in files) {
        try {
          out.add(parseNote(await f.readAsString(), filePath: _rel(f.path)));
        } catch (_) {}
      }
    }
    return out;
  }

  Future<Note?> loadDiary(DateTime day) async {
    final f = File(abs(VaultLayout.diaryPath(day)));
    if (!await f.exists()) return null;
    return parseNote(await f.readAsString(), filePath: _rel(f.path));
  }

  /// 保存杂记（路径没给就按类型和日期生成）
  Future<Note> saveNote(Note note) async {
    var rel = note.filePath;
    if (rel.isEmpty) {
      rel = note.type == NoteType.diary
          ? VaultLayout.diaryPath(note.date)
          : VaultLayout.taskNotePath(note.date, note.taskTitle ?? note.subtaskTitle ?? '任务杂记');
    }
    await writeFile(rel, renderNote(note));
    return Note(
      id: note.id,
      type: note.type,
      date: note.date,
      body: note.body,
      taskId: note.taskId,
      taskTitle: note.taskTitle,
      subtaskTitle: note.subtaskTitle,
      mood: note.mood,
      tags: note.tags,
      filePath: rel,
    );
  }

  // ─────────────────────────── 日程 ───────────────────────────

  Future<List<CalendarEvent>> loadEvents(DateTime month) async {
    final f = File(abs(VaultLayout.eventMonthPath(month)));
    if (!await f.exists()) return const [];
    try {
      final json = jsonDecode(await f.readAsString());
      final list = (json is Map ? json['events'] : json);
      if (list is List) {
        return list
            .whereType<Map>()
            .map((e) => CalendarEvent.fromJson(e.cast<String, dynamic>()))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<void> saveEvents(DateTime month, List<CalendarEvent> events) async {
    final f = File(abs(VaultLayout.eventMonthPath(month)));
    await f.parent.create(recursive: true);
    final payload = {
      'version': 1,
      'month': VaultLayout.monthFolder(month),
      'events': events.map((e) => e.toJson()).toList(),
    };
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
  }

  // ─────────────────────────── 通用文件操作 ───────────────────────────

  Future<String?> readFileOrNull(String relPath) async {
    final f = File(abs(relPath));
    if (!await f.exists()) return null;
    return f.readAsString();
  }

  Future<void> writeFile(String relPath, String content) async {
    final f = File(abs(relPath));
    await f.parent.create(recursive: true);
    await f.writeAsString(content);
  }

  Future<void> deleteFile(String relPath) async {
    final f = File(abs(relPath));
    if (await f.exists()) await f.delete();
  }

  /// 删除 = 挪进回收站（默认留 30 天）
  Future<String> moveToTrash(String relPath, {DateTime? now}) async {
    final trashRel = VaultLayout.trashPath(relPath, now ?? DateTime.now());
    final src = File(abs(relPath));
    if (await src.exists()) {
      final dst = File(abs(trashRel));
      await dst.parent.create(recursive: true);
      await src.rename(dst.path);
    }
    return trashRel;
  }

  /// 清理超过 [keepDays] 天的回收站内容
  Future<int> cleanTrash({int keepDays = 30}) async {
    final dir = Directory(abs(VaultLayout.trashDir));
    if (!await dir.exists()) return 0;
    final deadline = DateTime.now().subtract(Duration(days: keepDays));
    var removed = 0;
    await for (final e in dir.list()) {
      final stat = await e.stat();
      if (stat.modified.isBefore(deadline)) {
        await e.delete(recursive: true);
        removed++;
      }
    }
    return removed;
  }

  /// 扫描 vault 里所有需要同步的文件（已排除回收站和临时文件）
  Future<List<VaultFile>> scanFiles() async {
    final dir = Directory(rootPath);
    if (!await dir.exists()) return const [];
    final out = <VaultFile>[];
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final rel = _rel(e.path);
      if (VaultLayout.isIgnored(rel)) continue;
      final stat = await e.stat();
      out.add(VaultFile(relPath: rel, size: stat.size, modified: stat.modified));
    }
    out.sort((a, b) => a.relPath.compareTo(b.relPath));
    return out;
  }

  String _rel(String absolute) {
    var r = p.relative(absolute, from: rootPath);
    return r.split(p.separator).join('/');
  }
}

extension on BigTask {
  BigTask copyWithPath(String path) => BigTask(
        id: id,
        title: title,
        description: description,
        deadline: deadline,
        created: created,
        tags: tags,
        subtasks: subtasks,
        filePath: path,
      );
}
