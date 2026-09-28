/// 自绘的窗口顶部条（配合「隐藏系统标题栏」用）。
///
/// 为什么要有它：Windows 原生标题栏那条黑杠不好看，所以把系统标题栏藏起来，
/// 只保留右上角的最小化/最大化/关闭（`windowButtonVisibility: true`）。
/// 但标题栏没了就没地方拖窗口了 —— 这一条负责「可以拖动」，顺便放个图标和
/// 窗口名，右边留出宽度给系统那三个按钮，别让文字被压住。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class AppTitleBar extends StatelessWidget {
  const AppTitleBar({super.key, this.title = '人生任务管理器'});

  final String title;

  /// 桌面三端才需要；安卓/iOS 有自己的状态栏，不掺和
  static bool get supported => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  /// 右上角三个系统按钮大概占这么宽（Windows 上约 138px）
  static const double _buttonsWidth = 146;

  @override
  Widget build(BuildContext context) {
    if (!supported) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DragToMoveArea(
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.35))),
        ),
        padding: const EdgeInsets.only(left: 12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Image.asset('assets/app_icon.png', width: 22, height: 22),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const Spacer(),
            // 给系统的最小化/最大化/关闭留位置
            const SizedBox(width: _buttonsWidth),
          ],
        ),
      ),
    );
  }
}

/// 给需要自己排版的地方用（比如某些页面想留出拖动区）
const EdgeInsets kTitleBarPadding = EdgeInsets.only(top: 40);
