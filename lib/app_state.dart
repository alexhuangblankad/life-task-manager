/// 全局状态：UI 只跟它打交道，它负责读写 vault、跑同步、驱动倒计时刷新。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';

import 'core/countdown.dart';
import 'core/device_config.dart';
import 'core/front_matter.dart';
import 'core/history_today.dart';
import 'core/ids.dart';
import 'core/llm_client.dart';
import 'core/reminder.dart';
import 'core/report.dart';
import 'model/ai_config.dart';
import 'model/event.dart';
import 'model/note.dart';
import 'model/profile.dart';
import 'model/report_cycle.dart';
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
    await _loadRepeatDone();
    await reloadMonth(month, notify: false);
  }

  // ─────────────────────── 重复任务（定时任务）───────────────────────

  /// {小任务ID: {做过的日期}}
  Map<String, Set<String>> repeatDone = {};

  static String dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _loadRepeatDone() async {
    repeatDone = {};
    try {
      final raw = await repo.readFileOrNull(VaultLayout.repeatDonePath);
      if (raw == null) return;
      final json = jsonDecode(raw);
      if (json is Map) {
        json.forEach((k, v) {
          if (v is List) repeatDone[k.toString()] = v.map((e) => e.toString()).toSet();
        });
      }
    } catch (_) {}
  }

  Future<void> _saveRepeatDone() async {
    final sorted = repeatDone.map((k, v) => MapEntry(k, (v.toList()..sort())));
    await repo.writeFile(
      VaultLayout.repeatDonePath,
      const JsonEncoder.withIndent(' ').convert(sorted),
    );
  }

  /// 这个重复任务在这一天是不是已经做过了
  bool isRepeatDoneOn(String subtaskId, DateTime day) =>
      repeatDone[subtaskId]?.contains(dateKey(day)) ?? false;

  /// 重复任务：切换「这一天做过」（和普通任务的完成标记分开记）
  Future<void> toggleRepeatDone(String subtaskId, DateTime day) async {
    final set = repeatDone.putIfAbsent(subtaskId, () => <String>{});
    final key = dateKey(day);
    if (!set.remove(key)) set.add(key);
    await _saveRepeatDone();
    notifyListeners();
  }

  /// 这一天该做的重复任务
  List<({TaskFile task, SubTask subtask})> repeatsOn(DateTime day) {
    final out = <({TaskFile task, SubTask subtask})>[];
    for (final tf in tasks) {
      for (final st in tf.task.subtasks) {
        if (st.isRepeating && st.repeatsOn(day)) out.add((task: tf, subtask: st));
      }
    }
    return out;
  }

  /// 所有重复任务（按下次发生时间排序），放在待办页/倒计时页用
  List<({TaskFile task, SubTask subtask, DateTime next, int daysLeft})> get upcomingRepeats {
    final now = DateTime.now();
    final out = <({TaskFile task, SubTask subtask, DateTime next, int daysLeft})>[];
    for (final tf in tasks) {
      for (final st in tf.task.subtasks) {
        if (!st.isRepeating) continue;
        final next = st.repeat!.nextOccurrence(now);
        if (next == null) continue;
        out.add((task: tf, subtask: st, next: next, daysLeft: st.repeat!.daysUntilNext(now) ?? 0));
      }
    }
    out.sort((a, b) => a.next.compareTo(b.next));
    return out;
  }

  // ─────────────────────── 历史上的今天 ───────────────────────

  HistoryToday? history;

  /// 首次用到时才解析那份 520KB 的数据
  Future<void> ensureHistory() async {
    if (history != null) return;
    try {
      history = await HistoryToday.load();
      notifyListeners();
    } catch (_) {
      // 数据坏了也不能让日历打不开
    }
  }

  CalendarPrefs get calendarPrefs => profile.calendar;

  Future<void> saveCalendarPrefs(CalendarPrefs prefs) =>
      saveProfile(profile.copyWith(calendar: prefs));

  // ─────────────────────── 提醒 ───────────────────────

  ReminderService? _reminder;
  String? _localDir;

  Future<void> startReminders(String localDir) async {
    _localDir = localDir;
    _reminder ??= ReminderService(
      collect: reminderItems,
      storePath: '$localDir/notified.json',
    );
    await _reminder!.start();
  }

  /// 今天要提醒几条（铃铛上的小红点用）
  int get todayReminderCount => reminderItems().length;

  /// 立刻检查并弹一次系统通知（铃铛面板里手动触发，方便验证通知有没有生效）
  Future<int> notifyNow() async {
    if (_reminder == null) {
      final dir = _localDir;
      if (dir == null) return 0;
      await startReminders(dir);
    }
    return _reminder!.check();
  }

  /// 今天/此刻要提醒的事。
  ///
  /// key 里带上「这一次」的标识（日期或时刻），同一次只弹一回。
  /// - 任务自己的提醒 🔔（到期当天 / 提前N天 / 指定时间）→ 到点必弹，不看总开关
  /// - 到期待办、今天该做的定时任务、今天计划做的 → 受「任务提醒」总开关控制
  /// - 日程自己的提醒 🔔（提前N分钟 / 开始时）
  List<ReminderItem> reminderItems() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final out = <ReminderItem>[];
    final auto = profile.calendar.remindOnTaskDay;

    for (final tf in tasks) {
      for (final st in tf.task.subtasks) {
        if (st.done) continue;

        // 1) 任务自己设的提醒：到点就弹
        final rule = st.reminder;
        final fire = rule?.fireAt(st.due);
        if (rule != null && fire != null && _due(fire, now)) {
          out.add(ReminderItem(
            key: 'rem-${st.id}-${fire.toIso8601String()}',
            title: '提醒：${st.title}',
            body: [
              tf.task.title,
              rule.label,
              if (st.due != null) '到期 ${formatDate(st.due!)}',
            ].join(' · '),
          ));
        }

        if (!auto) continue;

        // 2) 到期的
        if (st.due != null && !st.isRepeating) {
          final left = calendarDaysBetween(today, st.due!);
          if (left <= 0) {
            out.add(ReminderItem(
              key: 'due-${st.id}-${formatDate(st.due!)}',
              title: left == 0 ? '今天到期：${st.title}' : '逾期 ${-left} 天：${st.title}',
              body: tf.task.title,
            ));
          }
        }

        // 3) 今天该做的定时任务（每月15日 / 每月农历十五 …）
        if (st.isRepeating && st.repeatsOn(today) && !isRepeatDoneOn(st.id, today)) {
          out.add(ReminderItem(
            key: 'rep-${st.id}-${formatDate(today)}',
            title: '今天要做：${st.title}',
            body: '${tf.task.title} · ${st.repeat!.label}',
          ));
        }

        // 4) 今天计划做的
        if (!st.isRepeating && st.isPlannedOn(today)) {
          out.add(ReminderItem(
            key: 'plan-${st.id}-${formatDate(today)}',
            title: '今天打算做：${st.title}',
            body: tf.task.title,
          ));
        }
      }
    }

    // 日程自己设的提醒
    for (final e in events) {
      final at = e.remindAt;
      if (e.done || at == null || !_due(at, now)) continue;
      out.add(ReminderItem(
        key: 'evt-${e.id}-${e.start.toIso8601String()}',
        title: '日程：${e.title}',
        body: '${formatDate(e.start)} ${e.timeLabel} · ${e.reminder!.label}',
      ));
    }

    return out;
  }

  /// 提醒到点了没（顺带补提醒：最多补最近 7 天错过的，别让关机期间的事消失）
  static bool _due(DateTime fire, DateTime now) {
    if (fire.isAfter(now)) return false;
    return now.difference(fire).inDays <= 7;
  }

  // ─────────────────────── AI 周报 / 月报 ───────────────────────

  AiConfig get ai => device.ai;

  Future<void> saveAiConfig(AiConfig c) async {
    device.ai = c;
    await saveDeviceConfig();
    notifyListeners();
  }

  /// 把某一期的原始数据汇成统计。
  ///
  /// 一期可能跨月（比如 9/28 ~ 10/4），所以涉及的每个月的杂记和日程都要读。
  Future<PeriodSummary> collectSummary(ReportCycle cycle, DateTime today) async {
    final p = cycle.previousPeriod(today);

    final notes = <Note>[];
    final events = <CalendarEvent>[];
    var cursor = DateTime(p.first.year, p.first.month, 1);
    while (!cursor.isAfter(p.last)) {
      notes.addAll(await repo.loadNotes(cursor));
      events.addAll(await repo.loadEvents(cursor));
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }

    // 定时任务：本期已经过去的每一天，该做的做了没
    final repeats = <({String title, String task, bool done})>[];
    for (var day = p.first; !day.isAfter(p.last) && !day.isAfter(today); day = day.add(const Duration(days: 1))) {
      for (final item in repeatsOn(day)) {
        repeats.add((
          title: item.subtask.title,
          task: item.task.task.title,
          done: isRepeatDoneOn(item.subtask.id, day),
        ));
      }
    }

    return PeriodSummary.build(
      label: p.label,
      suffix: p.suffix,
      title: p.title,
      first: p.first,
      last: p.last,
      tasks: tasks,
      notes: notes,
      events: events,
      repeatOccurrences: repeats,
      now: today,
      daysLeftStart: _daysLeftAt(p.first),
      daysLeftEnd: _daysLeftAt(p.last),
    );
  }

  int? _daysLeftAt(DateTime day) {
    final target = profile.lifeTarget;
    if (target == null) return null;
    return calendarDaysBetween(day, target);
  }

  /// 已经生成过这一期了没
  Future<bool> reportExistsFor(ReportCycle cycle, DateTime today) async {
    final p = cycle.previousPeriod(today);
    return await repo.readFileOrNull(VaultLayout.reportPath(p.label, p.suffix)) != null;
  }

  /// 生成一期报告。AI 挂了也照样出（客观分和统计不依赖模型）。
  Future<PeriodReport> generateReport({ReportCycle? cycle, DateTime? today, bool withAi = true}) async {
    final t = today ?? DateTime.now();
    final c = cycle ?? ai.cycle;
    final summary = await collectSummary(c, t);

    AiReview? review;
    String? err;
    if (!withAi) {
      err = null;
    } else if (!ai.enabled) {
      err = 'AI 评语没生成：设置里没打开';
    } else if (!ai.ready) {
      err = 'AI 评语没生成：发行商 / API Key / 模型名没配全';
    } else {
      try {
        final text = await LlmClient().chat(
          cfg: ai,
          systemPrompt: '你是一个克制、务实的个人复盘助理。只输出要求的 JSON。',
          userPrompt: buildReportPrompt(summary, extra: ai.extraPrompt),
        );
        review = AiReview.parse(text);
      } on LlmException catch (e) {
        err = e.message;
      } catch (e) {
        err = '$e';
      }
    }

    final report = PeriodReport(
      summary: summary,
      generatedAt: t,
      review: review,
      aiError: err,
      providerName: ai.provider.name,
      modelName: ai.effectiveModel,
    );
    await repo.writeFile(VaultLayout.reportPath(summary.label, summary.suffix), report.toMarkdown());
    notifyListeners();
    return report;
  }

  /// 到点就自动生成上一期（启动时 + 每小时都会调一次，同一天只会生成一份）
  Future<String?> maybeAutoReport() async {
    if (!ai.anyReportOn || !ai.autoReport) return null;
    final now = DateTime.now();
    if (!ai.cycle.shouldRunOn(now)) return null;
    if (await reportExistsFor(ai.cycle, now)) return null;
    if (!ai.ready) return '到出报告的日子了，但 AI 还没配好（设置 → AI）';
    try {
      final report = await generateReport();
      // 顺手弹个系统通知，不然生成完了也不知道
      try {
        final n = LocalNotification(
          title: '${report.summary.title} ${report.summary.suffix}已生成',
          body: '客观分 ${report.summary.objectiveScore} · 综合 ${report.overallScore}',
        );
        await n.show();
      } catch (_) {}
      return '已生成上一期报告（${ai.cycle.unit.suffix}）';
    } catch (e) {
      return '生成报告失败：$e';
    }
  }

  /// 已有的报告列表（新的在前）
  Future<List<String>> listReports() => repo.listFiles(VaultLayout.reportDir, extension: '.md');

  Future<String?> readReport(String fileName) =>
      repo.readFileOrNull('${VaultLayout.reportDir}/$fileName');

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

  /// 今天要做的事（计划日期是今天、截止日期是今天/已逾期、或今天该做的重复任务）
  List<({TaskFile task, SubTask subtask})> get todayFocus {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final out = <({TaskFile task, SubTask subtask})>[];
    final seen = <String>{};
    for (final tf in tasks) {
      for (final st in tf.task.subtasks) {
        if (st.isRepeating) {
          if (st.repeatsOn(today) && seen.add(st.id)) out.add((task: tf, subtask: st));
          continue;
        }
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
