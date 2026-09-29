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

  /// 已经打开过的页面。IndexedStack 会把 children 全部 build 一遍，
  /// 手机上等于一启动就渲染日历 42 格 + 杂记列表 + 设置页那一堆卡片 ——
  /// 又慢又卡。这里只建「访问过」的页面，没去过的先放空占位。
  final Set<String> _visited = {'countdown'};

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
        // 手机窄屏：左边那条导航栏会吃掉大半宽度（内容区只剩 280px 左右，
        // 卡片全被挤到溢出、拖动都卡），所以窄屏换成底部标签栏
        final narrow = MediaQuery.of(context).size.width < 700;
        return Scaffold(
        bottomNavigationBar: narrow
            ? NavigationBar(
                selectedIndex: selected,
                onDestinationSelected: (i) => _select(order[i]),
                destinations: [
                  for (final id in order)
                    NavigationDestination(
                      icon: _destinations[id]!.icon,
                      selectedIcon: _destinations[id]!.selectedIcon,
                      label: _labelOf(id),
                    ),
                ],
              )
            : null,
        body: Row(
          children: [
            if (!narrow)
              NavigationRail(
              extended: MediaQuery.of(context).size.width > 1100,
              selectedIndex: selected,
              onDestinationSelected: (i) => _select(order[i]),
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
                // 只建访问过的页面（IndexedStack 会把 children 全部 build，
                // 5 个页面一起渲染在手机上就是启动慢 + 卡）
                children: [
                  for (final id in _canonical)
                    _visited.contains(id) ? _buildPage(id, s) : const SizedBox.shrink(),
                ],
              ),
            ),
          ],
        ),
        );
      },
    );
  }

  void _select(String id) {
    setState(() {
      _page = id;
      _visited.add(id);
      if (id == 'calendar') {
        // 520KB 的历史数据等真打开日历时再解析，别挡启动
        widget.state.ensureHistory();
      }
    });
  }

  String _labelOf(String id) => switch (id) {
        'countdown' => '倒计时',
        'calendar' => '日历',
        'tasks' => '待办',
        'notes' => '杂记',
        _ => '设置',
      };

  Widget _buildPage(String id, AppState s) => switch (id) {
        'countdown' => CountdownPage(state: s),
        'tasks' => TasksPage(state: s),
        'notes' => NotesPage(state: s),
        'settings' => SettingsPage(state: s),
        _ => CalendarPage(state: s),
      };
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
        LayoutBuilder(
          builder: (context, c) {
            final titleWidget = Column(
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
            );

            // 窄屏（手机）：标题和按钮挤一行的话，右边的按钮会被屏幕边缘切掉
            // （模拟器实测：「新增日程」被裁了一半）。改成按钮换行放标题下面。
            if (c.maxWidth < 520) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleWidget,
                    if (actions.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      // Wrap 默认是顶部对齐 —— 48 高的图标按钮会跟小号文字错开，
                      // 看起来就是「月份和箭头不齐平」。居中对齐才对。
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: actions,
                      ),
                    ],
                  ],
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Row(
                children: [
                  titleWidget,
                  const Spacer(),
                  ...actions,
                ],
              ),
            );
          },
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
