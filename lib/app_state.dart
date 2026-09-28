/// 全局状态：UI 只跟它打交道，它负责读写 vault、跑同步、驱动倒计时刷新。
library;

import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/foundation.dart';

import 'core/countdown.dart';
import 'core/device_config.dart';
import 'core/front_matter.dart';
import 'core/ids.dart';
import 'model/event.dart';
import 'model/note.dart';
import 'model/profile.dart';
import 'model/task.dart';
import 'sync/sync_engine.dart';
import 'sync/webdav.dart';
import 'vault/layout.dart';
import 'vault/repository.dart';

class AppState extends ChangeNotifier {
  AppState({DeviceConfigStore? store}) : _store = store ?? DeviceConfigStore();

  final DeviceConfigStore _store;
  DeviceConfig device = DeviceConfig();
  VaultRepository repo = VaultRepository(defaultVaultPath());

  Profile profile = const Profile();
  List<TaskFile> tasks = const [];
  List<CalendarEvent> events = const [];
  List<Note> notes = const [];

  /// 当前查看的月份（日历/杂记共用）
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);

  /// 每秒滴答一次，只让倒计时那块重建
  final ValueNotifier<DateTime> tick = ValueNotifier<DateTime>(DateTime.now());

  Timer? _timer;
  bool ready = false;
  bool busy = false;
  String? status;
  SyncReport? lastSyncReport;
  final List<String> syncLog = [];

  String get vaultPath => device.vaultPath;

  @override
  void dispose() {
    _timer?.cancel();
    tick.dispose();
    super.dispose();
  }

  // ─────────────────────── 启动 ───────────────────────

  Future<void> bootstrap() async {
    device = await _store.load();
    repo = VaultRepository(device.vaultPath);
    await repo.ensureStructure();
    await _loadAll();
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => tick.value = DateTime.now());
    ready = true;
    notifyListeners();
  }

  Future<void> _loadAll() async {
    profile = await repo.loadProfile();
    tasks = await repo.loadTasks();
    await reloadMonth(month, notify: false);
  }

  Future<void> reloadAll() async {
    await _loadAll();
    notifyListeners();
  }

  Future<void> reloadMonth(DateTime m, {bool notify = true}) async {
    month = DateTime(m.year, m.month);
    events = await repo.loadEvents(month);
    notes = await repo.loadNotes(month);
    if (notify) notifyListeners();
  }

  // ─────────────────────── 人生期限 ───────────────────────

  Future<void> saveProfile(Profile p) async {
    profile = p;
    await repo.saveProfile(p);
    notifyListeners();
  }

  // ─────────────────────── 大任务 / 小任务 ───────────────────────

  Future<TaskFile> createTask({
    required String title,
    String description = '',
    DateTime? deadline,
    List<String> tags = const [],
  }) async {
    final created = await repo.createTask(
      title: title,
      description: description,
      deadline: deadline,
      tags: tags,
    );
    tasks = await repo.loadTasks();
    notifyListeners();
    return created;
  }

  Future<void> _rewriteTask(TaskFile tf, String Function(String raw) change) async {
    final raw = await repo.readFileOrNull(tf.task.filePath) ?? tf.raw;
    final updated = change(raw);
    if (updated != raw) await repo.saveTaskFile(tf.task.filePath, updated);
    tasks = await repo.loadTasks();
    notifyListeners();
  }

  Future<void> toggleSubtask(TaskFile tf, String subtaskId, bool done) =>
      _rewriteTask(tf, (raw) => setSubtaskDone(raw, subtaskId, done));

  Future<void> addSubtask(TaskFile tf, SubTask st) => _rewriteTask(tf, (raw) => appendSubtask(raw, st));

  Future<void> editSubtask(TaskFile tf, SubTask st) => _rewriteTask(tf, (raw) => updateSubtask(raw, st));

  Future<void> deleteSubtask(TaskFile tf, String subtaskId) =>
      _rewriteTask(tf, (raw) => removeSubtask(raw, subtaskId));

  /// 把大任务的标题/描述/截止日期写回 front-matter 和正文
  Future<void> updateTaskMeta(TaskFile tf, {String? title, String? description, DateTime? deadline, bool clearDeadline = false}) async {
    final patch = <String, dynamic>{
      'title': title ?? tf.task.title,
      if (deadline != null) 'deadline': formatDate(deadline),
      if (clearDeadline) 'deadline': null,
    };
    final raw = await repo.readFileOrNull(tf.task.filePath) ?? tf.raw;
    var updated = upsertFrontMatter(raw, patch);
    if (description != null) {
      updated = _replaceDescription(updated, tf.task.title, description);
    }
    await repo.saveTaskFile(tf.task.filePath, updated);
    tasks = await repo.loadTasks();
    notifyListeners();
  }

  Future<void> deleteTask(TaskFile tf) async {
    await repo.moveToTrash(tf.task.filePath);
    tasks = await repo.loadTasks();
    notifyListeners();
  }

  // ─────────────────────── 杂记 ───────────────────────

  /// 写/追加当天日记
  Future<Note> saveDiary(DateTime day, String body) async {
    final rel = VaultLayout.diaryPath(day);
    final existingRaw = await repo.readFileOrNull(rel);
    if (existingRaw == null) {
      final note = Note(id: newNoteId(), type: NoteType.diary, date: day, body: body);
      final saved = await repo.saveNote(note);
      await reloadMonth(month);
      return saved;
    }
    final text = appendToNote(existingRaw, body);
    await repo.writeFile(rel, text);
    await reloadMonth(month);
    return parseNote(text, filePath: rel);
  }

  /// 完成任务后写的任务杂记
  Future<Note> saveTaskNote({
    required DateTime day,
    required String body,
    required String taskTitle,
    String? taskId,
    String? subtaskTitle,
    int? mood,
  }) async {
    final note = Note(
      id: newNoteId(),
      type: NoteType.task,
      date: DateTime(day.year, day.month, day.day),
      body: body,
      taskId: taskId,
      taskTitle: taskTitle,
      subtaskTitle: subtaskTitle,
      mood: mood,
    );
    final saved = await repo.saveNote(note);
    await reloadMonth(month);
    return saved;
  }

  Future<void> updateNote(Note note) async {
    await repo.saveNote(note);
    await reloadMonth(month);
  }

  Future<void> deleteNote(Note note) async {
    if (note.filePath.isEmpty) return;
    await repo.moveToTrash(note.filePath);
    await reloadMonth(month);
  }

  /// 某天的日记（跨月也能取）
  Future<Note?> diaryOf(DateTime day) => repo.loadDiary(day);

  /// 某个大任务相关的全部任务杂记
  List<Note> notesForTask(String taskId) =>
      notes.where((n) => n.taskId == taskId).toList();

  // ─────────────────────── 日程 ───────────────────────

  Future<void> upsertEvent(CalendarEvent event) async {
    final list = [...events];
    final i = list.indexWhere((e) => e.id == event.id);
    if (i >= 0) {
      list[i] = event;
    } else {
      list.add(event);
    }
    await repo.saveEvents(month, list);
    events = await repo.loadEvents(month);
    notifyListeners();
  }

  Future<void> deleteEvent(String id) async {
    final list = events.where((e) => e.id != id).toList();
    await repo.saveEvents(month, list);
    events = await repo.loadEvents(month);
    notifyListeners();
  }

  List<CalendarEvent> eventsOfDay(DateTime day) => events.where((e) => e.onDay(day)).toList();

  /// 某天到期的小任务（日历要和待办联动，靠的就是这个）
  List<({TaskFile task, SubTask subtask})> subtasksDueOn(DateTime day) {
    final out = <({TaskFile task, SubTask subtask})>[];
    for (final tf in tasks) {
      for (final st in tf.task.subtasks) {
        if (st.due == null) continue;
        if (st.due!.year == day.year && st.due!.month == day.month && st.due!.day == day.day) {
          out.add((task: tf, subtask: st));
        }
      }
    }
    return out;
  }

  /// 某天「打算做」的小任务（⏳ 计划日期；很多事没有截止日期，只有想哪天做）
  List<({TaskFile task, SubTask subtask})> subtasksPlannedOn(DateTime day) {
    final out = <({TaskFile task, SubTask subtask})>[];
    for (final tf in tasks) {
      for (final st in tf.task.subtasks) {
        if (st.isPlannedOn(day)) out.add((task: tf, subtask: st));
      }
    }
    return out;
  }

  /// 今天要做的事（计划日期是今天，或截止日期是今天/已逾期）
  List<({TaskFile task, SubTask subtask})> get todayFocus {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final out = <({TaskFile task, SubTask subtask})>[];
    final seen = <String>{};
    for (final tf in tasks) {
      for (final st in tf.task.subtasks) {
        if (st.done) continue;
        final planned = st.isPlannedOn(today);
        final due = st.due != null && !st.due!.isAfter(today);
        if (planned || due) {
          if (seen.add(st.id)) out.add((task: tf, subtask: st));
        }
      }
    }
    return out;
  }

  // ─────────────────────── 外观 ───────────────────────

  ThemeMode get themeMode => switch (device.themeMode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  Future<void> setThemeMode(String mode) async {
    device.themeMode = mode;
    notifyListeners();
    await saveDeviceConfig();
  }

  /// 托盘提示文字（人生倒计时，没设置就显示最近的任务 deadline）
  String get trayTooltip {
    final target = profile.lifeTarget;
    if (target != null && profile.lifeCountdownEnabled) {
      final c = computeCountdown(DateTime.now(), target, start: profile.lifeStart);
      return '人生任务管理器 · 还剩 ${c.years} 年 ${c.days} 天';
    }
    final next = allSubtasksWithDue;
    if (next.isEmpty) return '人生任务管理器';
    final days = calendarDaysBetween(DateTime.now(), next.first.subtask.due!);
    return '人生任务管理器 · ${next.first.subtask.title} 还剩 $days 天';
  }

  // ─────────────────────── 同步 ───────────────────────

  Future<void> saveDeviceConfig() async {
    await _store.save(device);
    notifyListeners();
  }

  Future<void> changeVaultPath(String path) async {
    device.vaultPath = path;
    repo = VaultRepository(path);
    await repo.ensureStructure();
    await saveDeviceConfig();
    await _loadAll();
    notifyListeners();
  }

  /// 测试 WebDAV 连接（设置页按钮）
  Future<String> testWebdav() async {
    final cfg = device.webdav;
    if (!cfg.usable) return '请先填写地址和账号';
    final client = WebdavClient(
      baseUrl: cfg.url,
      username: cfg.username,
      password: cfg.password,
      remoteRoot: cfg.remoteRoot,
    );
    try {
      return await client.testConnection();
    } catch (e) {
      return '连接失败：$e';
    } finally {
      client.close();
    }
  }

  Future<SyncReport?> syncNow({bool dryRun = false}) async {
    final cfg = device.webdav;
    if (!cfg.usable) {
      status = '还没配置 WebDAV，先到「设置」里填坚果云账号';
      notifyListeners();
      return null;
    }
    busy = true;
    syncLog.clear();
    notifyListeners();

    final client = WebdavClient(
      baseUrl: cfg.url,
      username: cfg.username,
      password: cfg.password,
      remoteRoot: cfg.remoteRoot,
    );
    try {
      final engine = SyncEngine(
        repo: repo,
        backend: client,
        stateStore: SyncStateStore(_syncStatePath),        deviceName: device.deviceName,
        remoteRoot: cfg.remoteRoot,
      );
      final report = await engine.sync(dryRun: dryRun, onLog: syncLog.add);
      lastSyncReport = report;
      status = report.summary;
      if (!dryRun) {
        device.lastSyncAt = DateTime.now();
        await saveDeviceConfig();
        await _loadAll();
      }
      return report;
    } catch (e) {
      status = '同步失败：$e';
      return null;
    } finally {
      client.close();
      busy = false;
      notifyListeners();
    }
  }

  /// 同步状态文件放在 vault 同级（不进 vault，免得被同步来同步去）
  String get _syncStatePath {
    final v = device.vaultPath.replaceAll('\\', '/');
    final idx = v.lastIndexOf('/');
    final parent = idx > 0 ? v.substring(0, idx) : v;
    return '$parent/.ltm_sync_state.json';
  }

  List<({TaskFile task, SubTask subtask})> get allSubtasksWithDue {
    final out = <({TaskFile task, SubTask subtask})>[];
    for (final tf in tasks) {
      for (final st in tf.task.subtasks) {
        if (st.due != null && !st.done) out.add((task: tf, subtask: st));
      }
    }
    out.sort((a, b) => a.subtask.due!.compareTo(b.subtask.due!));
    return out;
  }
}

/// 替换大任务正文里的描述（标题和下一个 ## 之间那段）
String _replaceDescription(String raw, String title, String description) {
  final nl = raw.contains('\r\n') ? '\r\n' : '\n';
  final lines = raw.replaceAll('\r\n', '\n').split('\n');
  var start = -1;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trim() == '# $title') {
      start = i;
      break;
    }
  }
  if (start < 0) return raw;
  var end = lines.length;
  for (var i = start + 1; i < lines.length; i++) {
    if (lines[i].trim().startsWith('## ')) {
      end = i;
      break;
    }
  }
  final newBlock = description.trim().isEmpty ? <String>[] : ['', description.trim()];
  final out = [...lines.sublist(0, start + 1), ...newBlock, ...lines.sublist(end)];
  return out.join(nl);
}
