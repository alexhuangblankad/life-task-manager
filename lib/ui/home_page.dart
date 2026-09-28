import 'package:flutter/material.dart';

import '../app_state.dart';
import 'calendar_page.dart';
import 'countdown_page.dart';
import 'notes_page.dart';
import 'settings_page.dart';
import 'tasks_page.dart';
import 'theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.state});

  final AppState state;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    final s = widget.state;
    _pages = [
      CountdownPage(state: s),
      CalendarPage(state: s),
      TasksPage(state: s),
      NotesPage(state: s),
      SettingsPage(state: s),
    ];
  }

  static const _destinations = [
    NavigationRailDestination(icon: Icon(Icons.hourglass_bottom_outlined), selectedIcon: Icon(Icons.hourglass_bottom), label: Text('倒计时')),
    NavigationRailDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: Text('日历')),
    NavigationRailDestination(icon: Icon(Icons.checklist_outlined), selectedIcon: Icon(Icons.checklist), label: Text('待办')),
    NavigationRailDestination(icon: Icon(Icons.edit_note_outlined), selectedIcon: Icon(Icons.edit_note), label: Text('杂记')),
    NavigationRailDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: Text('设置')),
  ];

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    // 必须监听状态：否则设置改完了界面不会重建（倒计时"设置后不生效"就是这里少了监听）
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Scaffold(
        body: Row(
          children: [
            NavigationRail(
              extended: MediaQuery.of(context).size.width > 1100,
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: MediaQuery.of(context).size.width > 1100 ? null : NavigationRailLabelType.all,
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Icon(Icons.timelapse, size: 28),
              ),
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: IconButton(
                      tooltip: '立即同步',
                      onPressed: s.busy ? null : () => s.syncNow(),
                      icon: s.busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.cloud_sync_outlined),
                    ),
                  ),
                ),
              ),
              destinations: _destinations,
            ),
            const VerticalDivider(width: 1),
            Expanded(child: IndexedStack(index: _index, children: _pages)),
          ],
        ),
      ),
    );
  }
}

/// 页面通用外壳：标题 + 右侧动作 + 内容
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.headlineSmall),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                ],
              ),
              const Spacer(),
              ...actions,
            ],
          ),
        ),
        const Divider(),
        Expanded(child: child),
      ],
    );
  }
}

/// 空状态提示
class EmptyHint extends StatelessWidget {
  const EmptyHint({super.key, required this.text, this.icon = Icons.inbox_outlined, this.action});

  final String text;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: scheme.outline),
          const SizedBox(height: Gaps.m),
          Text(text, style: TextStyle(color: scheme.onSurfaceVariant)),
          if (action != null) ...[const SizedBox(height: Gaps.m), action!],
        ],
      ),
    );
  }
}
