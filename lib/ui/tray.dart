/// 右下角托盘常驻（像微信那样）+ 窗口行为。
///
/// 行为：
///   - 关窗口 → 缩到托盘，不退出（可在设置里关掉）
///   - 托盘图标悬停 → 显示「人生还剩 X 年 Y 天」
///   - 左键单击托盘 → 显示/隐藏主窗口
///   - 右键菜单 → 显示主窗口 / 立即同步 / 退出
///
/// 注意：托盘用的是 tray_manager 的 legacy 入口。
/// 0.7 起主入口换成了底层 nativeapi（MenuItem.createWithLabelAndType，没有 key），
/// 官方明确说老的 `legacy.dart` 会继续可用，只是标记 deprecated —— 这里图它简单好维护。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tray_manager/legacy.dart' as tray;
import 'package:window_manager/window_manager.dart';

import '../app_state.dart';

class TrayController with tray.TrayListener, WindowListener {
  TrayController({required this.state});

  final AppState state;

  bool _installed = false;
  bool _quitting = false;
  DateTime _lastTipUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  /// 只有桌面三端需要托盘；Android 没有这回事
  bool get _supported => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  Future<void> setup() async {
    if (!_supported || _installed) return;

    await windowManager.ensureInitialized();
    await windowManager.setTitle('人生任务管理器');
    await windowManager.setMinimumSize(const Size(900, 600));

    tray.trayManager.addListener(this);
    await tray.trayManager.setIcon('assets/tray.ico');
    await tray.trayManager.setToolTip(state.trayTooltip);
    await _refreshMenu();

    state.tick.addListener(_onTick);
    _installed = true;
  }

  Future<void> _refreshMenu() async {
    await tray.trayManager.setContextMenu(tray.Menu(items: [
      tray.MenuItem(key: 'show', label: '显示主窗口'),
      tray.MenuItem(key: 'sync', label: '立即同步'),
      tray.MenuItem.separator(),
      tray.MenuItem(key: 'quit', label: '退出'),
    ]));
  }

  /// 托盘提示每 30 秒刷一次就够（别每秒写一次，Windows 托盘会闪）
  void _onTick() {
    final now = DateTime.now();
    if (now.difference(_lastTipUpdate).inSeconds < 30) return;
    _lastTipUpdate = now;
    tray.trayManager.setToolTip(state.trayTooltip);
  }

  Future<void> showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onWindowClose() async {
    if (_quitting || !state.device.runInTray) {
      await _reallyQuit();
      return;
    }
    await windowManager.hide();
  }

  @override
  void onTrayIconMouseDown() => showWindow();

  @override
  void onTrayIconRightMouseDown() => tray.trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(tray.MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show':
        await showWindow();
      case 'sync':
        await state.syncNow();
        await tray.trayManager.setToolTip(state.trayTooltip);
      case 'quit':
        await _reallyQuit();
    }
  }

  Future<void> _reallyQuit() async {
    _quitting = true;
    state.tick.removeListener(_onTick);
    await tray.trayManager.destroy();
    await windowManager.destroy();
    exit(0);
  }

  void dispose() {
    if (!_installed) return;
    state.tick.removeListener(_onTick);
    windowManager.removeListener(this);
    tray.trayManager.removeListener(this);
  }
}
