import 'package:flutter_test/flutter_test.dart';
import 'package:life_task_manager/core/front_matter.dart';

void main() {
  group('front-matter', () {
    test('解析基本字段', () {
      const raw = '''---
id: t-abc
type: 大任务
tags: [毕设, 机器人]
mood: 4
---

正文第一行。
''';
      final doc = parseFrontMatter(raw);
      expect(doc.data['id'], 't-abc');
      expect(doc.data['type'], '大任务');
      expect(doc.data['tags'], ['毕设', '机器人']);
      expect(doc.data['mood'], 4);
      expect(doc.body, '正文第一行。\n', reason: '正文字头不该有多余空行');
    });

    test('没有 front-matter 时全部算正文', () {
      const raw = '# 标题\n\n正文\n';
      final doc = parseFrontMatter(raw);
      expect(doc.data, isEmpty);
      expect(doc.body, raw);
    });

    test('CRLF 文件：正文保留 \\r\\n，不丢内容', () {
      final raw = '---\r\nid: t-1\r\ntitle: 标题\r\n---\r\n\r\n正文\r\n';
      final doc = parseFrontMatter(raw);
      expect(doc.data['id'], 't-1');
      expect(doc.data['title'], '标题');
      expect(doc.body.contains('正文'), isTrue);
      expect(doc.body.startsWith('正文'), isTrue);
    });

    test('值里有冒号/井号时自动加引号，且能还原', () {
      final out = buildFrontMatter({'title': '学习: Flutter #1', 'id': 't-1'}, '正文');
      expect(out.contains('title: "学习: Flutter #1"'), isTrue);
      final back = parseFrontMatter(out);
      expect(back.data['title'], '学习: Flutter #1');
      expect(back.data['id'], 't-1');
      expect(back.body, '正文');
    });

    test('upsert 只覆盖指定字段，用户字段保留', () {
      const raw = '''---
id: t-1
用户自己写的字段: 别删我
mood: 2
---

正文
''';
      final out = upsertFrontMatter(raw, {'mood': 5, 'tags': ['a']});
      final back = parseFrontMatter(out);
      expect(back.data['用户自己写的字段'], '别删我');
      expect(back.data['mood'], 5);
      expect(back.data['tags'], ['a']);
      expect(back.data['id'], 't-1');
      expect(back.body.trim(), '正文');
    });

    test('upsert 传 null 表示删除该字段', () {
      final out = upsertFrontMatter('---\nid: t-1\n死字段: x\n---\n\n正文\n', {'死字段': null});
      expect(out.contains('死字段'), isFalse);
    });

    test('BOM 开头也能解析', () {
      final doc = parseFrontMatter('\ufeff---\nid: t-1\n---\n\n正文\n');
      expect(doc.data['id'], 't-1');
    });
  });
}
