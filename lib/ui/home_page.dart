import 'package:flutter/material.dart';

import '../app_state.dart';
import 'calendar_page.dart';
import 'countdown_page.dart';
import 'notes_page.dart';
import 'reminder_panel.dart';
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
  /// 当前显示哪一页（存的是「页面 id」不是下标 —— 用户调顺序后下标会变，
  /// 存下标会导致调完顺序界面跳到别的页去）
  String _page = 'countdown';

  /// 页面定义。显示顺序由用户在设置里调（见 AppState.navOrder）
  static const _destinations = <String, NavigationRailDestination>{
    'countdown': NavigationRailDestination(icon: Icon(Icons.hourglass_bottom_outlined), selectedIcon: Icon(Icons.hourglass_bottom), label: Text('倒计时')),
    'calendar': NavigationRailDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: Text('日历')),
    'tasks': NavigationRailDestination(icon: Icon(Icons.checklist_outlined), selectedIcon: Icon(Icons.checklist), label: Text('待办')),
    'notes': NavigationRailDestination(icon: Icon(Icons.edit_note_outlined), selectedIcon: Icon(Icons.edit_note), label: Text('杂记')),
    'settings': NavigationRailDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: Text('设置')),
  };

  /// 页面实例固定按这个顺序放进 IndexedStack：
  /// IndexedStack 靠「类型 + 位置」复用 State，顺序跟着用户走的话，
  /// 改完顺序 Flutter 会把 A 页的 State 塞给 B 页（就是之前那个勾选不刷新的坑）。
  static const _canonical = ['countdown', 'calendar', 'tasks', 'notes', 'settings'];

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    // 必须监听状态，而且**每次都要新建页面实例**：
    // 如果把页面实例缓存在 initState 里，重建时传回去的是同一个 widget 对象，
    // Flutter 认为"widget 没变"就跳过子树的 rebuild —— 于是数据变了界面纹丝不动
    // （勾选后勾不显示、设置改完界面不变，都是这个原因）。
    // State 会按 widget 类型+位置复用，所以日历选中的日期、输入框里的字都不会丢。
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final order = s.navOrder.isEmpty ? _canonical : s.navOrder;
        final selected = order.indexOf(_page) < 0 ? 0 : order.indexOf(_page);
        final current = order[selected];
        return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              extended: MediaQuery.of(context).size.width > 1100,
              selectedIndex: selected,
              onDestinationSelected: (i) => setState(() => _page = order[i]),
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 小铃铛：今天要提醒的事（倒计时 / 到期待办 / 定时任务）
                        Badge(
                          isLabelVisible: s.todayReminderCount > 0,
                          label: Text('${s.todayReminderCount}'),
                          child: IconButton(
                            tooltip: '提醒',
                            onPressed: () => showReminderPanel(context, s),
                            icon: const Icon(Icons.notifications_outlined),
                          ),
                        ),
                        IconButton(
                          tooltip: '立即同步',
                          onPressed: s.busy ? null : () => s.syncNow(),
                          icon: s.busy
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.cloud_sync_outlined),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              destinations: [for (final id in order) _destinations[id]!],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: IndexedStack(
                index: _canonical.indexOf(current),
                children: [
                  CountdownPage(state: s),
                  CalendarPage(state: s),
                  TasksPage(state: s),
                  NotesPage(state: s),
                  SettingsPage(state: s),
                ],
              ),
            ),
          ],
        ),
        );
      },
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
