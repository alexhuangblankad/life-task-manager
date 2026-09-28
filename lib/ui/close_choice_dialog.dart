/// 第一次点关闭按钮时弹的那个选择框。
///
/// 为什么要问：关窗口到底是「收起来继续跑」还是「退出程序」，
/// 没有标准答案 —— 有人拿它当常驻提醒工具（微信那样），
/// 有人就想要关掉。与其替他猜，不如问一次，顺手记住。
library;

import 'package:flutter/material.dart';

import '../app_state.dart';
import 'tray.dart';

Future<void> showCloseChoiceDialog(
  BuildContext context, {
  required AppState state,
  required TrayController tray,
  required bool firstTime,
}) async {
  final remember = ValueNotifier<bool>(true);

  final choice = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(firstTime ? '关闭窗口时要怎么处理？' : '关闭窗口'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '缩到托盘：窗口收进右下角，倒计时和提醒继续跑，下次点托盘图标就能叫回来。\n'
                '直接退出：程序关掉，提醒和定时任务都不再触发。',
                style: TextStyle(height: 1.6),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: remember.value,
                onChanged: (v) => setState(() => remember.value = v ?? true),
                title: const Text('记住我的选择，以后不再问'),
              ),
              Text(
                '以后想改：设置 → 外观 → 关闭窗口时',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'quit'),
            child: const Text('直接退出'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'tray'),
            child: const Text('缩到托盘，后台继续跑'),
          ),
        ],
      ),
    ),
  );

  final picked = choice ?? 'tray';
  // 勾了「记住」才持久化选择；没勾就只对这一次生效，下次还问
  await state.setCloseAction(picked, remember: remember.value);
  await tray.applyCloseAction(picked);
}
