/// 提醒服务：收集「该提醒的事」→ 到点弹 / 预约。
///
/// 两端的差别（重要）：
///   桌面：每分钟检查一次，到点就用 local_notifier 弹（桌面进程不会被杀，够用）
///   安卓：往前多看几天，把未来要提醒的事**提前预约到系统闹钟**（zedSchedule），
///        这样 App 被系统杀掉也照样提醒。只靠 App 自己弹在安卓上等于没有提醒。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'notifier.dart';

/// 一条要提醒的事
class ReminderItem {
  const ReminderItem({
    required this.key,
    required this.title,
    required this.body,
    this.fireAt,
  });

  /// 唯一标识，带上「这一次」的信息（日期或时刻），同一次只提醒一回
  final String key;
  final String title;
  final String body;

  /// 该在什么时候弹；null = 立刻
  final DateTime? fireAt;
}

class ReminderService {
  ReminderService({required this.collect, required this.storePath});

  /// 给定某一天，返回那天要提醒的事（由 AppState 提供）
  final List<ReminderItem> Function(DateTime day) collect;
  final String storePath;

  Timer? _timer;
  final Set<String> _handled = {};

  /// 往前看几天（补提醒：关机/没开 App 期间错过的）
  static const int _daysBack = 7;

  /// 往后看几天（安卓上要提前交给系统闹钟）
  static const int _daysAhead = 7;

  Future<void> start() async {
    await _load();
    await Notifier.init();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => check());
    await check();
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  /// 检查一遍：到点的弹出来，未来的（安卓）预约给系统。返回这次处理了几条。
  Future<int> check() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var count = 0;

    for (var offset = -_daysBack; offset <= _daysAhead; offset++) {
      final day = today.add(Duration(days: offset));
      List<ReminderItem> items;
      try {
        items = collect(day);
      } catch (e) {
        continue; // 某天算挂了不能影响其它天
      }

      for (final item in items) {
        if (_handled.contains(item.key)) continue;
        final at = item.fireAt ?? now;

        if (at.isAfter(now)) {
          // 还没到点：移动端交给系统闹钟；桌面端留着自己到点再弹
          if (Notifier.supportsScheduling) {
            await Notifier.scheduleAt(
              key: item.key,
              when: at,
              title: item.title,
              body: item.body,
            );
            _handled.add(item.key);
            count++;
          }
          continue;
        }

        // 已经到点（含补最近几天错过的）
        await Notifier.show(key: item.key, title: item.title, body: item.body);
        _handled.add(item.key);
        count++;
      }
    }

    if (count > 0) await _save();
    return count;
  }

  // ── 记录哪些提醒已经处理过（存本机，不进 vault）──

  Future<void> _load() async {
    try {
      final f = File(storePath);
      if (!await f.exists()) return;
      final json = jsonDecode(await f.readAsString());
      if (json is List) {
        _handled.addAll(json.map((e) => e.toString()));
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      // 只留最近这些，别让文件无限长大
      final list = _handled.length > 600 ? _handled.toList().sublist(_handled.length - 600) : _handled.toList();
      final f = File(storePath);
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode(list));
    } catch (_) {}
  }
}
