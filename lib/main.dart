import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app_state.dart';
import 'core/device_config.dart';
import 'ui/close_choice_dialog.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';
import 'ui/tray.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_CN');

  final state = AppState();
  await state.bootstrap();

  final tray = TrayController(state: state);
  runApp(LifeTaskManagerApp(state: state, tray: tray));

  // 等第一帧渲染完再干这些重活，别卡启动
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await tray.setup();
    // 提醒记录放本机（不进 vault，免得同步来同步去）
    final localDir = File(defaultDeviceConfigPath()).parent.path;
    await state.startReminders(localDir);
    // 520KB 的历史数据延后解析，不挡启动
    await state.ensureHistory();

    // AI 周报/月报：启动先看一眼（可能今天就是出报告的日子），之后每小时看一次
    final first = await state.maybeAutoReport();
    if (first != null) debugPrint('[报告] $first');
    Timer.periodic(const Duration(hours: 1), (_) async {
      final msg = await state.maybeAutoReport();
      if (msg != null) debugPrint('[报告] $msg');
    });
  });
}

class LifeTaskManagerApp extends StatefulWidget {
  const LifeTaskManagerApp({super.key, required this.state, required this.tray});

  final AppState state;
  final TrayController tray;

  @override
  State<LifeTaskManagerApp> createState() => _LifeTaskManagerAppState();
}

class _LifeTaskManagerAppState extends State<LifeTaskManagerApp> {
  /// 弹窗要用 MaterialApp 里的 Navigator，所以留个 key
  final _navKey = GlobalKey<NavigatorState>();
  var _prompting = false;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    // 第一次点关闭按钮 → 托盘那边发信号过来，这里弹选择框
    widget.tray.closePrompt.addListener(_onClosePrompt);
  }

  @override
  void dispose() {
    widget.tray.closePrompt.removeListener(_onClosePrompt);
    super.dispose();
  }

  Future<void> _onClosePrompt() async {
    if (_prompting) return;
    final ctx = _navKey.currentContext;
    if (ctx == null) return;
    _prompting = true;
    try {
      await showCloseChoiceDialog(
        ctx,
        state: state,
        tray: widget.tray,
        firstTime: !state.device.closeActionChosen,
      );
    } finally {
      _prompting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 监听状态：改主题、改期限、勾任务之后界面才会跟着变
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => MaterialApp(
        title: '人生任务管理器',
        debugShowCheckedModeBanner: false,
        navigatorKey: _navKey,
        theme: buildAppTheme(Brightness.light, fontChoice: state.fontChoice, fontScale: state.fontScale),
        darkTheme: buildAppTheme(Brightness.dark, fontChoice: state.fontChoice, fontScale: state.fontScale),
        themeMode: state.themeMode,
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        home: HomePage(state: state),
      ),
    );
  }
}
