/// 单实例：保证同时只有一个进程在跑。
///
/// 要解决的问题：关窗口缩到托盘之后（进程还在），用户点桌面图标会**再开一个进程** ——
/// 内存里两份数据、两个托盘图标、还各自读写同一批文件。
///
/// **实现方式（踩过坑，别再改回去）**：
/// 一开始想用「独占文件锁」（`RandomAccessFile.lock(FileLock.exclusive)`）来判断，
/// 实测**根本拦不住** —— 连开三个进程，三个都成功拿到锁：
///   - 空文件时锁的范围是空的，等于没锁；
///   - 补上 `lock(FileLock.exclusive, 0, 1)` 明确锁前 1 个字节后，还是三个都成功。
/// 所以改成**不依赖文件锁**的确定性做法：
///   1. `app.lock` 里记录当前实例的 pid；
///   2. 启动时读出来，用 `tasklist` 查那个 pid 的进程还在不在（且是不是自己这个程序）；
///   3. 还在 → 写 `show.flag` 请求显示窗口，然后自己退出；
///   4. 不在（崩过/正常退过）→ 把自己的 pid 写进去，正常启动。
library;

import 'dart:io';

import 'package:path/path.dart' as p;

class SingleInstance {
  SingleInstance(this.dir);

  /// 数据目录（和设备配置放一起，不放 vault，免得跟着同步走）
  final String dir;

  String get _lockPath => p.join(dir, 'app.lock');
  String get _showFlagPath => p.join(dir, 'show.flag');

  /// true = 我是唯一实例；false = 已经有一个在跑（调用方应请求显示后退出）
  Future<bool> acquire() async {
    try {
      final f = File(_lockPath);
      await f.parent.create(recursive: true);

      final old = await _readPid(f);
      if (old != null && old != pid && await _alive(old)) {
        await _log('发现已有实例在跑（pid=$old），我不启动');
        return false;
      }

      await f.writeAsString('$pid\n');
      await _log('没有其它实例，我接手（pid=$pid）');
      return true;
    } catch (e) {
      await _log('单实例检查出错，按唯一实例继续：$e');
      return true; // 检查出错时宁可多开一个，也别让用户打不开程序
    }
  }

  /// 请求已经在跑的那个实例把窗口显示出来
  Future<void> requestShow() async {
    try {
      await File(_showFlagPath).writeAsString('1');
      await _log('已写 show.flag，请已有实例把窗口显示出来');
    } catch (_) {
      // 连标记都写不下去就只能算了（至少不会开成第二个进程）
    }
  }

  /// 已经在跑的实例调用：有人点图标了吗？有就把标记吃掉
  Future<bool> consumeShowRequest() async {
    try {
      final f = File(_showFlagPath);
      if (await f.exists()) {
        await f.delete();
        await _log('收到显示请求，把窗口叫回来');
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<int?> _readPid(File f) async {
    if (!await f.exists()) return null;
    final t = (await f.readAsString()).trim();
    return int.tryParse(t.split(RegExp(r'\s+')).first);
  }

  /// 这个 pid 现在是不是还活着，而且它就是本程序（防止 pid 被系统复用）
  Future<bool> _alive(int target) async {
    if (Platform.isWindows) {
      try {
        final r = await Process.run('tasklist', [
          '/FI', 'PID eq $target',
          '/NH', '/FO', 'CSV',
        ]);
        final out = (r.stdout as String);
        return out.contains('life_task_manager') && out.contains('$target');
      } catch (_) {
        return false;
      }
    }
    // 其它平台（本功能主要给 Windows 用）用信号探测，探不到就当没有
    try {
      final r = await Process.run('ps', ['-p', '$target', '-o', 'comm=']);
      return (r.stdout as String).trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// 写一行诊断日志：单实例有没有生效，看这个文件就够了
  Future<void> _log(String msg) async {
    try {
      await File(p.join(dir, 'single_instance.log')).writeAsString(
        '${DateTime.now().toIso8601String()}  pid=$pid  $msg\n',
        mode: FileMode.append,
      );
    } catch (_) {}
  }
}
