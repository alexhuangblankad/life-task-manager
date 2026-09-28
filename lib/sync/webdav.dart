/// 自己写的薄 WebDAV 客户端。
///
/// 为什么不用现成包：同步引擎需要精确拿到 ETag 并用 If-Match 做「带条件的写」，
/// 现成包（webdav_client 最后更新 2024 年）把这一层藏起来了。这里只用 http + xml，
/// 自己要什么就实现什么。
///
/// 坚果云实测注意点（写进代码里的硬约束）：
///  - 免费版 30 分钟最多 600 次请求 → 所以一次同步要尽量少发请求（按目录 PROPFIND 递归）
///  - 429 要退避重试，不能硬撞
///  - 中文文件名走 UTF-8 百分号编码
///  - 412 = 远端被别人改过，绝不能当成功
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

/// 服务器上的一个条目
class WebdavEntry {
  const WebdavEntry({
    required this.path,
    required this.isDir,
    this.size = 0,
    this.etag,
    this.modified,
  });

  /// 相对 remoteRoot 的路径（不含前导 /）
  final String path;
  final bool isDir;
  final int size;
  final String? etag;
  final DateTime? modified;
}

class WebdavException implements Exception {
  WebdavException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  bool get isPreconditionFailed => statusCode == 412;
  bool get isNotFound => statusCode == 404;
  bool get isRateLimited => statusCode == 429;

  @override
  String toString() => 'WebdavException($statusCode): $message';
}

/// 同步引擎只依赖这个接口，方便用内存假服务器做测试
abstract class WebdavBackend {
  Future<void> ensureDir(String path);

  /// 列目录（depth 1），不含自身
  Future<List<WebdavEntry>> list(String path);

  Future<String?> getString(String path);

  /// 返回服务器给的新 ETag（没有就 null）
  Future<String?> put(String path, String content, {String? ifMatch, bool createOnly = false});

  Future<void> delete(String path);

  Future<bool> exists(String path);
}

class WebdavClient implements WebdavBackend {
  WebdavClient({
    required this.baseUrl,
    required this.username,
    required this.password,
    this.remoteRoot = '/LifeTaskManager',
    http.Client? client,
    this.maxRetries = 3,
  }) : _client = client ?? http.Client();

  /// 例：https://dav.jianguoyun.com/dav/
  final String baseUrl;
  final String username;
  final String password;
  final String remoteRoot;
  final int maxRetries;
  final http.Client _client;

  /// 统计本次会话发了多少请求（对着坚果云的限流心里有数）
  int requestCount = 0;

  Map<String, String> get _authHeaders => {
        'Authorization': 'Basic ${base64Encode(utf8.encode('$username:$password'))}',
        'User-Agent': 'LifeTaskManager/0.1',
      };

  String get normalizedRoot {
    var r = remoteRoot.trim();
    if (r.isEmpty) r = '/';
    if (!r.startsWith('/')) r = '/$r';
    if (r.length > 1 && r.endsWith('/')) r = r.substring(0, r.length - 1);
    return r;
  }

  Uri _uri(String path) {
    final clean = path.replaceAll(RegExp(r'^/+'), '');
    final enc = clean
        .split('/')
        .where((s) => s.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');
    final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    final full = enc.isEmpty ? base : '$base$enc';
    return Uri.parse(full);
  }

  Uri _uriForDir(String path) {
    final u = _uri(path);
    final s = u.toString();
    return Uri.parse(s.endsWith('/') ? s : '$s/');
  }

  /// 把 remoteRoot 和相对路径拼起来
  String _remote(String relPath) {
    final clean = relPath.replaceAll(RegExp(r'^/+'), '');
    if (clean.isEmpty) return normalizedRoot;
    return '$normalizedRoot/$clean';
  }

  Future<http.StreamedResponse> _send(String method, Uri uri, {Map<String, String>? headers, String? body}) async {
    var lastError = '';
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      requestCount++;
      final req = http.Request(method, uri)
        ..headers.addAll(_authHeaders)
        ..followRedirects = false;
      if (headers != null) req.headers.addAll(headers);
      if (body != null) req.body = body;
      try {
        final resp = await _client.send(req).timeout(const Duration(seconds: 60));
        if (resp.statusCode == 429 || resp.statusCode == 503) {
          final wait = Duration(seconds: 2 * (attempt + 1) * (attempt + 1));
          await resp.stream.drain<void>();
          await Future<void>.delayed(wait);
          lastError = 'HTTP ${resp.statusCode}（限流），已等待 ${wait.inSeconds}s 重试';
          continue;
        }
        return resp;
      } on SocketException catch (e) {
        lastError = '网络不通：${e.message}';
        await Future<void>.delayed(Duration(seconds: 1 + attempt));
      } on HttpException catch (e) {
        lastError = 'HTTP 错误：${e.message}';
        await Future<void>.delayed(Duration(seconds: 1 + attempt));
      }
    }
    throw WebdavException('重试 $maxRetries 次仍失败：$lastError');
  }

