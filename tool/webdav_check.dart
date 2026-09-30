/// 拿真的 WebDAV 服务器（本机 wsgidav）验一遍 HTTP 层和整条同步链路。
///
/// 用法：
///   dart run tool/webdav_check.dart http://127.0.0.1:8099/ user pass /ltm
library;

import 'dart:convert';
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

  print('\n=== 3. 「只能下载、无法上传」专项（本轮修复的根因） ===');
  // 用例 A：本地改一个文件 → 同步 → **直接去服务器把那个文件读出来**，
  // 看内容是不是真的更新了。只看本地「同步完成」的提示不算验证 ——
  // 当年那个 bug 恰恰在本地看起来一切正常。
  final ackRel = '杂记/202609/日记/2026-09-28.md';
  final beforeUpload = await client2.getString(ackRel) ?? '';
  await vaultA.writeFile(ackRel, '$beforeUpload\nA 在同步前又写了一句话。');
  final rUpload = await engineA.sync();
  final afterUpload = await client2.getString(ackRel) ?? '';
  final afterLocal = await vaultA.readFileOrNull(ackRel) ?? '';
  check('本地改动真的传上去了（读服务器确认，不信本地提示）',
      afterUpload.contains('A 在同步前又写了一句话。'), '本地与云端一致=${afterUpload == afterLocal}');
  check('两端内容逐字节相同',
      sha1Of(utf8.encode(afterUpload)) == sha1Of(utf8.encode(afterLocal)),
      '上传 ${rUpload.uploaded} 个 / 错误 ${rUpload.errors.length}');

  // 用例 B：**服务器说谎**。后端包一层：除了 PUT 之外都转发给真服务器，
  // PUT 一律回一个 ETag 但根本不落盘 —— 这就是用户踩过的场景
  //（服务端拒绝写入却回成功，我们把状态记成已同步，下次就把云端旧内容
  //  下载回来盖掉本地新内容）。
  final liarRoot = '$root-说谎测试';
  final truth = WebdavClient(baseUrl: url, username: user, password: pass, remoteRoot: liarRoot);
  final liar = _LyingBackend(truth);

  final tmp2 = await Directory.systemTemp.createTemp('ltm_dav_liar_');
  final vaultC = VaultRepository('${tmp2.path}/C');
  await vaultC.ensureStructure();
  const rel = '杂记/202609/日记/2026-09-28.md';
  await vaultC.writeFile(rel, '本地第一版\n');
  final engineC = SyncEngine(
    repo: vaultC,
    backend: liar,
    stateStore: SyncStateStore('${tmp2.path}/stateC.json'),
    deviceName: '电脑C',
    remoteRoot: liarRoot,
  );
  final rC1 = await engineC.sync();
  check('第一次同步（服务器说谎）：上传被识破', rC1.errors.isNotEmpty, rC1.summary);
  check('服务器上确实什么都没写进去', !await truth.exists(rel),
      '服务器上的内容=${await truth.getString(rel)}');

  // 服务器上备好一份内容，本地也放一模一样的一份（模拟「上次已经同步好的状态」），
  // 然后再把本地改成「新内容」：服务端照样嘴上答应、实际不写 →
  // 必须报错、绝不能反过来把本地覆盖掉。
  await truth.put(rel, '云端旧内容\n');
  await vaultC.writeFile(rel, '云端旧内容\n');
  final engineC2 = SyncEngine(
    repo: vaultC,
    backend: liar,
    stateStore: SyncStateStore('${tmp2.path}/stateC2.json'),
    deviceName: '电脑C',
    remoteRoot: liarRoot,
  );
  final rC2 = await engineC2.sync(); // 内容一致 → 记下基准状态
  check('先正常同步一次对齐状态', rC2.errors.isEmpty && rC2.conflicts == 0, rC2.summary);

  await vaultC.writeFile(rel, '用户刚改的新内容\n');
  final rC3 = await engineC2.sync();
  final localAfter = await vaultC.readFileOrNull(rel) ?? '';
  final remoteAfter = await truth.getString(rel) ?? '';
  check('说谎的服务器没让上传「假装成功」', rC3.errors.isNotEmpty, '服务器共说谎 ${liar.lies} 次 / ${rC3.summary}');
  check('本地新内容没被云端旧内容盖掉', localAfter.contains('用户刚改的新内容'), localAfter.trim());
  check('本地仍是「脏」的（回读校验拦住了）', rC3.errors.any((e) => e.contains('回读')), rC3.errors.join('；'));

  // 状态文件里绝不能出现「新内容的哈希」—— 一旦记成已同步，下次同步就会
  // 认为本地干净、云端更新，把旧内容下载回来覆盖。
  final stateRaw = await File('${tmp2.path}/stateC2.json').readAsString();
  check('同步状态里没有新内容的哈希（否则下次就会反向覆盖）',
      !stateRaw.contains(sha1Of(utf8.encode('用户刚改的新内容\n'))));

  // 再同步一次：还是重试上传、还是报错、本地还是那份新内容
  final rC4 = await engineC2.sync();
  final localAgain = await vaultC.readFileOrNull(rel) ?? '';
  check('下次同步仍然重试上传并报错（本地保持脏）',
      rC4.errors.isNotEmpty && localAgain.contains('用户刚改的新内容'), rC4.summary);

  // 演示（不是断言）：如果没有「上传后回读」这道防线，状态会被记成已同步，
  // 下一次同步就会把云端旧内容下载回来盖掉本地 —— 这就是用户当年看到的现象。
  final poisoned = SyncStateStore('${tmp2.path}/state_poisoned.json');
  await poisoned.save(SyncState(remoteRoot: liarRoot.replaceAll(RegExp(r'^/+'), ''), files: {
    rel: SyncedFile(sha1: sha1Of(utf8.encode(localAgain)), etag: '假装上传成功后的新 ETag'),
  }));
  final engineC3 = SyncEngine(
    repo: vaultC,
    backend: liar,
    stateStore: poisoned,
    deviceName: '电脑C',
    remoteRoot: liarRoot,
  );
  final rC5 = await engineC3.sync();
  final localPoisoned = await vaultC.readFileOrNull(rel) ?? '';
  print('  ⚠️ 演示：状态被污染时（旧版本的行为）→ ${rC5.summary}；'
      '本地现在的内容：${localPoisoned.trim()}');

  truth.close();
  try {
    await tmp2.delete(recursive: true);
  } catch (_) {}

  print('\n=== 4. 限流统计 ===');
  print('  本次总共发出 ${client.requestCount + client2.requestCount} 次请求（坚果云免费版限额：30 分钟 600 次）');
  client.close();
  client2.close();
  try {
    await tmp.delete(recursive: true);
  } catch (_) {}

  print('\n结果：$_pass 项通过，$_fail 项失败');
  exit(_fail == 0 ? 0 : 1);
}

/// 一个「说谎的」WebDAV 后端：除了 PUT 之外都原样转发给真服务器，
/// **PUT 只回一个 ETag，根本不写**。
///
/// 这就是用户踩过的坑（服务端因为权限/配额/路径拒绝写入，却回了个成功），
/// 用来验证「上传后回读校验」这道防线真的拦得住。
class _LyingBackend implements WebdavBackend {
  _LyingBackend(this.real);

  final WebdavClient real;
  int lies = 0;

  @override
  Future<void> ensureDir(String path) => real.ensureDir(path);

  @override
  Future<List<WebdavEntry>> list(String path) => real.list(path);

  @override
  Future<String?> getString(String path) => real.getString(path);

  @override
  Future<String?> put(String path, String content, {String? ifMatch, bool createOnly = false}) async {
    lies++;
    return '"说谎后端给的新 ETag"';
  }

  @override
  Future<void> delete(String path) => real.delete(path);

  @override
  Future<bool> exists(String path) => real.exists(path);
}
