/// 拿真的 WebDAV 服务器（本机 wsgidav）验一遍 HTTP 层和整条同步链路。
///
/// 用法：
///   dart run tool/webdav_check.dart http://127.0.0.1:8099/ user pass /ltm
library;

import 'dart:io';

import 'package:life_task_manager/core/ids.dart';
import 'package:life_task_manager/model/note.dart';
import 'package:life_task_manager/model/task.dart';
import 'package:life_task_manager/sync/sync_engine.dart';
import 'package:life_task_manager/sync/webdav.dart';
import 'package:life_task_manager/vault/repository.dart';

int _pass = 0;
int _fail = 0;

void check(String name, bool ok, [String extra = '']) {
  if (ok) {
    _pass++;
    print('  ✅ $name ${extra.isEmpty ? "" : "→ $extra"}');
  } else {
    _fail++;
    print('  ❌ $name ${extra.isEmpty ? "" : "→ $extra"}');
  }
}

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args[0] : 'http://127.0.0.1:8099/';
  final user = args.length > 1 ? args[1] : 'u';
  final pass = args.length > 2 ? args[2] : 'p';
  final root = args.length > 3 ? args[3] : '/ltm';

  print('=== 1. HTTP 层（真服务器） ===');
  final client = WebdavClient(baseUrl: url, username: user, password: pass, remoteRoot: root);
  print('  ${await client.testConnection()}');

  await client.put('a/b.md', '# 你好\n内容一\n');
  final listed = await client.list('a');
  final bEntry = listed.where((e) => e.path == 'a/b.md').toList();
  check('MKCOL + PUT + PROPFIND', bEntry.isNotEmpty, 'etag=${bEntry.isEmpty ? "-" : bEntry.first.etag}');
  check('下载内容正确', (await client.getString('a/b.md'))?.contains('内容一') ?? false);

  await client.put('杂记/202609/日记/2026-09-28.md', '中文路径测试');
  final cn = await client.list('杂记/202609/日记');
  check('中文/含空格路径', cn.any((e) => e.path == '杂记/202609/日记/2026-09-28.md'), cn.map((e) => e.path).join(','));
  check('中文内容正确', (await client.getString('杂记/202609/日记/2026-09-28.md'))?.contains('中文路径测试') ?? false);

  final etag = bEntry.isEmpty ? null : bEntry.first.etag;
  if (etag != null) {
    try {
      await client.put('a/b.md', '内容二\n', ifMatch: etag);
      check('If-Match 带正确 ETag 能写', true);
      try {
        // 用假的 ETag 硬写：服务器必须拒绝（412），否则说明"带条件的写"没生效，
        // 多设备同时改同一个文件就会静默覆盖
        await client.put('a/b.md', '拿旧 ETag 硬写', ifMatch: '"deadbeefdeadbeef"');
        check('412 冲突检测', false, '假 ETag 居然写成功了——远端覆盖会丢数据');
      } catch (e) {
        check('412 冲突检测', e is WebdavException && e.isPreconditionFailed, '$e');
      }
    } catch (e) {
      check('If-Match 带正确 ETag 能写', false, '$e');
    }
  }
  check('exists', await client.exists('a/b.md'));
  await client.delete('a/b.md');
  check('DELETE', !await client.exists('a/b.md'));

  print('\n=== 2. 两个 vault 通过服务器互相同步 ===');
  // 用一个独立的同步根，别和上面 HTTP 层测试留下的文件混在一起
  final syncRoot = '$root-同步测试';
  final client2 = WebdavClient(baseUrl: url, username: user, password: pass, remoteRoot: syncRoot);
  final tmp = await Directory.systemTemp.createTemp('ltm_dav_');
  final vaultA = VaultRepository('${tmp.path}/A');
  final vaultB = VaultRepository('${tmp.path}/B');
  await vaultA.ensureStructure();
  await vaultB.ensureStructure();

  // A 上建内容
  final created = await vaultA.createTask(title: '草坪机器人毕设', now: DateTime(2026, 9, 28));
  var raw = await vaultA.readFileOrNull(created.task.filePath) ?? created.raw;
  raw = appendSubtask(raw, SubTask(id: newSubtaskId(), title: '跑通仿真', due: DateTime(2026, 10, 1)));
  await vaultA.saveTaskFile(created.task.filePath, raw);
  await vaultA.saveNote(Note(id: newNoteId(), type: NoteType.diary, date: DateTime(2026, 9, 28), body: '今天在 A 上写的'));

  final engineA = SyncEngine(
    repo: vaultA,
    backend: client2,
    stateStore: SyncStateStore('${tmp.path}/stateA.json'),
    deviceName: '电脑A',
    remoteRoot: syncRoot,
  );
  final rA = await engineA.sync();
  check('A 上传', rA.errors.isEmpty && rA.uploaded >= 2 && rA.conflicts == 0, rA.summary);

  final engineB = SyncEngine(
    repo: vaultB,
    backend: client2,
    stateStore: SyncStateStore('${tmp.path}/stateB.json'),
    deviceName: '手机B',
    remoteRoot: syncRoot,
  );
  final rB = await engineB.sync();
  check('B 下载', rB.errors.isEmpty && rB.downloaded >= 2, rB.summary);
  final bDiary = await vaultB.readFileOrNull('杂记/202609/日记/2026-09-28.md');
  check('B 上能看到 A 写的内容', bDiary?.contains('今天在 A 上写的') ?? false);

  // 两边同时改同一天日记 → 必须产生冲突副本，两份都留
  await vaultA.writeFile('杂记/202609/日记/2026-09-28.md', (await vaultA.readFileOrNull('杂记/202609/日记/2026-09-28.md'))! + '\nA 又加了一句。');
  await vaultB.writeFile('杂记/202609/日记/2026-09-28.md', (await vaultB.readFileOrNull('杂记/202609/日记/2026-09-28.md'))! + '\nB 也加了一句。');

  final rA2 = await engineA.sync();
  final rB2 = await engineB.sync();
  final rA3 = await engineA.sync();
  check('冲突被检出', (rA2.conflicts + rB2.conflicts + rA3.conflicts) >= 1,
      'A:${rA2.conflicts} B:${rB2.conflicts} A:${rA3.conflicts}');

  final aFiles = (await vaultA.scanFiles()).map((f) => f.relPath).where((p) => p.contains('冲突')).toList();
  final bFiles = (await vaultB.scanFiles()).map((f) => f.relPath).where((p) => p.contains('冲突')).toList();
  check('两边都拿到了冲突副本', aFiles.isNotEmpty && bFiles.isNotEmpty, 'A:$aFiles B:$bFiles');

  final aDiary = await vaultA.readFileOrNull('杂记/202609/日记/2026-09-28.md') ?? '';
  final conflictBody = aFiles.isEmpty ? '' : (await vaultA.readFileOrNull(aFiles.first) ?? '');
  check('两份内容都还在（没丢数据）',
      (aDiary.contains('A 又加了一句') || aDiary.contains('B 也加了一句')) &&
          (conflictBody.contains('A 又加了一句') || conflictBody.contains('B 也加了一句')),
      '原本:${aDiary.contains("A 又加了一句") ? "A句" : ""}${aDiary.contains("B 也加了一句") ? "B句" : ""} 副本:${conflictBody.contains("A 又加了一句") ? "A句" : ""}${conflictBody.contains("B 也加了一句") ? "B句" : ""}');

  // 收敛：再同步一轮应该稳定
  final rA4 = await engineA.sync();
  final rB4 = await engineB.sync();
  check('冲突处理后会收敛（不再反复冲突）', rA4.conflicts == 0 && rB4.conflicts == 0,
      'A:${rA4.summary} | B:${rB4.summary}');

  print('\n=== 3. 限流统计 ===');
  print('  本次总共发出 ${client.requestCount + client2.requestCount} 次请求（坚果云免费版限额：30 分钟 600 次）');
  client.close();
  client2.close();
  try {
    await tmp.delete(recursive: true);
  } catch (_) {}

  print('\n结果：$_pass 项通过，$_fail 项失败');
  exit(_fail == 0 ? 0 : 1);
}
