/// 「历史上的今天」—— 读打包在 assets 里的数据，运行时不联网。
///
/// 数据来源：百度百科「历史上的今天」 https://baike.baidu.com/calendar/
/// 打包脚本：tool/fetch_history.py（365 天 / 约 1460 条 / 520 KB）
library;

import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

class HistoryEvent {
  const HistoryEvent({
    required this.year,
    required this.title,
    this.desc = '',
    this.link,
    this.type = '',
  });

  final String year;
  final String title;
  final String desc;
  final String? link;

  /// event / birth / death
  final String type;

  /// 出生/逝世显示成不同的小标签
  String get typeLabel => switch (type) {
        'birth' => '出生',
        'death' => '逝世',
        _ => '事件',
      };

  factory HistoryEvent.fromJson(Map<String, dynamic> j) => HistoryEvent(
        year: (j['year'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        desc: (j['desc'] ?? '').toString(),
        link: (j['link'] ?? '').toString().isEmpty ? null : j['link'].toString(),
        type: (j['type'] ?? '').toString(),
      );
}

class HistoryToday {
  HistoryToday({required this.days, required this.source, required this.sourceUrl});

  final Map<String, List<HistoryEvent>> days;
  final String source;
  final String sourceUrl;

  static const String assetPath = 'assets/history_today.json';

  static HistoryToday? _cached;

  /// 读一次，之后走缓存（520 KB，解析一次就够）
  static Future<HistoryToday> load({AssetBundle? bundle, bool forceReload = false}) async {
    if (!forceReload && _cached != null) return _cached!;
    final text = await (bundle ?? rootBundle).loadString(assetPath);
    final json = jsonDecode(text) as Map<String, dynamic>;
    final days = <String, List<HistoryEvent>>{};
    final raw = json['days'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is List) {
          days[k.toString()] = v
              .whereType<Map>()
              .map((e) => HistoryEvent.fromJson(e.cast<String, dynamic>()))
              .toList();
        }
      });
    }
    _cached = HistoryToday(
      days: days,
      source: (json['source'] ?? '').toString(),
      sourceUrl: (json['source_url'] ?? '').toString(),
    );
    return _cached!;
  }

  static String keyOf(DateTime day) =>
      '${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  List<HistoryEvent> of(DateTime day) => days[keyOf(day)] ?? const [];

  /// 这天有没有内容（用来决定要不要显示卡片）
  bool has(DateTime day) => of(day).isNotEmpty;
}
