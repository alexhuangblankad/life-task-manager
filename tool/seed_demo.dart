/// 塞一份示例数据进 vault（用项目自己的读写代码，顺便验证写盘逻辑）。
///
/// 用法：
///   dart run tool/seed_demo.dart "C:/Users/xxx/Documents/LifeTaskManager"
library;

import 'dart:io';

import 'package:life_task_manager/core/ids.dart';
import 'package:life_task_manager/model/event.dart';
import 'package:life_task_manager/model/note.dart';
import 'package:life_task_manager/model/task.dart';
import 'package:life_task_manager/vault/repository.dart';

Future<void> main(List<String> args) async {
  final path = args.isNotEmpty
      ? args.first
      : '${Platform.environment['USERPROFILE'] ?? '.'}/Documents/LifeTaskManager';

  final repo = VaultRepository(path);
  await repo.ensureStructure();

  final today = DateTime.now();
  final d = (int days) => DateTime(today.year, today.month, today.day).add(Duration(days: days));

  // ── 大任务 ──
  final created = await repo.createTask(
    title: '草坪机器人毕设',
    description: '基于视觉的路径规划，目标是让仿真能跑通完整流程。',
    deadline: d(120),
    tags: ['毕设', '机器人'],
    now: today,
  );

  var raw = await repo.readFileOrNull(created.task.filePath) ?? created.raw;
  raw = appendSubtask(raw, SubTask(id: newSubtaskId(), title: '写完开题报告', priority: Priority.high));
  raw = appendSubtask(raw, SubTask(id: newSubtaskId(), title: '跑通仿真最小示例', due: d(3), priority: Priority.high));
  raw = appendSubtask(raw, SubTask(id: newSubtaskId(), title: '整理答辩 PPT', due: d(10), priority: Priority.medium));
  raw = appendSubtask(raw, SubTask(id: newSubtaskId(), title: '写第三章：路径规划算法', due: d(25)));
  await repo.saveTaskFile(created.task.filePath, raw);

  // 把第一个小任务勾上（顺手验证勾选写回文件）
  var again = await repo.readFileOrNull(created.task.filePath) ?? raw;
  final firstId = parseTaskFile(again).task.subtasks.first.id;
  again = setSubtaskDone(again, firstId, true, now: d(-2));
  await repo.saveTaskFile(created.task.filePath, again);

  final tf = (await repo.loadTasks()).first;

  // ── 日程（本月）──
  final events = [
    CalendarEvent(
      id: newEventId(),
      title: '组会汇报进度',
      start: DateTime(d(1).year, d(1).month, d(1).day, 14),
      end: DateTime(d(1).year, d(1).month, d(1).day, 16),
    ),
    CalendarEvent(
      id: newEventId(),
      title: '交开题报告',
      start: d(3),
      allDay: true,
      taskId: tf.task.id,
    ),
  ];
  await repo.saveEvents(today, events);

  // ── 一条任务杂记 ──
  await repo.saveNote(Note(
    id: newNoteId(),
    type: NoteType.task,
    date: d(-2),
    body: '开题报告写完了。第三章的算法对比表还没想清楚要不要留，先记一笔，改的时候再看。',
    taskId: tf.task.id,
    taskTitle: tf.task.title,
    subtaskTitle: '写完开题报告',
  ));

  print('示例数据已写入：$path');
  print('大任务：${tf.task.title}（${tf.task.doneCount}/${tf.task.totalCount}）');
  for (final f in await repo.scanFiles()) {
    print('  ${f.relPath}');
  }
}