  /// 把服务器返回的 href 转成「相对 remoteRoot 的路径」。
  ///
  /// 统一只做一件事：剥掉 remoteRoot 前缀 + 去掉首尾斜杠。
  /// 之前这里还拿它跟「请求路径」比对，两边基准不一样，结果目录自身没被过滤掉，
  /// 递归扫描时会自己套自己 → 死循环狂发请求（真服务器上才暴露出来）。
  String _decodeHref(String href) {
    var h = href;
    final uri = Uri.tryParse(h);
    if (uri != null && uri.path.isNotEmpty) h = uri.path;
    var decoded = Uri.decodeComponent(h);
    if (decoded.startsWith(normalizedRoot)) {
      decoded = decoded.substring(normalizedRoot.length);
    }
    return decoded.replaceAll(RegExp(r'^/+'), '').replaceAll(RegExp(r'/+$'), '');
  }

  @override
  Future<bool> exists(String path) async {
    final resp = await _send('PROPFIND', _uri(_remote(path)), headers: {'Depth': '0'});
    await resp.stream.drain<void>();
    if (resp.statusCode == 404 || resp.statusCode == 410) return false;
    return resp.statusCode == 207 || resp.statusCode == 200;
  }

  /// 确保 remoteRoot 本身存在
  Future<void> ensureRoot() async {
    if (await exists('')) return;
    final resp = await _send('MKCOL', _uriForDir(_remote('')));
    await resp.stream.drain<void>();
    if (resp.statusCode != 201 && resp.statusCode != 405 && resp.statusCode != 200) {
      throw WebdavException('创建根目录失败 $normalizedRoot', statusCode: resp.statusCode);
    }
  }

  /// 创建目录。注意：path 是**相对 remoteRoot** 的路径（如 `杂记/202609`），
  /// 全公开方法的路径约定都是「相对 remoteRoot」，内部才拼 _remote()。
  @override
  Future<void> ensureDir(String path) async {
    final rel = path.replaceAll(RegExp(r'^/+'), '').replaceAll(RegExp(r'/+$'), '');
    if (rel.isEmpty) {
      await ensureRoot();
      return;
    }
    await ensureRoot();
    final parts = rel.split('/').where((s) => s.isNotEmpty).toList();
    final acc = <String>[];
    for (final part in parts) {
      acc.add(part);
      final sub = acc.join('/');
      if (await exists(sub)) continue;
      final resp = await _send('MKCOL', _uriForDir(_remote(sub)));
      await resp.stream.drain<void>();
      // 201 = 建好了；405 = 已存在（并发时正常）
      if (resp.statusCode != 201 && resp.statusCode != 405 && resp.statusCode != 200) {
        throw WebdavException('创建目录失败 $sub', statusCode: resp.statusCode);
      }
    }
  }

