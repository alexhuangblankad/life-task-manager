/// 设备本地配置（**不进 vault、不参与同步**）。
///
/// 这里放的是「每台机器不一样」的东西：vault 路径、WebDAV 账号密码、设备名。
/// 密码放进 vault 会跟着 WebDAV 一起上传，等于明文上云，所以单独存本地。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../model/ai_config.dart';

const String kAppDirName = 'LifeTaskManager';

class WebdavConfig {
  const WebdavConfig({
    this.enabled = false,
    this.url = '',
    this.username = '',
    this.password = '',
    this.remoteRoot = '/LifeTaskManager',
  });

  final bool enabled;

  /// 例：https://dav.jianguoyun.com/dav/
  final String url;
  final String username;
  final String password;

  /// 服务器上的根目录
  final String remoteRoot;

  bool get usable => enabled && url.trim().isNotEmpty && username.trim().isNotEmpty;

  WebdavConfig copyWith({
    bool? enabled,
    String? url,
    String? username,
    String? password,
    String? remoteRoot,
  }) =>
      WebdavConfig(
        enabled: enabled ?? this.enabled,
        url: url ?? this.url,
        username: username ?? this.username,
        password: password ?? this.password,
        remoteRoot: remoteRoot ?? this.remoteRoot,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'url': url,
        'username': username,
        'password': password,
        'remote_root': remoteRoot,
      };

  static WebdavConfig fromJson(Map<String, dynamic> j) => WebdavConfig(
        enabled: j['enabled'] == true,
        url: (j['url'] ?? '').toString(),
        username: (j['username'] ?? '').toString(),
        password: (j['password'] ?? '').toString(),
        remoteRoot: (j['remote_root'] ?? '/LifeTaskManager').toString(),
      );
}

class DeviceConfig {
  DeviceConfig({
    this.vaultPath = '',
    this.deviceName = '',
    this.webdav = const WebdavConfig(),
    this.lastSyncAt,
    this.themeMode = 'system',
    this.closeAction = 'tray',
    this.closeActionChosen = false,
    this.ai = const AiConfig(),
    this.fontChoice = 'noto',
    this.fontScale = 'normal',
    this.navOrder = const [],
  });

  String vaultPath;
  String deviceName;
  WebdavConfig webdav;
  DateTime? lastSyncAt;

  /// 外观：system / light / dark
  String themeMode;

  /// 点关闭按钮时的行为：'tray'（缩到右下角继续跑）或 'quit'（退出）
  String closeAction;

  /// 用户是不是已经明确选过了。没选过 → 第一次关窗口时弹窗问一次。
  bool closeActionChosen;

  /// AI 周报/月报（含 API Key，只存本机，不参与同步）
  AiConfig ai;

  /// 界面字体：'noto'（内置 Noto Sans SC）或 'system'（跟随系统）
  String fontChoice;

  /// 字号档位：small / normal / large / huge
  String fontScale;

  /// 左侧导航栏的显示顺序（页面 id 列表）。空 = 用默认顺序。
  List<String> navOrder;

  Map<String, dynamic> toJson() => {
        'version': 1,
        'vault_path': vaultPath,
        'device_name': deviceName,
        'webdav': webdav.toJson(),
        'last_sync_at': lastSyncAt?.toIso8601String(),
        'theme_mode': themeMode,
        'close_action': closeAction,
        'close_action_chosen': closeActionChosen,
        'ai': ai.toJson(),
        'font_choice': fontChoice,
        'font_scale': fontScale,
        'nav_order': navOrder,
      };

