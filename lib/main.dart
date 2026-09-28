import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app_state.dart';
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

  // 等第一帧渲染完再装托盘/调窗口，避免启动卡住
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await tray.setup();
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
        theme: buildAppTheme(Brightness.light),
        darkTheme: buildAppTheme(Brightness.dark),
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
