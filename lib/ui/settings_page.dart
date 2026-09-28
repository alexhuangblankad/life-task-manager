import 'dart:io';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/app_info.dart';
import '../core/device_config.dart';
import '../model/profile.dart';
import '../utils/date_text.dart';
import 'ai_settings_card.dart';
import 'home_page.dart';
import 'profile_dialog.dart';
import 'theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.state});

  final AppState state;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _vault;
  late final TextEditingController _device;
  late final TextEditingController _url;
  late final TextEditingController _user;
  late final TextEditingController _pass;
  late final TextEditingController _root;
  bool _enabled = false;
  bool _busy = false;
  String _testResult = '';

  AppState get s => widget.state;

  @override
  void initState() {
    super.initState();
    final d = s.device;
    _vault = TextEditingController(text: d.vaultPath);
    _device = TextEditingController(text: d.deviceName);
    _url = TextEditingController(text: d.webdav.url);
    _user = TextEditingController(text: d.webdav.username);
    _pass = TextEditingController(text: d.webdav.password);
    _root = TextEditingController(text: d.webdav.remoteRoot);
    _enabled = d.webdav.enabled;
  }

  @override
  void dispose() {
    for (final c in [_vault, _device, _url, _user, _pass, _root]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final d = s.device;
    d.deviceName = _device.text.trim().isEmpty ? defaultDeviceName() : _device.text.trim();
    d.webdav = WebdavConfig(
      enabled: _enabled,
      url: _url.text.trim(),
      username: _user.text.trim(),
      password: _pass.text,
      remoteRoot: _root.text.trim().isEmpty ? '/LifeTaskManager' : _root.text.trim(),
    );
    final newVault = _vault.text.trim();
    if (newVault.isNotEmpty && newVault != d.vaultPath) {
      await s.changeVaultPath(newVault);
    } else {
      await s.saveDeviceConfig();
    }
    if (mounted) setState(() => _testResult = '已保存');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final profile = s.profile;
    final target = profile.lifeTarget;

    return PageScaffold(
      title: '设置',
      subtitle: '数据都在你自己的盘上，服务器只用来同步',
      actions: [
        FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save, size: 18), label: const Text('保存设置')),
      ],
      child: ListView(
        padding: Gaps.page,
        children: [
          // ── 人生期限 ──
          _Card(
            title: '人生期限',
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(target == null ? '还没设置' : '终点：${formatDateCn(target)}'),
                subtitle: Text(
                  profile.configured
                      ? '出生 ${profile.birthDate == null ? "未填" : formatDateCn(profile.birthDate!)} · '
                          '预期 ${profile.lifeExpectancyYears} 年 · '
                          '${profile.showSeconds ? "显示到秒" : "只显示到天"}'
                      : '填了出生日期和预期寿命，倒计时页就开始跳数字',
                ),
                trailing: OutlinedButton(
                  onPressed: () => showProfileEditor(context, s),
                  child: const Text('修改'),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gaps.l),

          // ── 外观 ──
          _Card(
            title: '外观',
            children: [
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'system', label: Text('跟随系统'), icon: Icon(Icons.brightness_auto_outlined)),
                    ButtonSegment(value: 'light', label: Text('亮色'), icon: Icon(Icons.light_mode_outlined)),
                    ButtonSegment(value: 'dark', label: Text('暗色'), icon: Icon(Icons.dark_mode_outlined)),
                  ],
                  selected: {s.device.themeMode},
                  onSelectionChanged: (v) async {
                    await s.setThemeMode(v.first);
                    if (mounted) setState(() {});
                  },
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const SizedBox(width: 72, child: Text('关窗口时')),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: s.device.closeAction,
                      isDense: true,
                      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'tray', child: Text('缩到右下角托盘，后台继续跑', style: TextStyle(fontSize: 14))),
                        DropdownMenuItem(value: 'quit', child: Text('直接退出程序', style: TextStyle(fontSize: 14))),
                      ],
                      onChanged: (v) async {
                        if (v == null) return;
                        await s.setCloseAction(v);
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                ],
              ),
              Text(
                '缩到托盘时倒计时和提醒继续跑，点托盘图标能叫回来；右键托盘可以同步或退出。'
                '第一次关窗口时会先问你一次，这个选择也能在这儿改。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Divider(height: 24),
              Row(
                children: [
                  const SizedBox(width: 72, child: Text('字体')),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: s.fontChoice,
                      isDense: true,
                      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                      items: [
                        for (final f in kFontChoices)
                          DropdownMenuItem(value: f.id, child: Text(f.name, style: const TextStyle(fontSize: 14))),
                      ],
                      onChanged: (v) async {
                        if (v == null) return;
                        await s.setFont(choice: v);
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const SizedBox(width: 72, child: Text('字号')),
                  Expanded(
                    child: SegmentedButton<String>(
                      segments: [
                        for (final f in kFontScales) ButtonSegment(value: f.id, label: Text(f.name)),
                      ],
                      selected: {s.fontScale},
                      onSelectionChanged: (v) async {
                        await s.setFont(scale: v.first);
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '看不清就先调字号。默认字体是内置的 Noto Sans SC（开源，观感接近苹果的苹方，'
                '笔画比系统默认的雅黑清楚），安卓上也自带一份，不用看系统脸色。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: Gaps.l),

          // ── AI 周报 / 月报 ──
          AiSettingsCard(state: s),
          const SizedBox(height: Gaps.l),

          // ── 日历小趣味 ──
          _Card(
            title: '日历小趣味（不想看就都关掉）',
            children: [
              _prefSwitch(s, '农历与节气', '日历格子里那行小字：农历日 / 节气 / 节日名',
                  s.calendarPrefs.showLunar, (v) => s.calendarPrefs.copyWith(showLunar: v)),
              _prefSwitch(s, '法定节假日', '放假标「休」、调休上班标「班」',
                  s.calendarPrefs.showHoliday, (v) => s.calendarPrefs.copyWith(showHoliday: v)),
              _prefSwitch(s, '节日祝福', '过节那天在日历里写一句',
                  s.calendarPrefs.showGreeting, (v) => s.calendarPrefs.copyWith(showGreeting: v)),
              _prefSwitch(s, '历史上的今天', '每天几条真实事件（数据打包在本地，不联网）',
                  s.calendarPrefs.showHistory, (v) => s.calendarPrefs.copyWith(showHistory: v)),
              _prefSwitch(s, '宜忌', '黄历那套，默认关',
                  s.calendarPrefs.showYiJi, (v) => s.calendarPrefs.copyWith(showYiJi: v)),
              const Divider(height: 24),
              _prefSwitch(s, '到期当天弹桌面提醒', '今天到期 / 今天该做的定时任务，弹一次系统通知',
                  s.calendarPrefs.remindOnTaskDay, (v) => s.calendarPrefs.copyWith(remindOnTaskDay: v)),
              Text(
                '注：法定节假日的数据是随包里带的年度表，目前覆盖到 2026 年；之后要等农历库更新（界面不会瞎猜，没有就不显示）。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: Gaps.l),

          // ── 数据位置 ──
          _Card(
            title: '数据位置（本地已有的一份）',
            children: [
              TextField(
                controller: _vault,
                decoration: const InputDecoration(
                  labelText: 'vault 文件夹',
                  helperText: '所有数据都是这个文件夹里的纯文本文件，用 Obsidian 也能直接打开',
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _openFolder(_vault.text),
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('打开文件夹'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _vault.text = defaultVaultPath()),
                    icon: const Icon(Icons.restore, size: 18),
                    label: const Text('恢复默认位置'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _device,
                decoration: const InputDecoration(
                  labelText: '这台设备的名称',
                  helperText: '同步冲突时用得到：冲突副本文件名里会带上它',
                ),
              ),
            ],
          ),
          const SizedBox(height: Gaps.l),

          // ── WebDAV ──
          _Card(
            title: 'WebDAV 同步（坚果云）',
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
                title: const Text('启用同步'),
              ),
              TextField(
                controller: _url,
                decoration: const InputDecoration(
                  labelText: '服务器地址',
                  hintText: 'https://dav.jianguoyun.com/dav/',
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _user,
                      decoration: const InputDecoration(labelText: '账号（坚果云登录邮箱）'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _pass,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: '应用密码',
                        helperText: '坚果云后台「安全选项 → 添加应用密码」生成，不是登录密码',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _root,
                decoration: const InputDecoration(labelText: '服务器上的目录', hintText: '/LifeTaskManager'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _testConnection,
                    icon: const Icon(Icons.wifi_tethering, size: 18),
                    label: const Text('测试连接'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _runSync(dryRun: true),
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('预演同步'),
                  ),
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _runSync(dryRun: false),
                    icon: const Icon(Icons.cloud_sync, size: 18),
                    label: const Text('立即同步'),
                  ),
                ],
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
              if (_testResult.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_testResult, style: TextStyle(color: scheme.primary)),
                ),
              if (s.device.lastSyncAt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('上次同步：${relativeTime(s.device.lastSyncAt!)}'),
                ),
              if (s.lastSyncReport != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    s.lastSyncReport!.summary,
                    style: TextStyle(
                      color: s.lastSyncReport!.errors.isEmpty ? scheme.primary : scheme.error,
                    ),
                  ),
                ),
              if (s.lastSyncReport?.conflictPaths.isNotEmpty ?? false)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('发现冲突，两份都保留了：', style: TextStyle(color: scheme.error)),
                      for (final p in s.lastSyncReport!.conflictPaths)
                        Text('· $p', style: Theme.of(context).textTheme.bodySmall),
                      Text(
                        '看完之后，删掉不需要的那份就行。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              if (s.syncLog.isNotEmpty) ...[
                const Divider(height: 24),
                Text('同步日志', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                Container(
                  constraints: const BoxConstraints(maxHeight: 140),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final line in s.syncLog)
                          Text(line, style: const TextStyle(fontSize: 12, height: 1.4)),
                      ],
                    ),
                  ),
                ),
              ],
              const Divider(height: 24),
              Text(
                '坚果云免费版限制：每 30 分钟最多 600 次请求、每月上传 1GB / 下载 3GB。'
                '所以同步是「攒着一起做」，不会改一个字就传一次。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: Gaps.l),

          // ── 支持作者 ──
          _Card(
            title: '支持作者',
            children: [
              const Text('软件免费、开源，代码和数据都在你自己手里，所有功能都不需要付费。'),
              const SizedBox(height: 6),
              const Text('如果它确实帮到你了，可以扫码请我喝瓶水（定额 5 元，纯自愿，不解锁任何东西）。'),
              const SizedBox(height: 16),
              Center(
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset('assets/donate_qr.png', width: 300),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '微信扫码支持 5 元',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '定额 5 元，纯属自愿 —— 收不收都不影响任何功能，软件该有的全都有',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Gaps.l),

          const SizedBox(height: Gaps.l),

          // ── 导航栏顺序 ──
          _Card(
            title: '导航栏顺序（按自己的习惯排）',
            children: [
              Text(
                '把最常用的放最前面。比如你主要用日历，就把「日历」挪到第一位，'
                '倒计时放最后也行 —— 四个功能谁主谁次，你说了算。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _navOrderOf(s).length; i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(_navIcons[_navOrderOf(s)[i]] ?? Icons.circle_outlined),
                  title: Text(_navLabels[_navOrderOf(s)[i]] ?? _navOrderOf(s)[i]),
                  subtitle: i == 0 ? const Text('第一个（打开就显示这页）') : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '上移',
                        icon: const Icon(Icons.keyboard_arrow_up),
                        onPressed: i == 0 ? null : () => _moveNav(s, i, -1),
                      ),
                      IconButton(
                        tooltip: '下移',
                        icon: const Icon(Icons.keyboard_arrow_down),
                        onPressed: i == _navOrderOf(s).length - 1 ? null : () => _moveNav(s, i, 1),
                      ),
                    ],
                  ),
                ),
              if (s.navOrder.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      await s.setNavOrder(const []);
                      if (mounted) setState(() {});
                    },
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const Text('恢复默认顺序'),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Gaps.l),
          // ── 关于 ──
          _Card(
            title: '关于',
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset('assets/app_icon.png', width: 56, height: 56),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$kAppName $kAppVersion',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(kAppTagline,
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 2),
                        SelectableText(
                          kAppRepoUrl,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.primary,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Text(
                '你的数据长这样（全是纯文本，Obsidian 也能直接读）：',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'config/profile.json   人生期限、日历开关\n'
                '大任务/                一个大任务一个 .md\n'
                '日程/202609.json       按月存，可设每天/每周/农历每月重复\n'
                '杂记/202609/           日记/ 和 任务/ 两个子目录\n'
                '报告/                  周报、月报、季报（AI 评分）\n'
                '回收站/                删掉的东西放这儿',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'Consolas', height: 1.6),
              ),
              const Divider(height: 24),
              Text(
                '许可：MIT（随便用、随便改、随便分发，保留版权声明即可）\n'
                '数据默认在「文档\\LifeTaskManager」，和程序目录分开 —— 卸载软件不会删数据',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.6),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _testConnection() async {
    setState(() {
      _busy = true;
      _testResult = '';
    });
    await _saveSilently();
    final result = await s.testWebdav();
    if (mounted) {
      setState(() {
        _busy = false;
        _testResult = result;
      });
    }
  }

  Future<void> _runSync({required bool dryRun}) async {
    setState(() => _busy = true);
    await _saveSilently();
    await s.syncNow(dryRun: dryRun);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _saveSilently() async {
    final d = s.device;
    d.deviceName = _device.text.trim().isEmpty ? defaultDeviceName() : _device.text.trim();
    d.webdav = WebdavConfig(
      enabled: _enabled,
      url: _url.text.trim(),
      username: _user.text.trim(),
      password: _pass.text,
      remoteRoot: _root.text.trim().isEmpty ? '/LifeTaskManager' : _root.text.trim(),
    );
    await s.saveDeviceConfig();
  }


  static const _navLabels = <String, String>{
    'countdown': '倒计时',
    'calendar': '日历',
    'tasks': '待办',
    'notes': '杂记',
    'settings': '设置',
  };

  static const _navIcons = <String, IconData>{
    'countdown': Icons.hourglass_bottom_outlined,
    'calendar': Icons.calendar_month_outlined,
    'tasks': Icons.checklist_outlined,
    'notes': Icons.edit_note_outlined,
    'settings': Icons.settings_outlined,
  };

  static const _navDefault = ['countdown', 'calendar', 'tasks', 'notes', 'settings'];

  List<String> _navOrderOf(AppState s) => s.navOrder.isEmpty ? _navDefault : s.navOrder;

  /// 上移/下移一格，立刻存下来
  Future<void> _moveNav(AppState s, int i, int delta) async {
    final order = [..._navOrderOf(s)];
    final j = i + delta;
    if (j < 0 || j >= order.length) return;
    final t = order[i];
    order[i] = order[j];
    order[j] = t;
    await s.setNavOrder(order);
    if (mounted) setState(() {});
  }

  /// 日历小趣味开关：勾一下立刻存进 vault（跟着同步走）
  Widget _prefSwitch(
    AppState st,
    String title,
    String subtitle,
    bool value,
    CalendarPrefs Function(bool) build,
  ) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      value: value,
      onChanged: (v) async {
        await st.saveCalendarPrefs(build(v));
        if (mounted) setState(() {});
      },
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
    );
  }

  Future<void> _openFolder(String path) async {
    if (path.trim().isEmpty) return;
    final dir = Directory(path);
    if (!await dir.exists()) await dir.create(recursive: true);
    if (Platform.isWindows) {
      await Process.run('explorer', [dir.path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [dir.path]);
    } else {
      await Process.run('xdg-open', [dir.path]);
    }
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gaps.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Gaps.m),
            ...children,
          ],
        ),
      ),
    );
  }
}