  @override
  Future<List<WebdavEntry>> list(String path) async {
    final target = _remote(path);
    final selfRel = path.replaceAll(RegExp(r'^/+'), '').replaceAll(RegExp(r'/+$'), '');
    const body = '<?xml version="1.0" encoding="utf-8"?>'
        '<d:propfind xmlns:d="DAV:"><d:prop>'
        '<d:getetag/><d:getcontentlength/><d:getlastmodified/><d:resourcetype/>'
        '</d:prop></d:propfind>';
    final resp = await _send('PROPFIND', _uriForDir(target), headers: {
      'Depth': '1',
      'Content-Type': 'application/xml; charset=utf-8',
    }, body: body);
    final text = await resp.stream.bytesToString();

    if (resp.statusCode == 404 || resp.statusCode == 410) return const [];
    if (resp.statusCode != 207 && resp.statusCode != 200) {
      throw WebdavException('列目录失败 $target', statusCode: resp.statusCode);
    }

    final out = <WebdavEntry>[];
    XmlDocument doc;
    try {
      doc = XmlDocument.parse(text);
    } catch (_) {
      throw WebdavException('服务器返回的不是合法 XML（$target）');
    }

    for (final node in doc.descendants.whereType<XmlElement>()) {
      if (node.name.local != 'response') continue;
      String? href;
      String? etag;
      String? modified;
      var size = 0;
      var isDir = false;
      for (final child in node.descendants.whereType<XmlElement>()) {
        switch (child.name.local) {
          case 'href':
            href ??= child.innerText.trim();
          case 'getetag':
            etag ??= child.innerText.trim();
          case 'getlastmodified':
            modified ??= child.innerText.trim();
          case 'getcontentlength':
            size = int.tryParse(child.innerText.trim()) ?? size;
          case 'collection':
            isDir = true;
        }
      }
      if (href == null || href.isEmpty) continue;
      final rel = _decodeHref(href);
      // 目录自身（有些服务器会把被请求的目录也放进结果里）
      if (rel.isEmpty || rel == selfRel) continue;
      out.add(WebdavEntry(
        path: rel,
        isDir: isDir,
        size: size,
        etag: etag,
        modified: modified == null ? null : HttpDate.parse(modified),
      ));
    }
    return out;
  }

  @override
  Future<String?> getString(String path) async {
    final resp = await _send('GET', _uri(_remote(path)));
    final bytes = await resp.stream.toBytes();
    if (resp.statusCode == 404) return null;
    if (resp.statusCode != 200) {
      throw WebdavException('下载失败 $path', statusCode: resp.statusCode);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  @override
  Future<String?> put(String path, String content, {String? ifMatch, bool createOnly = false}) async {
    final rel = path.replaceAll(RegExp(r'^/+'), '');
    final slash = rel.lastIndexOf('/');
    if (slash > 0) {
      await ensureDir(rel.substring(0, slash));
    } else {
      await ensureRoot();
    }
    final target = _remote(rel);
    final headers = <String, String>{
      'Content-Type': 'text/markdown; charset=utf-8',
      if (ifMatch != null) 'If-Match': ifMatch,
      if (createOnly) 'If-None-Match': '*',
    };
    final resp = await _send('PUT', _uri(target), headers: headers, body: content);
    await resp.stream.drain<void>();
    if (resp.statusCode == 412) {
      throw WebdavException('远端已被别人改过（If-Match 不匹配）', statusCode: 412);
    }
    if (resp.statusCode != 200 && resp.statusCode != 201 && resp.statusCode != 204) {
      throw WebdavException('上传失败 $target', statusCode: resp.statusCode);
    }
    return resp.headers['etag'];
  }

  @override
  Future<void> delete(String path) async {
    final resp = await _send('DELETE', _uri(_remote(path)));
    await resp.stream.drain<void>();
    if (resp.statusCode == 404) return;
    if (resp.statusCode != 200 && resp.statusCode != 204) {
      throw WebdavException('删除失败 $path', statusCode: resp.statusCode);
    }
  }

  /// 重命名/移动（暂未在同步里用，留给「远程整理」功能）
  Future<void> move(String from, String to) async {
    final resp = await _send('MOVE', _uri(_remote(from)), headers: {
      'Destination': _uri(_remote(to)).toString(),
      'Overwrite': 'T',
    });
    await resp.stream.drain<void>();
    if (resp.statusCode != 201 && resp.statusCode != 204) {
      throw WebdavException('移动失败 $from → $to', statusCode: resp.statusCode);
    }
  }

  /// 连通性自检（设置页「测试连接」用）
  Future<String> testConnection() async {
    final before = requestCount;
    await ensureRoot();
    final entries = await list('');
    return '连接正常，$normalizedRoot 下已有 ${entries.length} 个条目（用了 ${requestCount - before} 次请求）';
  }

  void close() => _client.close();
}
