/// 设置页里的「AI 周报 / 月报」卡片。
///
/// 周期可选：每周（选周几总结上一周）/ 每两周 / 每月（选几号）/ 每季度 / 自定义天数。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/llm_client.dart';
import '../model/ai_config.dart';
import '../model/report_cycle.dart';
import 'theme.dart';

class AiSettingsCard extends StatefulWidget {
  const AiSettingsCard({super.key, required this.state});

  final AppState state;

  @override
  State<AiSettingsCard> createState() => _AiSettingsCardState();
}

class _AiSettingsCardState extends State<AiSettingsCard> {
  late TextEditingController _key;
  late TextEditingController _model;
  late TextEditingController _baseUrl;
  late TextEditingController _extra;
  var _busy = false;

  /// 输入框防抖：每敲一个字就写盘 + 刷新整个界面会卡，攒 700ms 再存
  Timer? _debounce;

  AppState get s => widget.state;
  AiConfig get cfg => s.ai;

  @override
  void initState() {
    super.initState();
    _loadControllers();
  }

  /// 文字类配置用这个：延迟保存，避免每个按键都写文件
  void _applyDebounced(AiConfig next) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), () async {
      await s.saveAiConfig(next);
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _key.dispose();
    _model.dispose();
    _baseUrl.dispose();
    _extra.dispose();
    super.dispose();
  }

  void _loadControllers() {
    _key = TextEditingController(text: cfg.apiKey);
    _model = TextEditingController(text: cfg.model);
    _baseUrl = TextEditingController(text: cfg.baseUrl);
    _extra = TextEditingController(text: cfg.extraPrompt);
  }

  Future<void> _apply(AiConfig next) async {
    await s.saveAiConfig(next);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = cfg.provider;
    final cycle = cfg.cycle;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Gaps.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('AI 周报 / 月报（可选）', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '让模型读你这个阶段的倒计时变化、完成的任务、两种杂记，给一份评语和评分。'
              '不填也能用——客观分是本地规则算的，不依赖任何模型。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),

            // ── 总开关 ──
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: cfg.enabled,
              onChanged: (v) => _apply(cfg.copyWith(enabled: v)),
              title: const Text('启用'),
              subtitle: const Text('关掉就不生成，也不会联网'),
            ),

            // ── 周期 ──
            Row(
              children: [
                const SizedBox(width: 120, child: Text('周期')),
                Expanded(
                  child: DropdownButtonFormField<ReportUnit>(
                    initialValue: cycle.unit,
                    decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                    items: [
                      for (final u in ReportUnit.values)
                        DropdownMenuItem(value: u, child: Text(u.label)),
                    ],
                    onChanged: (u) => u == null
                        ? null
                        : _apply(cfg.copyWith(cycle: ReportCycle(
                            unit: u,
                            customDays: cycle.customDays,
                            weekday: cycle.weekday,
                            monthDay: cycle.monthDay,
                          ))),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── 哪天生成（按周期显示不同的选择）──
            if (cycle.unit == ReportUnit.week || cycle.unit == ReportUnit.biweek) ...[
              Row(
                children: [
                  const SizedBox(width: 120, child: Text('哪天总结')),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: cycle.weekday,
                      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('周一')),
                        DropdownMenuItem(value: 2, child: Text('周二')),
                        DropdownMenuItem(value: 3, child: Text('周三')),
                        DropdownMenuItem(value: 4, child: Text('周四')),
                        DropdownMenuItem(value: 5, child: Text('周五')),
                        DropdownMenuItem(value: 6, child: Text('周六')),
                        DropdownMenuItem(value: 7, child: Text('周日')),
                      ],
                      onChanged: (w) => w == null
                          ? null
                          : _apply(cfg.copyWith(cycle: ReportCycle(
                              unit: cycle.unit,
                              customDays: cycle.customDays,
                              weekday: w,
                              monthDay: cycle.monthDay,
                            ))),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],

            if (cycle.unit == ReportUnit.month || cycle.unit == ReportUnit.quarter) ...[
              Row(
                children: [
                  const SizedBox(width: 120, child: Text('每月几号')),
                  SizedBox(
                    width: 100,
                    child: TextFormField(
                      initialValue: '${cycle.monthDay}',
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), suffixText: '号'),
                      onFieldSubmitted: (v) {
                        final n = int.tryParse(v.trim());
                        if (n == null) return;
                        _apply(cfg.copyWith(cycle: ReportCycle(
                          unit: cycle.unit,
                          customDays: cycle.customDays,
                          weekday: cycle.weekday,
                          monthDay: n.clamp(1, 28),
                        )));
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],

            if (cycle.unit == ReportUnit.custom) ...[
              Row(
                children: [
                  const SizedBox(width: 120, child: Text('多少天一期')),
                  SizedBox(
                    width: 100,
                    child: TextFormField(
                      initialValue: '${cycle.customDays}',
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), suffixText: '天'),
                      onFieldSubmitted: (v) {
                        final n = int.tryParse(v.trim());
                        if (n == null) return;
                        _apply(cfg.copyWith(cycle: ReportCycle(
                          unit: cycle.unit,
                          customDays: n.clamp(1, 365),
                          weekday: cycle.weekday,
                          monthDay: cycle.monthDay,
                        )));
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('📅 ${cycle.description}', style: theme.textTheme.bodySmall),
            ),
            const Divider(height: 28),

            // ── 发行商 ──
            Row(
              children: [
                const SizedBox(width: 120, child: Text('发行商')),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: cfg.providerId,
                    decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                    items: [
                      for (final prov in kAiProviders)
                        DropdownMenuItem(value: prov.id, child: Text(prov.name, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (id) => id == null
                        ? null
                        : _apply(cfg.copyWith(
                            providerId: id,
                            // 换发行商时把模型名和地址清空，回到预设默认值
                            model: '',
                            baseUrl: '',
                          )),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (p.hint.isNotEmpty)
              Text('ℹ️ ${p.hint}', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 10),

            // ── API Key ──
            TextField(
              controller: _key,
              obscureText: true,
              decoration: InputDecoration(
                labelText: p.needsKey ? 'API Key' : 'API Key（本机模型不用填）',
                border: const OutlineInputBorder(),
                isDense: true,
                helperText: '只存在本机（不参与 WebDAV 同步），当前：${maskKey(cfg.apiKey)}',
              ),
              onChanged: (v) => cfg.apiKey == v ? null : _applyDebounced(cfg.copyWith(apiKey: v)),
            ),
            const SizedBox(height: 10),

            // ── 模型 / 地址 ──
            TextField(
              controller: _model,
              decoration: InputDecoration(
                labelText: '模型名',
                hintText: p.defaultModel.isEmpty ? '自己填，比如 qwen-plus' : p.defaultModel,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => _applyDebounced(cfg.copyWith(model: v)),
            ),
            if (cfg.providerId == 'custom' || p.baseUrl.isEmpty) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _baseUrl,
                decoration: const InputDecoration(
                  labelText: '接口地址',
                  hintText: 'https://xxx/v1',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => _applyDebounced(cfg.copyWith(baseUrl: v)),
              ),
            ],
            const SizedBox(height: 10),

            TextField(
              controller: _extra,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '额外要求（可空）',
                hintText: '比如：多说缺点，别夸我',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => _applyDebounced(cfg.copyWith(extraPrompt: v)),
            ),
            const Divider(height: 28),

            // ── 动作 ──
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _generateNow,
                  icon: _busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome, size: 18),
                  label: Text(_busy ? '生成中…' : '立即生成上一期'),
                ),
                OutlinedButton.icon(
                  onPressed: _showReports,
                  icon: const Icon(Icons.article_outlined, size: 18),
                  label: const Text('看已生成的报告'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _testConnection,
                  icon: const Icon(Icons.cable, size: 18),
                  label: const Text('测一下能不能连上'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '注：模型调用会产生费用（Ollama 除外）。这里只发统计和摘录，不发原始文件。',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generateNow() async {
    setState(() => _busy = true);
    try {
      final report = await s.generateReport();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('已生成 ${report.label}-${report.summary.suffix}｜客观分 ${report.summary.objectiveScore}｜综合 ${report.overallScore}'),
        action: SnackBarAction(
          label: '看',
          onPressed: () => _showReportFile('${report.label}-${report.summary.suffix}.md'),
        ),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('生成失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _testConnection() async {
    if (!cfg.ready) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没配好：检查启用开关、API Key、模型名')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      // 发一句最短的话看有没有回
      final text = await LlmClient().chat(
        cfg: cfg,
        systemPrompt: '你只需要回一个字。',
        userPrompt: '回复：好',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('通了：${text.trim()}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('没通：$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showReports() async {
    final names = await s.listReports();
    if (!mounted) return;
    if (names.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('还没生成过报告')));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('已生成的报告'),
        content: SizedBox(
          width: 420,
          height: 380,
          child: ListView.builder(
            itemCount: names.length,
            itemBuilder: (_, i) => ListTile(
              dense: true,
              leading: const Icon(Icons.description_outlined),
              title: Text(names[i]),
              onTap: () {
                Navigator.pop(ctx);
                _showReportFile(names[i]);
              },
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
      ),
    );
  }

  Future<void> _showReportFile(String fileName) async {
    final text = await s.readReport(fileName);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(fileName),
        content: SizedBox(
          width: 640,
          height: 480,
          child: SingleChildScrollView(child: SelectableText(text ?? '读不到这个文件')),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
      ),
    );
  }
}
