/// 内存版 WebDAV 服务器 —— 专门给同步引擎做测试用。
///
/// 它不碰网络，但完整实现了「带条件的写」和 ETag 语义，
/// 所以三态同步的每种情况都能在这里被真实地跑出来（包括并发冲突）。
library;

import 'dart:convert';

import 'package:life_task_manager/sync/sync_engine.dart' show sha1Of;
import 'package:life_task_manager/sync/webdav.dart';

class MemoryWebdav implements WebdavBackend {
  final Map<String, String> files = {};
  final Map<String, String> etags = {};
  final Set<String> dirs = {};

  /// 模拟服务器 PUT 不返回 ETag 的老实服务器
  bool returnEtagOnPut = true;

  /// 记录每种方法被调了几次（用来断言「没有多余请求」）
  final Map<String, int> calls = {};

  void _count(String method) => calls[method] = (calls[method] ?? 0) + 1;

  int get totalCalls => calls.values.fold(0, (a, b) => a + b);

  /// 模拟「另一台设备」直接改服务器上的文件
  void remoteWrite(String path, String content) {
    files[path] = content;
    etags[path] = _etagOf(content);
  }

  void remoteDelete(String path) {
    files.remove(path);
    etags.remove(path);
  }

  String _etagOf(String content) => '"${sha1Of(utf8.encode(content)).substring(0, 12)}"';

  @override
  Future<void> ensureDir(String path) async {
    _count('MKCOL');
    var cur = '';
    for (final part in path.split('/').where((s) => s.isNotEmpty)) {
      cur = cur.isEmpty ? part : '$cur/$part';
      dirs.add(cur);
    }
  }

  @override
  Future<bool> exists(String path) async {
    _count('PROPFIND');
    if (files.containsKey(path) || dirs.contains(path)) return true;
    return files.keys.any((k) => k.startsWith('$path/'));
  }

  @override
  Future<List<WebdavEntry>> list(String path) async {
    _count('PROPFIND');
    final prefix = path.isEmpty ? '' : '$path/';
    final out = <WebdavEntry>[];
    final seenDirs = <String>{};
    for (final entry in files.entries) {
      final f = entry.key;
      if (!f.startsWith(prefix)) continue;
      final rest = f.substring(prefix.length);
      final slash = rest.indexOf('/');
      if (slash < 0) {
        out.add(WebdavEntry(
          path: f,
          isDir: false,
          size: utf8.encode(entry.value).length,
          etag: etags[f],
        ));
      } else {
        final d = '$prefix${rest.substring(0, slash)}';
        if (seenDirs.add(d)) out.add(WebdavEntry(path: d, isDir: true));
      }
    }
    for (final d in dirs) {
      if (!d.startsWith(prefix)) continue;
      final rest = d.substring(prefix.length);
      if (rest.isEmpty || rest.contains('/')) continue;
      if (seenDirs.add(d)) out.add(WebdavEntry(path: d, isDir: true));
    }
    return out;
  }

  @override
  Future<String?> getString(String path) async {
    _count('GET');
    return files[path];
  }

  @override
  Future<String?> put(String path, String content, {String? ifMatch, bool createOnly = false}) async {
    _count('PUT');
    if (createOnly && files.containsKey(path)) {
      throw WebdavException('已存在', statusCode: 412);
    }
    if (ifMatch != null && etags[path] != ifMatch) {
      throw WebdavException('If-Match 不匹配', statusCode: 412);
    }
    files[path] = content;
    etags[path] = _etagOf(content);
    return returnEtagOnPut ? etags[path] : null;
  }

  @override
  Future<void> delete(String path) async {
    _count('DELETE');
    files.remove(path);
    etags.remove(path);
    dirs.removeWhere((d) => d == path || d.startsWith('$path/'));
  }
}
