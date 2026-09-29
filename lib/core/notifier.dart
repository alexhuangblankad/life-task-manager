/// 通知的统一入口。
///
/// 桌面和安卓是两套完全不同的机制：
///
///   桌面（Windows/macOS/Linux）：`local_notifier` 直接弹一条系统通知。
///   桌面进程不会被系统随便杀，所以「App 自己每分钟检查一次 + 到点就弹」够用。
///
///   安卓：**不能靠 App 自己弹** —— 安卓会杀后台，App 不在了就什么都弹不出来。
///   正确做法是把未来要提醒的事提前交给系统的闹钟（zedSchedule），
///   到点由系统发通知，跟 App 死没死没关系。
///
/// 这个类是静态的，因为通知这东西没有「实例」的概念，全局一份就够。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:local_notifier/local_notifier.dart' as desktop;
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

class Notifier {
  Notifier._();

  static final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static bool get _isDesktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  static bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  /// 安卓/iOS 支持「预约到系统层」，桌面不支持（桌面的到点由 App 内的定时器负责）
  static bool get supportsScheduling => _isMobile;

  static const String _channelId = 'life_task_manager_reminders';
  static const String _channelName = '提醒';
  static const String _channelDesc = '任务到期、日程、定时任务的提醒';

  /// 所有预约通知共用的 ID 空间（用 key 的哈希，重预约会覆盖而不是堆一堆）
  static int idOf(String key) => key.hashCode & 0x7fffffff;

  static Future<void> init() async {
    if (_ready) return;
    try {
      if (_isDesktop) {
        await desktop.localNotifier.setup(appName: '人生任务管理器');
      } else if (_isMobile) {
        // 时区要先初始化，不然 zonedSchedule 会按 UTC 算时间
        tzdata.initializeTimeZones();
        try {
          final name = await FlutterTimezone.getLocalTimezone();
          tz.setLocalLocation(tz.getLocation(name.identifier));
        } catch (e) {
          debugPrint('[通知] 取本机时区失败，退回默认：$e');
        }

        const initSettings = InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: true,
            requestBadgePermission: true,
            requestSoundPermission: true,
          ),
        );
        await _local.initialize(initSettings);

        final android = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        await android?.createNotificationChannel(const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDesc,
          importance: Importance.high,
        ));
        // Android 13+ 要运行时申请通知权限，不申请就永远弹不出来
        await android?.requestNotificationsPermission();
        // Android 12+ 精确闹钟要单独授权（没有它系统会把提醒往后拖）
        try {
          await android?.requestExactAlarmsPermission();
        } catch (e) {
          debugPrint('[通知] 精确闹钟权限申请失败（不影响普通提醒）：$e');
        }
      }
      _ready = true;
    } catch (e) {
      debugPrint('[通知] 初始化失败：$e');
    }
  }

  /// 立刻弹一条
  static Future<void> show({required String key, required String title, required String body}) async {
    try {
      if (!_ready) await init();
      if (_isDesktop) {
        final n = desktop.LocalNotification(title: title, body: body);
        await n.show();
      } else if (_isMobile) {
        await _local.show(
          idOf(key),
          title,
          body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              _channelName,
              channelDescription: _channelDesc,
              importance: Importance.high,
              priority: Priority.high,
              color: Color(0xFF3D5AFE),
            ),
            iOS: DarwinNotificationDetails(),
          ),
        );
      }
    } catch (e) {
      debugPrint('[通知] 弹出失败：$e');
    }
  }

  /// 预约一条（安卓上靠它保证 App 被杀了也能提醒）
  static Future<void> scheduleAt({
    required String key,
    required DateTime when,
    required String title,
    required String body,
  }) async {
    if (!supportsScheduling) return;
    try {
      if (!_ready) await init();
      if (when.isBefore(DateTime.now())) return;

      await _local.zonedSchedule(
        idOf(key),
        title,
        body,
        tz.TZDateTime.from(when, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDesc,
            importance: Importance.high,
            priority: Priority.high,
            color: Color(0xFF3D5AFE),
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        // iOS 需要这个参数（安卓忽略），不传编译不过
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('[通知] 预约失败（$key）：$e');
    }
  }

  static Future<void> cancel(String key) async {
    try {
      if (_isMobile) await _local.cancel(idOf(key));
    } catch (_) {}
  }

  static Future<void> cancelAll() async {
    try {
      if (_isMobile) await _local.cancelAll();
    } catch (_) {}
  }
}
