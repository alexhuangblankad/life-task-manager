/// 桌面提醒：今天到期的、今天该做的（含重复任务），各提醒一次。
///
/// 用 local_notifier 弹系统通知（Windows 右下角那种）。
/// 同一天同一条只提醒一次，提醒记录存在本机，重启也不会重复弹。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:local_notifier/local_notifier.dart';

/// 一条要提醒的事
class ReminderItem {
  const ReminderItem({required this.key, required this.title, required this.body});
  final String key;
  final String title;
  final String body;
}

class ReminderService {
  ReminderService({
    required this.collect,
    required this.storePath,
    this.onClick,
    this.clock,
  });

  /// 由外层提供「今天要提醒什么」，避免这里依赖 AppState
  final List<ReminderItem> Function() collect;
  final String storePath;
  final void Function()? onClick;
  final DateTime Function()? clock;

  Timer? _timer;
  bool _ready = false;

  DateTime get _now => (clock ?? DateTime.now)();

  bool get _supported => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  Future<void> start() async {
    if (!_supported) return;
    try {
      await localNotifier.setup(appName: '人生任务管理器');
      _ready = true;
    } catch (_) {
      // 通知不可用不是致命问题：界面里的显示照旧
      _ready = false;
      return;
    }
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => check());
    await check();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// 检查并弹出今天还没提醒过的事项
  Future<int> check() async {
    if (!_ready) return 0;
    final items = collect();
    if (items.isEmpty) return 0;

    final notified = await _load();
    var shown = 0;

    for (final item in items) {
      // key 自己就带「这一次」的标识，不用再加日期后缀
      final token = item.key;
      if (notified.contains(token)) continue;
      try {
        final n = LocalNotification(title: item.title, body: item.body);
        n.onClick = () => onClick?.call();
        await n.show();
        notified.add(token);
        shown++;
      } catch (_) {
        break; // 弹不出来就别继续了
      }
    }

    if (shown > 0) await _save(notified);
    return shown;
  }

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<Set<String>> _load() async {
    try {
      final f = File(storePath);
      if (!await f.exists()) return {};
      final json = jsonDecode(await f.readAsString());
      if (json is Map && json['notified'] is List) {
        final list = (json['notified'] as List).map((e) => e.toString()).toSet();
        // 只留最近 7 天的记录，别无限长
        final keep = <String>{};
        for (var i = 0; i < 8; i++) {
          final k = _dateKey(_now.subtract(Duration(days: i)));
          keep.addAll(list.where((e) => e.endsWith('@$k')));
        }
        return keep;
      }
    } catch (_) {}
    return {};
  }

  Future<void> _save(Set<String> notified) async {
    try {
      final f = File(storePath);
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode({'notified': notified.toList()}));
    } catch (_) {}
  }
}
