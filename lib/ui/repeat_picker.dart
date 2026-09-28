/// 重复规则选择器（通用版）。
///
/// 用在「日程」上：每天 / 每周（可多选）/ 每月（可多个日子）/ 每月农历（可多个日子，
/// 比如初一、十五）/ 每年 / 每年农历。
library;

import 'package:flutter/material.dart';

import '../model/repeat.dart';

class RepeatPicker extends StatefulWidget {
  const RepeatPicker({
    super.key,
    required this.initial,
    required this.onChanged,
    this.title = '重复',
  });

  final RepeatRule? initial;
  final ValueChanged<RepeatRule?> onChanged;
  final String title;

  @override
  State<RepeatPicker> createState() => _RepeatPickerState();
}

class _RepeatPickerState extends State<RepeatPicker> {
  static const _kindLabels = <RepeatKind, String>{
    RepeatKind.daily: '每天',
    RepeatKind.weekly: '每周',
    RepeatKind.monthly: '每月',
    RepeatKind.lunarMonthly: '每月农历',
    RepeatKind.yearly: '每年',
    RepeatKind.lunarYearly: '每年农历',
  };

  RepeatKind? _kind;
  final Set<int> _weekdays = {};
  late TextEditingController _days;
  int _month = 1;
  int _day = 1;

