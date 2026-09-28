import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_task_manager/model/note.dart';
import 'package:life_task_manager/sync/sync_engine.dart';
import 'package:life_task_manager/vault/repository.dart';

import 'support/memory_webdav.dart';

void main() {
  late Directory tmp;
  late VaultRepository repo;
  late MemoryWebdav server;
  late SyncStateStore stateStore;
  late SyncEngine engine;

  final fixedClock = DateTime(2026, 9, 28, 20, 30, 0);

  Future<SyncReport> sync({bool dryRun = false}) => engine.sync(dryRun: dryRun);

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ltm_sync_');
    repo = VaultRepository('${tmp.path}/vault');
    await repo.ensureStructure();
    server = MemoryWebdav();
    stateStore = SyncStateStore('${tmp.path}/sync_state.json');
    engine = SyncEngine(
      repo: repo,
      backend: server,
      stateStore: stateStore,
      deviceName: '电脑A',
      remoteRoot: '/LifeTaskManager',
      clock: () => fixedClock,
    );
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<void> writeNote(String body, {DateTime? day}) async {
    await repo.saveNote(Note(
      id: 'n-1',
      type: NoteType.diary,
      date: day ?? DateTime(2026, 9, 28),
      body: body,
    ));
  }

  const rel = '杂记/202609/日记/2026-09-28.md';

  test('第一次同步：本机文件传到服务器', () async {
    await writeNote('今天第一版');
    final r = await sync();
    expect(r.errors, isEmpty);
    expect(r.uploaded, 1);
    expect(server.files.keys.any((k) => k == rel), isTrue);
    expect(server.files[rel], contains('今天第一版'));
  });

  test('第二次同步：什么都没变 → 全部跳过', () async {
    await writeNote('今天第一版');
    await sync();
    final r2 = await sync();
    expect(r2.uploaded, 0);
    expect(r2.downloaded, 0);
    expect(r2.unchanged, greaterThanOrEqualTo(1));
    expect(r2.summary, contains('已是最新'));
  });

  test('服务器新增文件 → 下载到本机', () async {
    server.remoteWrite('杂记/202609/日记/2026-09-27.md', '昨天在手机上写的');
    final r = await sync();
    expect(r.downloaded, 1);
    final local = await repo.readFileOrNull('杂记/202609/日记/2026-09-27.md');
    expect(local, contains('昨天在手机上写的'));
  });

  test('本机改了 → 上传（服务器不返回 ETag 时也不会反复重传）', () async {
    await writeNote('第一版');
    await sync();

    await writeNote('第二版');
    final r = await sync();
    expect(r.uploaded, 1);
    expect(server.files[rel], contains('第二版'));

    // 关键：第三次同步不该再传一次
    final r2 = await sync();
    expect(r2.uploaded, 0, reason: 'ETag 没记下来的话这里会一直重复上传');
  });

  test('服务器改了 → 下载覆盖本机（且不产生假冲突副本）', () async {
    await writeNote('第一版');
    await sync();

    server.remoteWrite(rel, '手机上改的版本');
    final r = await sync();
    expect(r.downloaded, 1);
    expect(r.conflicts, 0);
    expect(await repo.readFileOrNull(rel), contains('手机上改的版本'));
    expect(
      (await repo.scanFiles()).any((f) => f.relPath.contains('冲突')),
      isFalse,
      reason: '只有服务器改过时不该生成冲突副本',
    );
  });

  test('两边都改了 → 两份都留，绝不静默覆盖', () async {
    await writeNote('原始版本');
    await sync();

    await writeNote('电脑上改的');
    server.remoteWrite(rel, '手机上改的');

    final r = await sync();
    expect(r.conflicts, 1);
    expect(r.conflictPaths.length, 1);

    final conflictRel = r.conflictPaths.single;
    expect(conflictRel, contains('冲突-电脑A-2026-09-28-203000'));
    // 本机：原路径是电脑的版本，冲突副本是手机的版本
    expect(await repo.readFileOrNull(rel), contains('电脑上改的'));
    expect(await repo.readFileOrNull(conflictRel), contains('手机上改的'));
    // 服务器：两份都在
    expect(server.files[rel], contains('电脑上改的'));
    expect(server.files[conflictRel], contains('手机上改的'));

    // 再同步一次应该稳定，不该又冒出冲突
    final r2 = await sync();
    expect(r2.conflicts, 0);
  });

  test('两边改成一样的内容 → 不算冲突', () async {
    await writeNote('原始');
    await sync();
    await writeNote('一样的改动');
    server.remoteWrite(rel, await repo.readFileOrNull(rel) ?? '');
    final r = await sync();
    expect(r.conflicts, 0);
    expect(r.uploaded, 0);
    expect(r.downloaded, 0);
  });

  test('本机删除、服务器没动 → 服务器跟着删', () async {
    await writeNote('要删掉的');
    await sync();
    expect(server.files.containsKey(rel), isTrue);

    await repo.moveToTrash(rel, now: fixedClock);
    final r = await sync();
    expect(r.remoteDeleted, 1);
    expect(server.files.containsKey(rel), isFalse);
  });

  test('服务器删除、本机没动 → 本机进回收站（不真删）', () async {
    await writeNote('服务器要删的');
    await sync();

    server.remoteDelete(rel);
    final r = await sync();
    expect(r.localDeleted, 1);
    expect(await repo.readFileOrNull(rel), isNull);
    final inTrash = (await repo.scanFiles()).where((f) => f.relPath.contains('回收站'));
    // 回收站被 scanFiles 排除，直接查目录
    final trashDirs = Directory('${repo.rootPath}/回收站').listSync();
    expect(trashDirs, isNotEmpty, reason: '删掉的文件应该躺在回收站里');
    expect(inTrash.isEmpty, isTrue);
  });

  test('服务器删了但本机改过 → 保住本机改动（重新上传）', () async {
    await writeNote('第一版');
    await sync();

    await writeNote('第二版（本机改的）');
    server.remoteDelete(rel);
    final r = await sync();
    expect(r.uploaded, 1);
    expect(server.files[rel], contains('第二版（本机改的）'));
  });

  test('dryRun 只报告不动作', () async {
    await writeNote('新文件');
    final r = await sync(dryRun: true);
    expect(r.uploaded, 1);
    expect(server.files, isEmpty, reason: '预演不能真的上传');
    expect(r.summary, contains('预演'));
  });

  test('回收站里的东西不参与同步', () async {
    await repo.writeFile('回收站/2026-09-28_120000/旧.md', '旧内容');
    await writeNote('正常内容');
    final r = await sync();
    expect(r.uploaded, 1);
    expect(server.files.keys.any((k) => k.startsWith('回收站')), isFalse);
  });

  test('大任务文件也要同步（不是只有杂记）', () async {
    await repo.createTask(title: '草坪机器人毕设', now: DateTime(2026, 9, 28));
    final r = await sync();
    expect(r.uploaded, greaterThanOrEqualTo(1));
    expect(server.files.keys.any((k) => k.startsWith('大任务/')), isTrue);
  });

  test('同步状态会落盘，重启后仍然是「已是最新」', () async {
    await writeNote('内容');
    await sync();
    expect(await File(stateStore.path).exists(), isTrue);

    final engine2 = SyncEngine(
      repo: repo,
      backend: server,
      stateStore: SyncStateStore(stateStore.path),
      deviceName: '电脑A',
      remoteRoot: '/LifeTaskManager',
      clock: () => fixedClock,
    );
    final r = await engine2.sync();
    expect(r.uploaded, 0);
    expect(r.downloaded, 0);
  });

  test('服务器 PUT 不返回 ETag 时，会自己补问一次并记住', () async {
    server.returnEtagOnPut = false;
    await writeNote('内容');
    final r1 = await sync();
    expect(r1.uploaded, 1);
    final r2 = await sync();
    expect(r2.uploaded, 0, reason: '没有 ETag 时要靠补问拿回来，否则无限重传');
    expect(r2.unchanged, greaterThanOrEqualTo(1));
  });

  test('换成另一个同步根目录 → 重建基准但不动文件', () async {
    await writeNote('内容');
    await sync();
    final engine3 = SyncEngine(
      repo: repo,
      backend: server,
      stateStore: SyncStateStore(stateStore.path),
      deviceName: '电脑A',
      remoteRoot: '/另一个目录',
      clock: () => fixedClock,
    );
    final r = await engine3.sync();
    expect(r.errors, isEmpty);
    expect(await repo.readFileOrNull(rel), isNotNull);
    expect(server.files[rel], contains('内容'));
  });
}
