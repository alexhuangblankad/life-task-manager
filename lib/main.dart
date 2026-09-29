import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app_state.dart';
import 'core/device_config.dart';
import 'core/single_instance.dart';
import 'ui/close_choice_dialog.dart';
import 'ui/home_page.dart';
import 'ui/title_bar.dart';
import 'ui/theme.dart';
import 'ui/tray.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_CN');

  // 异形屏（刘海/挖孔）：开「边到边」+ 状态栏透明，内容铺到刘海下面，
  // 靠 SafeArea 把可点内容避开。比拿一条黑条糊住刘海好看得多，
  // 深色主题下也不会顶着一块亮条。
  if (Platform.isAndroid) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    ));
  }

  // 单实例：关窗口缩到托盘后进程还在，用户再点桌面图标不应该再开一个进程，
  // 而应该把已有那个的窗口叫回来。锁在进程退出时由系统自动释放。
  final localDir = File(defaultDeviceConfigPath()).parent.path;
  final single = SingleInstance(localDir);
  if (!await single.acquire()) {
    await single.requestShow();
    exit(0);
  }

  final state = AppState();
  final tray = TrayController(state: state);

  // 先把界面放出来，再加载数据。
  //
  // 原来是 `await state.bootstrap()` 挡在 runApp 前面 —— 安卓上读一堆 md +
  // 建目录要好几百毫秒到几秒，用户看到的就是长时间黑屏/白屏（"启动太慢"）。
  runApp(LifeTaskManagerApp(state: state, tray: tray));

  // 等第一帧渲染完再干这些重活，别卡启动
  // 有人点了桌面图标 → 把窗口叫回来（每秒看一眼，代价可以忽略）
  Timer.periodic(const Duration(seconds: 1), (_) async {
    if (await single.consumeShowRequest()) await tray.showWindow();
  });

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    // 先加载数据，界面这时候显示「正在打开…」
    await state.bootstrap();
    await tray.setup();
    // 提醒记录放本机（不进 vault，免得同步来同步去）；目录上面已经算过了

    // 提醒稍后再排：安卓首次要把未来 7 天的提醒逐个交给系统闹钟
    // （一串平台调用），放在启动瞬间会明显顿一下
    unawaited(Future.delayed(const Duration(seconds: 3), () => state.startReminders(localDir)));

    // 520KB 的历史数据不在这里解析了，改由「打开日历」时再触发（见 home_page）

    // AI 周报/月报：启动先看一眼（可能今天就是出报告的日子），之后每小时看一次
    unawaited(Future.delayed(const Duration(seconds: 6), () async {
      final first = await state.maybeAutoReport();
      if (first != null) debugPrint('[报告] $first');
    }));
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

  /// 界面的主体：桌面带自绘标题栏，手机没有标题栏但要躲开状态栏
  Widget _shell(AppState state) => Column(
        children: [
          const AppTitleBar(),
          Expanded(child: HomePage(state: state)),
        ],
      );

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
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          // 状态栏/导航栏图标颜色跟着主题走（深色界面用浅色图标，不然看不见）
          value: (Theme.of(context).brightness == Brightness.dark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark)
              .copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarContrastEnforced: false,
          ),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(state.fontScaleValue),
            ),
            child: child!,
          ),
        ),
        home: !state.ready
            ? const _BootScreen()
            : Stack(
          children: [
            // 先在整块窗口（包括刘海/状态栏/挖孔那条）铺一层主题底色。
            // 不铺的话 SafeArea 把内容推下去之后，上面那块没人画 → 露出窗口黑底，
            // 就是"用黑条糊住异形屏"的观感。铺了之后刘海区域跟页面同色。
            Positioned.fill(
              child: ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
            ),
            // 背景图（设了才画）+ 模糊
            if (state.backgroundPath.isNotEmpty)
              Positioned.fill(child: _AppBackground(state: state)),
            // 手机上要给状态栏留位置：桌面有自绘标题栏，手机什么都没有，
            // 不留的话页面标题会被状态栏的时钟压住（实测过）
            AppTitleBar.supported
                ? _shell(state)
                : SafeArea(bottom: false, child: _shell(state)),
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

/// 数据还没加载完时的过渡页。
///
/// 为什么不直接等：安卓上读 md + 建目录要几百毫秒到几秒，等完了再 runApp
/// 用户看到的就是长时间黑屏（抱怨的「启动太慢」）。现在先把这个画出来，
/// 数据到位后自动换成主页，感觉上快很多。
class _BootScreen extends StatelessWidget {
  const _BootScreen();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset('assets/app_icon.png', width: 72, height: 72),
            ),
            const SizedBox(height: 18),
            Text('人生任务管理器', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 14),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary),
            ),
            const SizedBox(height: 10),
            Text('正在打开本地数据…', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