  static const _weekNames = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    _kind = r?.kind;
    if (r != null) {
      if (r.kind == RepeatKind.weekly) {
        _weekdays.addAll(r.effectiveDays);
      } else if (r.kind == RepeatKind.monthly) {
        _days = TextEditingController(text: r.effectiveDays.join('、'));
      } else if (r.kind == RepeatKind.lunarMonthly) {
        _days = TextEditingController(text: r.effectiveDays.map(lunarDayLabel).join('、'));
      }
      _month = r.month ?? 1;
      _day = r.day ?? 1;
    }
    _days = (_daysOrNull()) ?? TextEditingController();
    if (r != null && r.kind == RepeatKind.yearly && _day != 0) {
      _days.text = '$_day';
    }
    if (r != null && r.kind == RepeatKind.lunarYearly) {
      _days.text = lunarDayLabel(_day);
    }
  }

  TextEditingController? _daysOrNull() {
    final r = widget.initial;
    if (r == null) return null;
    if (r.kind == RepeatKind.monthly) return TextEditingController(text: r.effectiveDays.join('、'));
    if (r.kind == RepeatKind.lunarMonthly) return TextEditingController(text: r.effectiveDays.map(lunarDayLabel).join('、'));
    return null;
  }

  @override
  void dispose() {
    _days.dispose();
    super.dispose();
  }

  /// 把「1、15」或「初一、十五」解析成天数列表
  List<int> _parseDays(String raw, int max, {bool lunar = false}) {
    final out = <int>[];
    for (final part in raw.split(RegExp(r'[、,，和及\s]+'))) {
      var t = part.trim();
      if (t.isEmpty) continue;
      t = t.replaceAll(RegExp(r'[日号]$'), '');
      final v = lunar ? chineseNumber(t) : int.tryParse(t);
      if (v == null || v < 1 || v > max) continue;
      if (!out.contains(v)) out.add(v);
    }
    out.sort();
    return out;
  }

  void _emit() {
    final k = _kind;
    if (k == null) {
      widget.onChanged(null);
      return;
    }
    RepeatRule? from(List<int> ds, RepeatRule Function(int) one, RepeatRule Function(List<int>) many) {
      if (ds.isEmpty) return null;
      return ds.length == 1 ? one(ds.first) : many(ds);
    }

    switch (k) {
      case RepeatKind.daily:
        widget.onChanged(const RepeatRule(kind: RepeatKind.daily));
      case RepeatKind.weekly:
        final ws = _weekdays.toList()..sort();
        widget.onChanged(from(
          ws,
          (w) => RepeatRule(kind: RepeatKind.weekly, day: w),
          (l) => RepeatRule(kind: RepeatKind.weekly, daysList: l),
        ));
      case RepeatKind.monthly:
        widget.onChanged(from(
          _parseDays(_days.text, 31),
          (d) => RepeatRule(kind: RepeatKind.monthly, day: d),
          (l) => RepeatRule(kind: RepeatKind.monthly, daysList: l),
        ));
      case RepeatKind.lunarMonthly:
        widget.onChanged(from(
          _parseDays(_days.text, 30, lunar: true),
          (d) => RepeatRule(kind: RepeatKind.lunarMonthly, day: d),
          (l) => RepeatRule(kind: RepeatKind.lunarMonthly, daysList: l),
        ));
      case RepeatKind.yearly:
        final d = int.tryParse(_days.text.trim());
        widget.onChanged(d == null || d < 1 || d > 31
            ? null
            : RepeatRule(kind: RepeatKind.yearly, month: _month.clamp(1, 12), day: d));
      case RepeatKind.lunarYearly:
        final d = chineseNumber(_days.text);
        widget.onChanged(d == null || d < 1 || d > 30
            ? null
            : RepeatRule(kind: RepeatKind.lunarYearly, month: _month.clamp(1, 12), day: d));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final k = _kind;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(width: 105, child: Text(widget.title, style: theme.textTheme.bodyMedium)),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: k?.name ?? 'none',
                isDense: true,
                decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                items: [
                  const DropdownMenuItem(value: 'none', child: Text('不重复', style: TextStyle(fontSize: 14))),
                  for (final e in _kindLabels.entries)
                    DropdownMenuItem(value: e.key.name, child: Text(e.value, style: const TextStyle(fontSize: 14))),
                ],
                onChanged: (v) {
                  setState(() {
                    _kind = v == null || v == 'none'
                        ? null
                        : RepeatKind.values.firstWhere((x) => x.name == v, orElse: () => RepeatKind.daily);
                  });
                  _emit();
                },
              ),
            ),
          ],
        ),

        // 每周：多选
        if (k == RepeatKind.weekly) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              for (var w = 1; w <= 7; w++)
                FilterChip(
                  label: Text('周${_weekNames[w - 1]}', style: const TextStyle(fontSize: 13)),
                  selected: _weekdays.contains(w),
                  onSelected: (on) {
                    setState(() => on ? _weekdays.add(w) : _weekdays.remove(w));
                    _emit();
                  },
                ),
            ],
          ),
        ],

        // 每月 / 每月农历：可以填多个
        if (k == RepeatKind.monthly || k == RepeatKind.lunarMonthly) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _days,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              labelText: k == RepeatKind.monthly ? '每月哪几号' : '每月农历哪几天',
              hintText: k == RepeatKind.monthly ? '可以填多个：1、15' : '可以填多个：初一、十五',
              helperText: k == RepeatKind.lunarMonthly ? '中文数字，顿号隔开' : null,
            ),
            onChanged: (_) => _emit(),
          ),
        ],

        // 每年 / 每年农历：月 + 日
        if (k == RepeatKind.yearly || k == RepeatKind.lunarYearly) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 90,
                child: TextFormField(
                  initialValue: k == RepeatKind.lunarYearly ? chineseMonthLabel(_month) : '$_month',
                  decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), labelText: '月'),
                  onFieldSubmitted: (v) {
                    final m = k == RepeatKind.lunarYearly ? chineseNumber(v) : int.tryParse(v.trim());
                    if (m == null) return;
                    setState(() => _month = m.clamp(1, 12));
                    _emit();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _days,
                  decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), labelText: '日'),
                  onChanged: (_) => _emit(),
                ),
              ),
            ],
          ),
        ],

        if (k != null) ...[
          const SizedBox(height: 6),
          Text(
            '📌 ${_preview()}',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
          ),
        ],
      ],
    );
  }

  /// 给用户看一眼「到底会怎么重复」
  String _preview() {
    final k = _kind;
    if (k == null) return '不重复';
    switch (k) {
      case RepeatKind.daily:
        return '每天都会出现';
      case RepeatKind.weekly:
        final ws = _weekdays.toList()..sort();
        return ws.isEmpty ? '还没选周几' : '每周${ws.map((w) => _weekNames[w - 1]).join('、')}';
      case RepeatKind.monthly:
        final ds = _parseDays(_days.text, 31);
        return ds.isEmpty ? '还没填日子' : '每月 ${ds.join('、')} 号';
      case RepeatKind.lunarMonthly:
        final ds = _parseDays(_days.text, 30, lunar: true);
        return ds.isEmpty ? '还没填日子' : '每月农历 ${ds.map(lunarDayLabel).join('、')}';
      case RepeatKind.yearly:
        return '每年 $_month 月 ${_days.text} 日';
      case RepeatKind.lunarYearly:
        final d = chineseNumber(_days.text);
        return '每年农历${chineseMonthLabel(_month)}月${d == null ? '?' : lunarDayLabel(d)}';
    }
  }
}