  static DeviceConfig fromJson(Map<String, dynamic> j) => DeviceConfig(
        vaultPath: (j['vault_path'] ?? '').toString(),
        deviceName: (j['device_name'] ?? '').toString(),
        webdav: WebdavConfig.fromJson((j['webdav'] as Map?)?.cast<String, dynamic>() ?? const {}),
        lastSyncAt: DateTime.tryParse((j['last_sync_at'] ?? '').toString()),
        themeMode: (j['theme_mode'] ?? 'system').toString(),
        // 老配置（v1.0.0）里只有 run_in_tray：
        //   false → 他当时就是「关窗口即退出」，视为已选过
        //   true  → 只是默认值，没明确表达过意愿 → 留到第一次关窗口时问一次
        closeAction: _closeActionOf(j),
        closeActionChosen: j['close_action_chosen'] is bool
            ? j['close_action_chosen'] as bool
            : (j['run_in_tray'] == false),
        ai: AiConfig.fromJson((j['ai'] as Map?)?.cast<String, dynamic>() ?? const {}),
        fontChoice: (j['font_choice'] ?? 'noto').toString(),
        fontScale: (j['font_scale'] ?? 'normal').toString(),
        navOrder: (j['nav_order'] is List)
            ? (j['nav_order'] as List).map((e) => e.toString()).toList()
            : const [],
      );
}

/// 设备本地配置放在哪（Windows/macOS/Linux 各按各的规矩）
String _closeActionOf(Map<String, dynamic> j) {
  final v = (j['close_action'] ?? '').toString();
  if (v == 'tray' || v == 'quit') return v;
  return j['run_in_tray'] == false ? 'quit' : 'tray';
}

String defaultDeviceConfigPath() {
  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    final base = (appData != null && appData.isNotEmpty) ? appData : p.join(home, 'AppData', 'Roaming');
    return p.join(base, kAppDirName, 'device.json');
  }
  if (Platform.isMacOS) {
    return p.join(home, 'Library', 'Application Support', kAppDirName, 'device.json');
  }
  final xdg = Platform.environment['XDG_CONFIG_HOME'];
  final base = (xdg != null && xdg.isNotEmpty) ? xdg : p.join(home, '.config');
  return p.join(base, kAppDirName, 'device.json');
}

/// 默认 vault 位置：文档目录下的 LifeTaskManager（用户可在设置里改）
String defaultVaultPath() {
  final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.';
  if (Platform.isWindows) {
    return p.join(home, 'Documents', kAppDirName);
  }
  if (Platform.isAndroid || Platform.isIOS) {
    // 手机上没有 USERPROFILE，也没有「文档目录」这个概念。
    // 先落在应用私有目录（不用申请任何权限就能读写）；
    // 想放公共目录（文件管理器里能看见）以后再加「所有文件访问权限」那条路。
    final base = Directory.systemTemp.parent.path;
    return p.join(base, 'files', kAppDirName);
  }
  return p.join(home, 'Documents', kAppDirName);
}

/// 本机默认设备名（同步冲突副本里会带上它，便于分辨是谁改的）
String defaultDeviceName() {
  final host = Platform.localHostname;
  if (host.isNotEmpty && host != 'localhost') return host;
  return Platform.operatingSystem;
}

class DeviceConfigStore {
  DeviceConfigStore({String? path}) : path = path ?? defaultDeviceConfigPath();

  final String path;

  Future<DeviceConfig> load() async {
    final f = File(path);
    if (!await f.exists()) {
      final cfg = DeviceConfig(
        vaultPath: defaultVaultPath(),
        deviceName: defaultDeviceName(),
      );
      await save(cfg);
      return cfg;
    }
    try {
      final text = await f.readAsString();
      final json = jsonDecode(text);
      if (json is Map) {
        final cfg = DeviceConfig.fromJson(json.cast<String, dynamic>());
        if (cfg.vaultPath.isEmpty) cfg.vaultPath = defaultVaultPath();
        if (cfg.deviceName.isEmpty) cfg.deviceName = defaultDeviceName();
        return cfg;
      }
    } catch (_) {
      // 配置坏了就用默认值，不要让 App 起不来
    }
    return DeviceConfig(vaultPath: defaultVaultPath(), deviceName: defaultDeviceName());
  }

  Future<void> save(DeviceConfig cfg) async {
    final f = File(path);
    await f.parent.create(recursive: true);
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(cfg.toJson()));
  }
}
