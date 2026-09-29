import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app_state.dart';
import 'core/device_config.dart';
import 'ui/close_choice_dialog.dart';
import 'ui/home_page.dart';
import 'ui/title_bar.dart';
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

  /// 主题：设了背景图就把 Scaffold 底色弄透明，不然背景全被盖住看不见
  ThemeData _themed(Brightness b) {
    final t = buildAppTheme(b, fontChoice: state.fontChoice, fontScale: state.fontScale);
    return state.backgroundPath.isEmpty ? t : t.copyWith(scaffoldBackgroundColor: Colors.transparent);
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
        theme: _themed(Brightness.light),
        darkTheme: _themed(Brightness.dark),
        themeMode: state.themeMode,
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        // 字号靠 textScaler 生效：它作用在「最终渲染的每一段文字」上，
        // 界面上那些写死 fontSize 的地方（日历小字、副标题…）也跟着变大变小。
        // 只改主题的 textTheme 是不够的 —— 那样写死的字号纹丝不动（踩过这个坑）。
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(state.fontScaleValue),
          ),
          child: child!,
        ),
        home: Stack(
          children: [
            // 背景图（设了才画）+ 模糊
            if (state.backgroundPath.isNotEmpty)
              Positioned.fill(child: _AppBackground(state: state)),
            Column(
              children: [
                const AppTitleBar(),
                Expanded(child: HomePage(state: state)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 背景图 + 模糊。模糊是为了让上面的字看得清 —— 不糊的话亮图会把字吃掉。
class _AppBackground extends StatelessWidget {
  const _AppBackground({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final file = File(state.backgroundPath);
    if (!file.existsSync()) return const SizedBox.shrink();

    final blur = state.backgroundBlur;
    Widget img = Image.file(
      file,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );

    if (blur > 0) {
      // 放大一点点：模糊会把边缘往外晕开，不放大就会在边上露出底色
      img = ClipRect(
        child: Transform.scale(
          scale: 1.08,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: img,
          ),
        ),
      );
    }
    return img;
  }
}
