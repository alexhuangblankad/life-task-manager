import 'package:flutter/material.dart';

import '../app_state.dart';
import '../model/profile.dart';
import '../model/task.dart' show formatDate, parseDate;

/// 人生期限设置弹窗（倒计时页和设置页共用）
Future<void> showProfileEditor(BuildContext context, AppState state) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _ProfileEditor(state: state),
  );
}

class _ProfileEditor extends StatefulWidget {
  const _ProfileEditor({required this.state});
  final AppState state;

  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  late TextEditingController _name;
  late TextEditingController _years;
  DateTime? _birth;
  DateTime? _target;
  bool _showSeconds = true;
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    final p = widget.state.profile;
    _name = TextEditingController(text: p.name);
    _years = TextEditingController(text: p.lifeExpectancyYears.toString());
    _birth = p.birthDate;
    _target = p.targetDate;
    _showSeconds = p.showSeconds;
    _enabled = p.lifeCountdownEnabled;
  }

  @override
  void dispose() {
    _name.dispose();
    _years.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime? initial) async {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: initial ?? DateTime(now.year, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
      locale: const Locale('zh', 'CN'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final target = _target ?? (_birth == null
        ? null
        : DateTime(_birth!.year + (int.tryParse(_years.text) ?? 80), _birth!.month, _birth!.day));

    return AlertDialog(
      title: const Text('人生期限'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: '称呼（可留空）'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final d = await _pick(_birth);
                        if (d != null) setState(() => _birth = d);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: '出生日期'),
                        child: Text(_birth == null ? '点我选择' : formatDate(_birth!)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _years,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '预期寿命'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final d = await _pick(_target);
                        if (d != null) setState(() => _target = d);
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: '直接指定终点（可选）',
                          helperText: '填了就以它为准，忽略上面的寿命推算',
                        ),
                        child: Text(_target == null ? '未指定' : formatDate(_target!)),
                      ),
                    ),
                  ),
                  if (_target != null)
                    IconButton(
                      tooltip: '清除',
                      onPressed: () => setState(() => _target = null),
                      icon: const Icon(Icons.clear),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _showSeconds,
                onChanged: (v) => setState(() => _showSeconds = v),
                title: const Text('显示到「秒」'),
                subtitle: const Text('关掉只显示到天，省电也没那么焦虑'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
                title: const Text('开启人生倒计时'),
                subtitle: const Text('关掉后只保留大任务截止日'),
              ),
              if (target != null) ...[
                const Divider(),
                Text(
                  '终点：${formatDate(target)} 23:59:59',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () async {
            await widget.state.saveProfile(Profile(
              name: _name.text.trim(),
              birthDate: _birth,
              lifeExpectancyYears: int.tryParse(_years.text) ?? 80,
              targetDate: _target,
              showSeconds: _showSeconds,
              lifeCountdownEnabled: _enabled,
            ));
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// 给别处复用：字符串 → 日期
DateTime? parseLooseDate(String s) => parseDate(s);
