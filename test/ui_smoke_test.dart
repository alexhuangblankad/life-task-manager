import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:life_task_manager/app_state.dart';
import 'package:life_task_manager/core/device_config.dart';
import 'package:life_task_manager/core/ids.dart';
import 'package:life_task_manager/main.dart';
import 'package:life_task_manager/model/event.dart';
import 'package:life_task_manager/model/note.dart';
import 'package:life_task_manager/model/profile.dart';
import 'package:life_task_manager/model/task.dart';
import 'package:life_task_manager/vault/repository.dart';
import 'package:life_task_manager/ui/tasks_page.dart';

/// 整机冒烟：真建 vault、真写文件，然后把四个页面都渲染一遍。
/// 布局溢出（RenderFlex overflow）在这里会直接让测试失败。
void main() {
  late Directory tmp;
  late String vaultPath;
  late AppState state;

  setUpAll(() async {
    await initializeDateFormatting('zh_CN');
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ltm_ui_');
    vaultPath = '${tmp.path}/vault';

    final repo = VaultRepository(vaultPath);
    await repo.ensureStructure();

    final today = DateTime.now();
    final created = await repo.createTask(
      title: '草坪机器人毕设',
      description: '基于视觉的路径规划',
      deadline: today.add(const Duration(days: 90)),
      now: today,
    );
    var raw = await repo.readFileOrNull(created.task.filePath) ?? created.raw;
    raw = appendSubtask(raw, SubTask(id: newSubtaskId(), title: '跑通仿真最小示例', due: today.add(const Duration(days: 3)), priority: Priority.high));
    raw = appendSubtask(raw, SubTask(id: newSubtaskId(), title: '整理答辩 PPT', due: today.add(const Duration(days: 10))));
    raw = appendSubtask(raw, SubTask(
      id: newSubtaskId(),
      title: '看两篇路径规划论文',
      scheduled: today,
      priority: Priority.medium,
    ));
    await repo.saveTaskFile(created.task.filePath, raw);

    await repo.saveNote(Note(
      id: newNoteId(),
      type: NoteType.diary,
      date: today,
      body: '今天把大纲写完了。',
    ));
    await repo.saveNote(Note(
      id: newNoteId(),
      type: NoteType.task,
      date: today,
      body: '仿真参数调好了。',
      taskId: created.task.id,
      taskTitle: '草坪机器人毕设',
      subtaskTitle: '跑通仿真最小示例',
    ));
    await repo.saveEvents(today, [
      CalendarEvent(id: newEventId(), title: '组会', start: DateTime(today.year, today.month, today.day, 14)),
    ]);
    await repo.saveProfile(Profile(birthDate: DateTime(2000, 5, 1), lifeExpectancyYears: 80));

    // 把设备配置指到临时 vault，别碰真人的数据
    final cfg = DeviceConfigStore(path: '${tmp.path}/device.json');
    await cfg.save(DeviceConfig(vaultPath: vaultPath, deviceName: '测试机'));

    state = AppState(store: cfg);
    await state.bootstrap();
  });

  tearDown(() async {
    state.dispose();
    // Windows 上文件句柄可能还没释放，删不掉就算了（临时目录留在 %TEMP% 里无害）
    try {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> pumpApp(WidgetTester tester, {double height = 1000}) async {
    // 视口给高一点，ListView 才会把下面的卡片也构建出来
    await tester.binding.setSurfaceSize(Size(1600, height));
    await tester.pumpWidget(LifeTaskManagerApp(state: state));
    // 界面里有每秒滴答的定时器，不能用 pumpAndSettle（永远等不到静止）
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> goTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  testWidgets('倒计时页：显示人生倒计时和任务倒计时', (tester) async {
    await pumpApp(tester);
    expect(find.text('人生倒计时'), findsOneWidget);
    expect(find.text('任务倒计时'), findsOneWidget);
    expect(find.textContaining('跑通仿真最小示例'), findsWidgets);
    expect(find.textContaining('还剩 3 天'), findsOneWidget);
  });

  testWidgets('待办页：展开大任务能看到小任务和勾选框', (tester) async {
    await pumpApp(tester);
    await goTab(tester, '待办');
    final tasksPage = find.byType(TasksPage);
    expect(find.descendant(of: tasksPage, matching: find.text('草坪机器人毕设')), findsWidgets);

    // 点开大任务（没展开时子项还没构建，必须先展开）
    await tester.tap(find.descendant(of: tasksPage, matching: find.text('草坪机器人毕设')).first);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(find.descendant(of: tasksPage, matching: find.text('跑通仿真最小示例')), findsOneWidget);
    expect(find.descendant(of: tasksPage, matching: find.text('整理答辩 PPT')), findsOneWidget);

    // 点小任务勾掉 → 写回文件（真实磁盘 I/O 必须放在 runAsync 里，否则 Future 不完成），
    // 写完之后会弹出「写任务杂记」对话框。
    final doneCount = await tester.runAsync(() async {
      await tester.tap(find.descendant(of: tasksPage, matching: find.text('跑通仿真最小示例')));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final reloaded = await VaultRepository(vaultPath).loadTasks();
      return reloaded.single.task.doneCount;
    });
    expect(doneCount, 1, reason: '勾选要真的写进 md 文件');

    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(find.text('跳过'), findsOneWidget, reason: '勾完应该弹出写任务杂记的对话框');
    await tester.tap(find.text('跳过'));
    await tester.pump();
  });

  testWidgets('日历页：月视图 + 当天日程 + 写日记入口', (tester) async {
    await pumpApp(tester);
    await goTab(tester, '日历');
    expect(find.text('组会'), findsWidgets);
    expect(find.textContaining('这天写的日记'), findsOneWidget);
    expect(find.text('新增日程'), findsOneWidget);
    // ⏳ 计划日期要出现在日历里（没有截止日期的任务也能排进某一天）
    expect(find.textContaining('计划这天做的事'), findsOneWidget);
    expect(find.text('看两篇路径规划论文'), findsWidgets);
  });

  testWidgets('外观：能切到暗色，并且跟着状态走', (tester) async {
    await pumpApp(tester, height: 2600);
    await goTab(tester, '设置');
    expect(find.text('外观'), findsOneWidget);

    await tester.tap(find.text('暗色'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(state.themeMode, ThemeMode.dark, reason: '切主题要立刻生效（不用重启）');
    expect(state.device.themeMode, 'dark');
    // 落盘的正确性由 test/device_config_test.dart 用纯 Dart 测试覆盖
    // （widget 测试的假异步区里，点击触发的写盘 Future 会挂住，断言文件内容会读到竞态）
  });

  testWidgets('设置页有收款码入口（支持作者）', (tester) async {
    await pumpApp(tester, height: 2600);
    await goTab(tester, '设置');
    expect(find.text('支持作者'), findsOneWidget);
    expect(find.textContaining('5 元'), findsWidgets);
    expect(find.byType(Image), findsWidgets, reason: '收款码图片要显示出来');
  });

  testWidgets('杂记页：两种杂记都在，能按月过滤', (tester) async {
    await pumpApp(tester);
    await goTab(tester, '杂记');
    expect(find.textContaining('任务杂记'), findsWidgets);
    expect(find.textContaining('日记'), findsWidgets);
    expect(find.textContaining('共 2 条'), findsOneWidget);
  });

  testWidgets('设置页：数据位置 / WebDAV / 关于 三块都在', (tester) async {
    await pumpApp(tester, height: 2600);
    await goTab(tester, '设置');
    expect(find.textContaining('数据位置'), findsOneWidget);
    expect(find.textContaining('WebDAV'), findsWidgets);
    expect(find.textContaining('关于'), findsOneWidget);
    expect(find.text(vaultPath), findsOneWidget, reason: 'vault 路径要显示出来');
  });

  testWidgets('人生期限：设置后倒计时开始跳数字', (tester) async {
    await pumpApp(tester);
    expect(find.text('还没设置人生期限'), findsNothing);
    expect(find.textContaining('人生还剩'), findsOneWidget);
    expect(find.textContaining('已经走完'), findsOneWidget);
  });
}
