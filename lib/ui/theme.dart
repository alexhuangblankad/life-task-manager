import 'dart:ui' show FontVariation;

import 'package:flutter/material.dart';

/// 内置字体的 family 名（pubspec 里声明的）
const String kNotoFamily = 'NotoSansSC';

/// 字体选项
///
/// 说明：macOS 的中文是「苹方」，本身有版权不能打包分发；
/// Noto Sans SC（思源黑体的 Google 版，OFL 许可）是观感最接近它的开源替代，
/// 而且字重全、笔画清楚，安卓上也自带一份不用看系统脸色。
const List<({String id, String name})> kFontChoices = [
  (id: 'noto', name: 'Noto Sans SC（内置 · 接近苹方）'),
  (id: 'system', name: '跟随系统'),
];

/// 字号档位
const List<({String id, String name, double scale})> kFontScales = [
  (id: 'small', name: '小', scale: 0.95),
  (id: 'normal', name: '标准', scale: 1.08),
  (id: 'large', name: '大', scale: 1.22),
  (id: 'huge', name: '特大', scale: 1.38),
];

double fontScaleOf(String id) {
  for (final s in kFontScales) {
    if (s.id == id) return s.scale;
  }
  return 1.08;
}

String fontScaleName(String id) {
  for (final s in kFontScales) {
    if (s.id == id) return s.name;
  }
  return '标准';
}

/// 可变字体要显式给 wght 轴，否则永远渲染成 Regular —— 粗体不粗、标题会糊
///
/// 注意：这里逐个样式改，不用 TextTheme.apply(fontSizeFactor:) ——
/// 那个在「有样式 fontSize 为 null」时会断言失败，直接把界面搞崩（真踩过）。
TextStyle? _tune(TextStyle? s, String? family, double scale, bool axis) {
  if (s == null) return null;
  final size = s.fontSize;
  return s.copyWith(
    fontFamily: family ?? s.fontFamily,
    fontSize: size == null ? null : size * scale,
    fontVariations: axis
        ? <FontVariation>[FontVariation('wght', (s.fontWeight ?? FontWeight.w400).value.toDouble())]
        : s.fontVariations,
  );
}

TextTheme _tuneAll(TextTheme t, String? family, double scale, bool axis) {
  TextStyle? f(TextStyle? s) => _tune(s, family, scale, axis);
  return TextTheme(
    displayLarge: f(t.displayLarge),
    displayMedium: f(t.displayMedium),
    displaySmall: f(t.displaySmall),
    headlineLarge: f(t.headlineLarge),
    headlineMedium: f(t.headlineMedium),
    headlineSmall: f(t.headlineSmall),
    titleLarge: f(t.titleLarge),
    titleMedium: f(t.titleMedium),
    titleSmall: f(t.titleSmall),
    bodyLarge: f(t.bodyLarge),
    bodyMedium: f(t.bodyMedium),
    bodySmall: f(t.bodySmall),
    labelLarge: f(t.labelLarge),
    labelMedium: f(t.labelMedium),
    labelSmall: f(t.labelSmall),
  );
}

ThemeData buildAppTheme(
  Brightness brightness, {
  String fontChoice = 'noto',
  String fontScale = 'normal',
}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF3D5AFE),
    brightness: brightness,
  );

  final family = fontChoice == 'system' ? null : kNotoFamily;
  final scale = fontScaleOf(fontScale);

  // 以 M3 默认排版为底，换字体 → 调字号 → 给可变字体补字重轴
  final base = ThemeData(brightness: brightness, useMaterial3: true);
  final text = _tuneAll(base.textTheme, family, scale, family != null);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: text,
    scaffoldBackgroundColor: scheme.surface,
    // 按钮/输入框也跟着换字体
    fontFamily: family,
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      isDense: true,
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.5), space: 1),
    listTileTheme: const ListTileThemeData(dense: true),
  );
}

/// 界面里到处要用的间距常量
class Gaps {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const EdgeInsets page = EdgeInsets.fromLTRB(20, 16, 20, 20);
}
