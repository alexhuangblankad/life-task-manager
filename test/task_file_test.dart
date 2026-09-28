import 'package:flutter_test/flutter_test.dart';
import 'package:life_task_manager/model/task.dart';

const String sampleLf = '''---
id: t-7k3m9q
type: 大任务
title: 草坪机器人毕设
deadline: 2027-05-30
created: 2026-09-28
tags: [毕设, 机器人]
---

# 草坪机器人毕设

这是描述第一行。
这是第二行。

## 子任务

- [ ] 写完开题报告 📅 2026-10-10 ⏫ ^s-a1b2c3
- [x] 选好仿真软件 ✅ 2026-09-20 ^s-d4e5f6
- [ ] 跑通仿真 🔽 #仿真 ^s-g7h8i9

## 备注

用户手写的东西，程序不能动它。
''';

void main() {
  group('解析任务文件', () {
    final tf = parseTaskFile(sampleLf, filePath: '大任务/2026-09-28_草坪机器人毕设.md');

    test('front-matter 字段', () {
      expect(tf.task.id, 't-7k3m9q');
      expect(tf.task.title, '草坪机器人毕设');
      expect(tf.task.deadline, DateTime(2027, 5, 30));
      expect(tf.task.created, DateTime(2026, 9, 28));
      expect(tf.task.tags, ['毕设', '机器人']);
    });

    test('描述取标题和 ## 之间的正文', () {
      expect(tf.task.description, '这是描述第一行。\n这是第二行。');
    });

    test('三个小任务', () {
      expect(tf.task.subtasks.length, 3);
      expect(tf.task.totalCount, 3);
      expect(tf.task.doneCount, 1);
      expect(tf.task.progress, closeTo(1 / 3, 0.001));
    });

    test('小任务字段解析（截止/优先级/完成时间/标签/ID）', () {
      final a = tf.task.subtasks[0];
      expect(a.id, 's-a1b2c3');
      expect(a.title, '写完开题报告');
      expect(a.due, DateTime(2026, 10, 10));
      expect(a.priority, Priority.high);
      expect(a.done, isFalse);

      final b = tf.task.subtasks[1];
      expect(b.done, isTrue);
      expect(b.doneAt, DateTime(2026, 9, 20));

      final c = tf.task.subtasks[2];
      expect(c.priority, Priority.low);
      expect(c.tags, ['仿真']);
      expect(c.title, '跑通仿真');
    });

    test('没有 front-matter 时用文件名兜底', () {
      final t = parseTaskFile('- [ ] 一件事 ^s-1', filePath: '大任务/我的任务.md');
      expect(t.task.title, '我的任务');
      expect(t.task.subtasks.single.title, '一件事');
    });

    test('缩进的任务行也能认出来', () {
      final st = parseSubtaskLine('    - [ ] 缩进的 ^s-9');
      expect(st, isNotNull);
      expect(st!.id, 's-9');
      expect(st.title, '缩进的');
    });
  });

  group('行级手术（绝不能动用户的其它内容）', () {
    test('勾选只改那一行', () {
      final out = setSubtaskDone(sampleLf, 's-a1b2c3', true, now: DateTime(2026, 9, 29));
      final lines = out.split('\n');
      final changed = <int>[];
      final before = sampleLf.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (i >= before.length || lines[i] != before[i]) changed.add(i);
      }
      expect(changed.length, 1);
      expect(lines[changed.single], '- [x] 写完开题报告 📅 2026-10-10 ⏫ ✅ 2026-09-29 ^s-a1b2c3');
      expect(out.contains('用户手写的东西，程序不能动它。'), isTrue);
      expect(out.contains('- [x] 选好仿真软件 ✅ 2026-09-20 ^s-d4e5f6'), isTrue);
    });

    test('取消勾选会去掉完成日期', () {
      final out = setSubtaskDone(sampleLf, 's-d4e5f6', false);
      expect(out.contains('- [ ] 选好仿真软件 ^s-d4e5f6'), isTrue);
      expect(out.contains('✅ 2026-09-20'), isFalse);
    });

    test('ID 不存在时原样返回', () {
      expect(setSubtaskDone(sampleLf, 's-不存在', true), sampleLf);
    });

    test('CRLF 文件保持 CRLF', () {
      final crlf = sampleLf.replaceAll('\n', '\r\n');
      final out = setSubtaskDone(crlf, 's-a1b2c3', true, now: DateTime(2026, 9, 29));
      expect(out.contains('\r\n'), isTrue);
      expect(RegExp(r'(?<!\r)\n').hasMatch(out), isFalse, reason: '不能出现落单的 \\n');
    });

    test('追加小任务会塞进 ## 子任务 区块，而不是乱丢文件末尾', () {
      final out = appendSubtask(sampleLf, const SubTask(id: 's-new', title: '新任务', priority: Priority.medium));
      final lines = out.split('\n');
      final idxNew = lines.indexWhere((l) => l.contains('s-new'));
      final idxRemark = lines.indexWhere((l) => l.trim() == '## 备注');
      final idxLastTask = lines.indexWhere((l) => l.contains('s-g7h8i9'));
      expect(idxNew, greaterThan(idxLastTask));
      expect(idxNew, lessThan(idxRemark));
      expect(lines[idxNew], '- [ ] 新任务 🔼 ^s-new');
    });

    test('没有子任务区块时会自己建一个', () {
      const noSection = '# 只有标题\n\n一些说明\n';
      final out = appendSubtask(noSection, const SubTask(id: 's-1', title: '第一件事'));
      expect(out.contains('## 子任务'), isTrue);
      expect(out.contains('- [ ] 第一件事 ^s-1'), isTrue);
      expect(out.contains('一些说明'), isTrue);
    });

    test('删除小任务只删那一行', () {
      final out = removeSubtask(sampleLf, 's-d4e5f6');
      expect(out.contains('s-d4e5f6'), isFalse);
      expect(out.contains('s-a1b2c3'), isTrue);
      expect(out.contains('s-g7h8i9'), isTrue);
      expect(out.contains('## 备注'), isTrue);
    });

    test('改标题/截止日期', () {
      final st = parseTaskFile(sampleLf).task.subtaskById('s-a1b2c3')!;
      final out = updateSubtask(sampleLf, st.copyWith(title: '写完开题报告（改）', due: DateTime(2026, 11, 1)));
      expect(out.contains('- [ ] 写完开题报告（改） 📅 2026-11-01 ⏫ ^s-a1b2c3'), isTrue);
    });
  });

  group('渲染', () {
    test('renderSubtaskLine 与 parseSubtaskLine 往返一致', () {
      const st = SubTask(
        id: 's-xyz',
        title: '写点东西',
        done: true,
        due: null,
        doneAt: null,
        priority: Priority.medium,
        tags: ['a', 'b'],
      );
      final line = renderSubtaskLine(st);
      final back = parseSubtaskLine(line)!;
      expect(back.id, st.id);
      expect(back.title, st.title);
      expect(back.done, st.done);
      expect(back.priority, st.priority);
      expect(back.tags, st.tags);
    });

    test('新建任务文件能被自己解析回来', () {
      final raw = renderTaskFile(BigTask(
        id: 't-abc',
        title: '测试大任务',
        description: '描述',
        deadline: DateTime(2027, 1, 1),
        created: DateTime(2026, 9, 28),
        tags: ['x'],
        subtasks: const [SubTask(id: 's-1', title: '子任务一')],
      ));
      final back = parseTaskFile(raw, filePath: '大任务/测试大任务.md');
      expect(back.task.id, 't-abc');
      expect(back.task.title, '测试大任务');
      expect(back.task.deadline, DateTime(2027, 1, 1));
      expect(back.task.tags, ['x']);
      expect(back.task.subtasks.single.id, 's-1');
      expect(back.task.description, '描述');
    });

    test('标题里有冒号和井号也能安全写入 front-matter', () {
      final raw = renderTaskFile(const BigTask(id: 't-1', title: '学习: Flutter #1'));
      final back = parseTaskFile(raw);
      expect(back.task.title, '学习: Flutter #1');
    });
  });
}
