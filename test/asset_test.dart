import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

/// 资源文件要真的打进包里，不然界面上只会显示一个空白方块
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('收款码和托盘图标都在包里', () async {
    for (final path in ['assets/donate_qr.png', 'assets/tray.ico']) {
      final data = await rootBundle.load(path);
      expect(data.lengthInBytes, greaterThan(1000), reason: '$path 应该有实际内容');
    }
  });

  test('收款码是能解码的图片，而且够大够竖（否则扫不动）', () async {
    final bytes = (await rootBundle.load('assets/donate_qr.png')).buffer.asUint8List();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, greaterThan(200), reason: '太小的图放界面上扫不出来');
    expect(frame.image.height, greaterThan(frame.image.width), reason: '微信收款码是竖版卡片');
  });
}
