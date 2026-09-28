import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_task_manager/model/event.dart';
import 'package:life_task_manager/model/note.dart';
import 'package:life_task_manager/model/profile.dart';
import 'package:life_task_manager/model/task.dart';
import 'package:life_task_manager/vault/repository.dart';

void main() {
  late Directory tmp;
  late VaultRepository repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ltm_test_');
    repo = VaultRepository(tmp.path);
    await repo.ensureStructure();
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('建目录结构', () async {
    for (final d in ['config', '大任务', '杂记', '日程', '报告', '回收站']) {
      expect(await Directory('${tmp.path}/$d').exists(), isTrue, reason: '$d 应该被创建');
    }
  });

  test('大任务：建 → 存 → 读回来', () async {
    final created = await repo.createTask(
      title: '草坪机器人毕设',
      description: '目标是完成仿真',
      deadline: DateTime(2027, 5, 30),
      tags: ['毕设'],
      now: DateTime(2026, 9, 28),
    );
    expect(created.task.filePath, '大任务/2026-09-28_草坪机器人毕设.md');
    expect(await File('${tmp.path}/${created.task.filePath}').exists(), isTrue);

    // 加一个小任务再存回去，模拟勾选
    var raw = await File('${tmp.path}/${created.task.filePath}').readAsString();
    raw = appendSubtask(raw, const SubTask(id: 's-1', title: '写完开题报告'));
    await repo.saveTaskFile(created.task.filePath, raw);

    final list = await repo.loadTasks();
    expect(list.length, 1);
    expect(list.single.task.title, '草坪机器人毕设');
    expect(list.single.task.subtasks.single.title, '写完开题报告');

    // 再勾上
    var raw2 = await File('${tmp.path}/${created.task.filePath}').readAsString();
    raw2 = setSubtaskDone(raw2, 's-1', true, now: DateTime(2026, 9, 29));
    await repo.saveTaskFile(created.task.filePath, raw2);
    final again = await repo.loadTasks();
    expect(again.single.task.subtasks.single.done, isTrue);
    expect(again.single.task.subtasks.single.doneAt, DateTime(2026, 9, 29));
  });

  test('杂记：日记落到 202609 月份文件夹，并能按天取回', () async {
    final saved = await repo.saveNote(Note(
      id: 'n-1',
      type: NoteType.diary,
      date: DateTime(2026, 9, 28),
      body: '今天干了点活。',
    ));
    expect(saved.filePath, '杂记/202609/日记/2026-09-28.md');

    final diary = await repo.loadDiary(DateTime(2026, 9, 28));
    expect(diary, isNotNull);
    expect(diary!.body, '今天干了点活。');

    final month = await repo.loadNotes(DateTime(2026, 9, 1));
    expect(month.length, 1);
  });

  test('杂记：任务杂记和日记杂记能一起按月读出来', () async {
    await repo.saveNote(Note(id: 'n-1', type: NoteType.diary, date: DateTime(2026, 9, 28), body: '日记'));
    await repo.saveNote(Note(
      id: 'n-2',
      type: NoteType.task,
      date: DateTime(2026, 9, 28),
      body: '任务杂记',
      taskId: 't-1',
      taskTitle: '草坪机器人毕设',
    ));
    final month = await repo.loadNotes(DateTime(2026, 9, 10));
    expect(month.length, 2);
    expect(month.where((n) => n.type == NoteType.task).single.taskTitle, '草坪机器人毕设');
  });

  test('日程：按月存取 JSON', () async {
    await repo.saveEvents(DateTime(2026, 9, 1), [
      CalendarEvent(id: 'e-1', title: '组会', start: DateTime(2026, 9, 30, 14), end: DateTime(2026, 9, 30, 16)),
      CalendarEvent(id: 'e-2', title: '交材料', start: DateTime(2026, 9, 29), allDay: true, done: true),
    ]);
    expect(await File('${tmp.path}/日程/202609.json').exists(), isTrue);

    final loaded = await repo.loadEvents(DateTime(2026, 9, 15));
    expect(loaded.length, 2);
    final meeting = loaded.firstWhere((e) => e.id == 'e-1');
    expect(meeting.title, '组会');
    expect(meeting.timeLabel, '14:00-16:00');
    expect(meeting.onDay(DateTime(2026, 9, 30, 23)), isTrue);
    expect(meeting.onDay(DateTime(2026, 10, 1)), isFalse);

    final allDay = loaded.firstWhere((e) => e.id == 'e-2');
    expect(allDay.allDay, isTrue);
    expect(allDay.timeLabel, '全天');
    expect(allDay.done, isTrue);
  });

  test('删除进回收站，不真删', () async {
    await repo.saveNote(Note(id: 'n-1', type: NoteType.diary, date: DateTime(2026, 9, 28), body: 'x'));
    final rel = '杂记/202609/日记/2026-09-28.md';
    await repo.moveToTrash(rel, now: DateTime(2026, 9, 28, 12, 0, 0));
    expect(await File('${tmp.path}/$rel').exists(), isFalse);
    expect(await File('${tmp.path}/回收站/2026-09-28_120000/$rel').exists(), isTrue);
  });

  test('同步扫描：排除回收站和隐藏文件', () async {
    await repo.saveNote(Note(id: 'n-1', type: NoteType.diary, date: DateTime(2026, 9, 28), body: 'x'));
    await repo.writeFile('回收站/2026-09-28_120000/旧文件.md', 'x');
    await repo.writeFile('.DS_Store', 'x');
    final files = await repo.scanFiles();
    final paths = files.map((f) => f.relPath).toList();
    expect(paths.contains('杂记/202609/日记/2026-09-28.md'), isTrue);
    expect(paths.any((p) => p.startsWith('回收站/')), isFalse);
    expect(paths.contains('.DS_Store'), isFalse);
  });

  test('配置：人生期限读写', () async {
    expect((await repo.loadProfile()).configured, isFalse);

    await repo.saveProfile(Profile(
      name: '测试',
      birthDate: DateTime(2003, 5, 1),
      lifeExpectancyYears: 80,
    ));
    final p = await repo.loadProfile();
    expect(p.birthDate, DateTime(2003, 5, 1));
    expect(p.lifeTarget, DateTime(2083, 5, 1, 23, 59, 59));
    expect(p.configured, isTrue);

    // 直接指定终点日期时，以它为准
    final p2 = Profile(birthDate: DateTime(2003, 5, 1), targetDate: DateTime(2027, 5, 30));
    await repo.saveProfile(p2);
    expect((await repo.loadProfile()).lifeTarget, DateTime(2027, 5, 30, 23, 59, 59));
  });
}
