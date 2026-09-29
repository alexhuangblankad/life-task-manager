/// 挑一个文件夹（桌面端用）。
///
/// 为什么不用 file_selector / file_picker 这类包：
/// 它们的**安卓实现**会要求 Kotlin Gradle Plugin 2.3.0，而这个网络下
/// 从 Maven 拉那个 jar 一直 Read timed out —— 一失败 Gradle 就整轮重跑，
/// 安卓打包被拖到 5 分钟以上还编不出来。
/// 而「挑数据文件夹」本来就是桌面才有的功能（安卓的 vault 是应用私有目录，
/// 没有挑文件夹这回事），所以干脆不引这个依赖：Windows 直接用它自带的
/// 文件夹选择框（PowerShell 调一下，隐藏窗口，不闪黑框）。
library;

import 'dart:io';

/// 返回选中的文件夹路径；用户取消或不支持返回 null。
Future<String?> pickFolder() async {
  if (!Platform.isWindows) return null;
  try {
    final r = await Process.run('powershell', [
      '-NoProfile',
      '-WindowStyle', 'Hidden',
      '-Command',
      r'Add-Type -AssemblyName System.Windows.Forms;'
      r'$d = New-Object System.Windows.Forms.FolderBrowserDialog;'
      r'$d.Description = "选择存放数据的文件夹";'
      r'$d.ShowNewFolderButton = $true;'
      r'if ($d.ShowDialog() -eq "OK") { Write-Output $d.SelectedPath }',
    ]);
    final out = (r.stdout as String).trim();
    return out.isEmpty ? null : out;
  } catch (_) {
    return null; // 调不出来也不能让设置页崩
  }
}
