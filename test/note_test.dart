import 'package:flutter_test/flutter_test.dart';
import 'package:life_task_manager/model/note.dart';
import 'package:life_task_manager/vault/layout.dart';

const String diary = '''---
id: n-8f2k1
type: 日记
date: 2026-09-28
mood: 4
tags: [随笔]
---

今天把开题报告的大纲写完了。
明天开始配仿真环境。
''';

const String taskNote = '''---
id: n-9d3x2
type: 任务
date: 2026-09-28
task: t-7k3m9q
task_title: 草坪机器人毕设
subtask: 写完开题报告
---

开题报告写完之后发现第三章的逻辑要重排。
''';

void main() {
  group('杂记解析', () {
    test('日记杂记', () {
      final n = parseNote(diary, filePath: '杂记/202609/日记/2026-09-28.md');
      expect(n.id, 'n-8f2k1');
      expect(n.type, NoteType.diary);
      expect(n.date, DateTime(2026, 9, 28));
      expect(n.mood, 4);
      expect(n.tags, ['随笔']);
      expect(n.body.startsWith('今天把开题报告的大纲写完了。'), isTrue);
      expect(n.taskId, isNull);
    });

    test('任务杂记带任务引用', () {
      final n = parseNote(taskNote, filePath: '杂记/202609/任务/2026-09-28_草坪机器人毕设.md');
      expect(n.type, NoteType.task);
      expect(n.taskId, 't-7k3m9q');
      expect(n.taskTitle, '草坪机器人毕设');
      expect(n.subtaskTitle, '写完开题报告');
    });

    test('没有 date 字段时从文件名抠日期', () {
      final n = parseNote('随便写点', filePath: '杂记/202609/日记/2026-10-05.md');
      expect(n.date, DateTime(2026, 10, 5));
    });

    test('渲染后能被自己解析回来', () {
      final n = Note(
        id: 'n-1',
        type: NoteType.task,
        date: DateTime(2026, 9, 28),
        body: '内容\n第二行',
        taskId: 't-1',
        taskTitle: '任务: 带冒号',
        subtaskTitle: '小任务',
        mood: 3,
        tags: ['a'],
      );
      final back = parseNote(renderNote(n));
      expect(back.id, 'n-1');
      expect(back.type, NoteType.task);
      expect(back.taskTitle, '任务: 带冒号');
      expect(back.body, '内容\n第二行');
      expect(back.mood, 3);
    });

    test('appendToNote 追加不覆盖', () {
      final out = appendToNote(diary, '晚上又补了 200 字。');
      expect(out.contains('今天把开题报告的大纲写完了。'), isTrue);
      expect(out.trimRight().endsWith('晚上又补了 200 字。'), isTrue);
    });
  });

  group('目录约定', () {
    test('月份文件夹格式：202609', () {
      expect(VaultLayout.monthFolder(DateTime(2026, 9, 28)), '202609');
      expect(VaultLayout.monthFolder(DateTime(2026, 12, 1)), '202612');
    });

    test('日记路径按月归档', () {
      expect(VaultLayout.diaryPath(DateTime(2026, 9, 28)), '杂记/202609/日记/2026-09-28.md');
      expect(VaultLayout.diaryDir(DateTime(2026, 9, 28)), '杂记/202609/日记');
    });

    test('任务杂记路径带上日期和任务名', () {
      expect(
        VaultLayout.taskNotePath(DateTime(2026, 9, 28), '草坪机器人毕设'),
        '杂记/202609/任务/2026-09-28_草坪机器人毕设.md',
      );
    });

    test('文件名清洗：干掉非法字符', () {
      expect(VaultLayout.sanitize('a/b\\c:d*e?f"g<h>i|j'), 'a b c d e f g h i j');
      expect(VaultLayout.sanitize('  两边空格  '), '两边空格');
      expect(VaultLayout.sanitize('结尾有点.'), '结尾有点');
      expect(VaultLayout.sanitize(''), '未命名');
      expect(VaultLayout.sanitize('x' * 100).length, 60);
    });

    test('同步忽略清单', () {
      expect(VaultLayout.isIgnored('回收站/2026-09-28_120000/x.md'), isTrue);
      expect(VaultLayout.isIgnored('.DS_Store'), isTrue);
      expect(VaultLayout.isIgnored('杂记/202609/日记/2026-09-28.md'), isFalse);
      expect(VaultLayout.isIgnored('大任务/x.tmp'), isTrue);
    });
  });
}
