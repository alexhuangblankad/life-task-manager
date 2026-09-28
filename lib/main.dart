import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app_state.dart';
import 'core/device_config.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';
import 'ui/tray.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_CN');

  final state = AppState();
  await state.bootstrap();

  final tray = TrayController(state: state);
  runApp(LifeTaskManagerApp(state: state));

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

class LifeTaskManagerApp extends StatelessWidget {
  const LifeTaskManagerApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    // 监听状态：改主题、改期限、勾任务之后界面才会跟着变
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => MaterialApp(
        title: '人生任务管理器',
        debugShowCheckedModeBanner: false,
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
