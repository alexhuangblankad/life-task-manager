/// 自绘的窗口顶部条。
///
/// 为什么要有它：Windows 原生标题栏那条灰黑杠不好看，所以把系统标题栏藏起来
/// （`TitleBarStyle.hidden`）。但藏了之后：
///   - 没地方拖窗口 → 这条自己实现拖动
///   - 系统那三个按钮**也没了**（实测 `windowButtonVisibility: true` 在 hidden
///     模式下不画）→ 所以最小化/最大化/关闭也自己画
///
/// 左边（图标 + 名字 + 空白）可拖动，双击还能最大化/还原（Windows 的老习惯）；
/// 右边三个按钮不参与拖动，不然点按钮会变成拖窗口。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class AppTitleBar extends StatefulWidget {
  const AppTitleBar({super.key, this.title = '人生任务管理器'});

  final String title;

  /// 桌面三端才需要；安卓/iOS 有自己的状态栏，不掺和
  static bool get supported => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  State<AppTitleBar> createState() => _AppTitleBarState();
}

class _AppTitleBarState extends State<AppTitleBar> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    if (AppTitleBar.supported && Platform.isWindows) {
      windowManager.addListener(this);
      _syncMaximized();
    }
  }

  @override
  void dispose() {
    if (AppTitleBar.supported && Platform.isWindows) windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _syncMaximized() async {
    try {
      final m = await windowManager.isMaximized();
      if (mounted && m != _maximized) setState(() => _maximized = m);
    } catch (_) {}
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  Widget build(BuildContext context) {
    if (!AppTitleBar.supported) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.35))),
      ),
      child: Row(
        children: [
          // 左边：可拖动区域（双击最大化/还原，跟 Windows 习惯一致）
          Expanded(
            child: DragToMoveArea(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTap: _toggleMaximize,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: Image.asset('assets/app_icon.png', width: 22, height: 22),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.title,
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 右边：三个窗口按钮（自己画，系统在隐藏标题栏时不画）
          _WindowButton(
            tooltip: '最小化',
            onTap: () => windowManager.minimize(),
            child: Icon(Icons.remove, size: 16, color: scheme.onSurfaceVariant),
          ),
          _WindowButton(
            tooltip: _maximized ? '还原' : '最大化',
            onTap: _toggleMaximize,
            child: Icon(
              _maximized ? Icons.filter_none : Icons.crop_square,
              size: 14,
              color: scheme.onSurfaceVariant,
            ),
          ),
          _WindowButton(
            tooltip: '关闭',
            danger: true,
            onTap: () => windowManager.close(), // 走正常关闭流程（会问缩托盘还是退出）
            child: Icon(Icons.close, size: 16, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleMaximize() async {
    try {
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
      await _syncMaximized();
    } catch (_) {}
  }
}

/// 一个窗口按钮：46x40（跟 Windows 原生按钮差不多大），悬停变色，关闭按钮悬停变红
class _WindowButton extends StatefulWidget {
  const _WindowButton({required this.child, required this.onTap, this.tooltip, this.danger = false});

  final Widget child;
  final VoidCallback onTap;
  final String? tooltip;
  final bool danger;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = _hover
        ? (widget.danger ? const Color(0xFFE53935) : scheme.surfaceContainerHighest)
        : Colors.transparent;
    final fg = _hover && widget.danger ? Colors.white : null;

    final btn = MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 46,
          height: 40,
          color: bg,
          alignment: Alignment.center,
          child: fg == null ? widget.child : IconTheme(data: IconThemeData(color: fg), child: widget.child),
        ),
      ),
    );

    final tip = widget.tooltip;
    return tip == null ? btn : Tooltip(message: tip, waitDuration: const Duration(milliseconds: 600), child: btn);
  }
}
