import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_task_manager/core/current_vault.dart';
import 'package:life_task_manager/ui/markdown_view.dart';

/// 杂记里插的图（拖进来的）：
/// - 路径怎么从「相对 vault」换成绝对路径（CurrentVault.resolve）
/// - MarkdownView 真的把 `![](附件/…)` 渲染成磁盘上的那张图
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ltm_attach_');
    CurrentVault.root = tmp.path;
  });

  tearDown(() async {
    CurrentVault.root = '';
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('图片路径解析', () {
    test('相对路径 → vault 下的绝对路径', () {
      final p = CurrentVault.resolve('附件/202609/截图.png');
      expect(p, isNotNull);
      expect(p!.replaceAll('\\', '/').endsWith('/附件/202609/截图.png'), isTrue);
      expect(p.replaceAll('\\', '/').startsWith(tmp.path.replaceAll('\\', '/')), isTrue);
    });

    test('百分号编码、开头的 ./ 和斜杠都能认', () {
      for (final raw in ['附件/202609/%E6%88%AA%E5%9B%BE.png', './附件/202609/截图.png', '/附件/202609/截图.png']) {
        final p = CurrentVault.resolve(raw);
        expect(p, isNotNull, reason: raw);
        expect(p!.replaceAll('\\', '/').endsWith('/附件/202609/截图.png'), isTrue, reason: raw);
      }
    });

    test('网络图和 data URI 不当本地文件', () {
      expect(CurrentVault.resolve('https://example.com/a.png'), isNull);
      expect(CurrentVault.resolve('data:image/png;base64,AAAA'), isNull);
    });

    test('绝对路径原样用（用户可以写死一个路径）', () {
      final p = CurrentVault.resolve('C:/pics/a.png');
      expect(p?.replaceAll('\\', '/'), 'C:/pics/a.png');
    });

    test('vault 还没确定时，相对路径解析不出来（不瞎猜）', () {
      CurrentVault.root = '';
      expect(CurrentVault.resolve('附件/a.png'), isNull);
    });
  });

  testWidgets('MarkdownView 把相对路径的图渲染成磁盘文件', (tester) async {
    final rel = '附件/202609/截图.png';
    final f = File('${tmp.path}/$rel');
    // 真实文件 I/O 必须放进 runAsync，否则 widget 测试的假异步区里这个 Future 不会完成
    await tester.runAsync(() async {
      await f.parent.create(recursive: true);
      // 1×1 的真 PNG：解析得动，不是空文件
      await f.writeAsBytes(onePixelPng);
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MarkdownView(data: '先写一句。\n\n![截图]($rel)\n')),
    ));
    await tester.pump();

    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images, isNotEmpty, reason: '图要渲染出来，不能只显示一行 markdown');
    final file = images.map((i) => i.image).whereType<FileImage>().toList();
    expect(file.length, 1);
    expect(file.single.file.path.replaceAll('\\', '/'), f.path.replaceAll('\\', '/'));
  });

  testWidgets('图找不到时给个占位，不让整页崩', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MarkdownView(data: '![不存在](附件/202609/nope.png)')),
    ));
    await tester.pump();
    expect(find.textContaining('图片没找到'), findsOneWidget);
  });
}

/// 1×1 透明 PNG
final List<int> onePixelPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
];
