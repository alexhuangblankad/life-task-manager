/// 提醒规则选择器（任务用 / 日程用）。
library;

import 'package:flutter/material.dart';

import '../model/reminder_rule.dart';
import '../utils/date_text.dart';

/// 任务提醒：不提醒 / 到期当天 / 提前N天 / 指定时间
class RemindPicker extends StatelessWidget {
  const RemindPicker({
    super.key,
    required this.initial,
    required this.onChanged,
    this.hasDue = true,
  });

  final RemindRule? initial;
  final ValueChanged<RemindRule?> onChanged;

  /// 没有到期日期的任务，只能选「指定时间」
  final bool hasDue;

  static const _base = ['不提醒', '到期当天', '提前1天', '提前3天', '提前7天', '指定时间'];

  String get _label {
    final r = initial;
    if (r == null) return '不提醒';
    return r.label;
  }

  @override
  Widget build(BuildContext context) {
    final labels = [..._base];
    if (initial != null && !labels.contains(_label)) labels.insert(1, _label);

    return DropdownButtonFormField<String>(
      initialValue: _label,
      decoration: const InputDecoration(
        labelText: '提醒 🔔',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        for (final l in labels)
          DropdownMenuItem(
            value: l,
            child: Text(
              l == '指定时间' ? '指定时间…' : l,
              style: const TextStyle(fontSize: 14),
            ),
          ),
      ],
      onChanged: (v) => _onPick(context, v),
    );
  }

  Future<void> _onPick(BuildContext context, String? v) async {
    if (v == null) return;
    switch (v) {
      case '不提醒':
        onChanged(null);
      case '到期当天':
        onChanged(const RemindRule.onDueDay());
      case '指定时间':
        await _pickAt(context);
      default:
        final m = RegExp(r'提前(\d{1,3})天').firstMatch(v);
        if (m != null) onChanged(RemindRule.daysBefore(int.parse(m.group(1)!)));
    }
  }

  Future<void> _pickAt(BuildContext context) async {
    final base = initial?.at ?? DateTime.now().add(const Duration(days: 1));
    final d = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: '选哪一天提醒',
    );
    if (d == null || !context.mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
      helpText: '几点提醒',
    );
    if (t == null) return;
    onChanged(RemindRule.at(DateTime(d.year, d.month, d.day, t.hour, t.minute)));
  }
}

/// 日程提醒：不提醒 / 开始时 / 提前N分钟（相对开始时间）
class EventRemindPicker extends StatelessWidget {
  const EventRemindPicker({
    super.key,
    required this.initial,
    required this.onChanged,
    required this.start,
  });

  final RemindRule? initial;
  final ValueChanged<RemindRule?> onChanged;
  final DateTime? start;

  static const _options = <String, int?>{
    '不提醒': null,
    '开始时': 0,
    '提前10分钟': 10,
    '提前30分钟': 30,
    '提前1小时': 60,
    '提前1天': 1440,
  };

  @override
  Widget build(BuildContext context) {
    final cur = initial;
    String label = '不提醒';
    if (cur != null && cur.kind == RemindKind.minutesBefore) {
      final m = cur.minutes ?? 0;
      for (final e in _options.entries) {
        if (e.value == m) label = e.key;
      }
    }

    return DropdownButtonFormField<String>(
      initialValue: label,
      decoration: InputDecoration(
        labelText: '提醒 🔔',
        helperText: start == null ? '先设开始时间' : '到点会弹 Windows 通知',
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        for (final k in _options.keys)
          DropdownMenuItem(value: k, child: Text(k, style: const TextStyle(fontSize: 14))),
      ],
      onChanged: (v) {
        if (v == null) return;
        final m = _options[v];
        if (m == null) {
          onChanged(null);
        } else {
          onChanged(RemindRule.minutesBefore(m));
        }
      },
    );
  }
}

/// 提醒时刻的文案（列表里显示用）
String remindText(RemindRule? r, DateTime? base) {
  if (r == null) return '';
  final at = base == null ? null : r.fireFrom(base);
  if (at == null) return r.label;
  return '🔔 ${r.label}（${formatDateTime(at)}）';
}
