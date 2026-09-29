/// 单实例：保证同时只有一个进程在跑。
///
/// 要解决的问题：关窗口缩到托盘之后（进程还在），用户点桌面图标会**再开一个进程** ——
/// 内存里两份数据、两份托盘图标、还各自读写同一批文件。
///
/// 做法（不需要任何第三方包）：
///   1. 数据目录放一个 `app.lock`，启动时用**独占文件锁**去锁它。
///      锁在进程退出时（哪怕是被杀、崩了）由系统自动释放，所以不会留下"假死锁"。
///   2. 锁不到 = 已经有一个实例在跑 → 写一个 `show.flag` 当信号，然后自己退出。
///   3. 已经在跑的那个实例每秒查一次这个信号，见到就把窗口显示出来并聚焦。
library;

import 'dart:io';
import 'dart:io' show pid;

import 'package:path/path.dart' as p;

class SingleInstance {
  SingleInstance(this.dir);

  /// 数据目录（和设备配置放一起，不放 vault，免得跟着同步走）
  final String dir;

  RandomAccessFile? _held;

  String get _lockPath => p.join(dir, 'app.lock');
  String get _showFlagPath => p.join(dir, 'show.flag');

  /// true = 我是唯一实例；false = 已经有一个在跑（调用方应请求显示后退出）
  /// 写一行诊断日志：单实例有没有生效，看这个文件就够了
  Future<void> _log(String msg) async {
    try {
      await File(p.join(dir, 'single_instance.log')).writeAsString(
        '${DateTime.now().toIso8601String()}  pid=$pid  $msg\n',
        mode: FileMode.append,
      );
    } catch (_) {}
  }

  Future<bool> acquire() async {
    try {
      final f = File(_lockPath);
      await f.parent.create(recursive: true);
      final raf = await f.open(mode: FileMode.write);
      await raf.lock(FileLock.exclusive); // 已被占用会抛异常
      _held = raf;
      await _log('拿到锁，我是唯一实例');
      return true;
    } catch (e) {
      await _log('锁被占了（已有实例在跑）：$e');
      return false;
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

  void release() {
    try {
      _held?.closeSync();
    } catch (_) {}
    _held = null;
  }
}
