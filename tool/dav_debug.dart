/// 看一眼真实服务器返回的 PROPFIND 原始内容，确认路径解码对不对。
library;

import 'dart:io';

import 'package:life_task_manager/sync/webdav.dart';

Future<void> main(List<String> args) async {
  final client = WebdavClient(
    baseUrl: args.isNotEmpty ? args[0] : 'http://127.0.0.1:8099/',
    username: 'u',
    password: 'p',
    remoteRoot: args.length > 1 ? args[1] : '/ltm',
  );

  await client.ensureRoot();
  await client.put('杂记/202609/日记/2026-09-28.md', '中文路径测试');
  print('请求数：${client.requestCount}');

  final entries = await client.list('杂记/202609/日记');
  print('list("杂记/202609/日记") 返回 ${entries.length} 条：');
  for (final e in entries) {
    print('   path="${e.path}" isDir=${e.isDir} size=${e.size} etag=${e.etag}');
  }

  final root = await client.list('');
  print('list("") 返回 ${root.length} 条：');
  for (final e in root) {
    print('   path="${e.path}" isDir=${e.isDir}');
  }
  client.close();
  exit(0);
}
