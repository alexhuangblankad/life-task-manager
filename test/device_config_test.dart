import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_task_manager/core/device_config.dart';

/// 设备本地配置的落盘/读回（纯 Dart，没有 widget 测试那套假异步）
void main() {
  late Directory tmp;
  late DeviceConfigStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ltm_cfg_');
    store = DeviceConfigStore(path: '${tmp.path}/device.json');
  });

  tearDown(() async {
    try {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    } catch (_) {}
  });

  test('第一次启动会生成默认配置并落盘', () async {
    final cfg = await store.load();
    expect(cfg.vaultPath, isNotEmpty);
    expect(cfg.deviceName, isNotEmpty);
    expect(cfg.themeMode, 'system', reason: '默认跟随系统');
    expect(cfg.runInTray, isTrue, reason: '默认关窗口缩托盘');
    expect(await File(store.path).exists(), isTrue);
  });

  test('主题 / 托盘 / WebDAV / 设备名 都能存下来再读回来', () async {
    final cfg = await store.load();
    cfg.themeMode = 'dark';
    cfg.runInTray = false;
    cfg.deviceName = '书房台式机';
    cfg.webdav = const WebdavConfig(
      enabled: true,
      url: 'https://dav.jianguoyun.com/dav/',
      username: 'me@example.com',
      password: 'app-pass',
      remoteRoot: '/LifeTaskManager',
    );
    await store.save(cfg);

    final back = await store.load();
    expect(back.themeMode, 'dark');
    expect(back.runInTray, isFalse);
    expect(back.deviceName, '书房台式机');
    expect(back.webdav.enabled, isTrue);
    expect(back.webdav.username, 'me@example.com');
    expect(back.webdav.password, 'app-pass');
    expect(back.webdav.remoteRoot, '/LifeTaskManager');
  });

  test('配置坏了不能让 App 起不来', () async {
    await File(store.path).writeAsString('这不是 JSON{{{');
    final cfg = await store.load();
    expect(cfg.themeMode, 'system');
    expect(cfg.vaultPath, isNotEmpty);
  });

  test('WebdavConfig.usable：没填地址或账号就不算可用', () {
    expect(const WebdavConfig().usable, isFalse);
    expect(const WebdavConfig(enabled: true, url: 'https://x', username: '').usable, isFalse);
    expect(const WebdavConfig(enabled: false, url: 'https://x', username: 'u').usable, isFalse);
    expect(const WebdavConfig(enabled: true, url: 'https://x', username: 'u').usable, isTrue);
  });
}
