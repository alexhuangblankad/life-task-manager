/// 同步引擎：本地 vault ⇄ WebDAV（坚果云）。
///
/// 核心是**三态比较**，不是「谁新谁赢」：
///   base   = 上次同步成功时的状态（记在本地 sync_state.json）
///   local  = 现在本机文件
///   remote = 现在服务器上的文件
///
/// 规则：
///   - 只有本机改过 → 上传
///   - 只有服务器改过 → 下载
///   - 两边都改过 → **两边都留**：本机版本留在原路径，服务器版本另存为 `xxx.冲突-设备-时间.md`，
///     两个文件都传上去。绝不静默覆盖（数据丢失只有两种来源：误删和冲突）。
///   - 一边删了、另一边没改 → 跟着删（本机删 = 进回收站，服务器删 = DELETE）
///   - 一边删了、另一边改了 → 保住改过的那份
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../vault/layout.dart';
import '../vault/repository.dart';
import 'webdav.dart';

/// 上次同步记录中的一个文件
class SyncedFile {
  const SyncedFile({required this.sha1, this.etag, this.syncedAt});
  final String sha1;
  final String? etag;
  final DateTime? syncedAt;

  Map<String, dynamic> toJson() => {
        'sha1': sha1,
        if (etag != null) 'etag': etag,
        if (syncedAt != null) 'synced_at': syncedAt!.toIso8601String(),
      };

  static SyncedFile fromJson(Map<String, dynamic> j) => SyncedFile(
        sha1: (j['sha1'] ?? '').toString(),
        etag: j['etag']?.toString(),
        syncedAt: DateTime.tryParse((j['synced_at'] ?? '').toString()),
      );
}

class SyncState {
  SyncState({this.remoteRoot = '', Map<String, SyncedFile>? files}) : files = files ?? {};

  String remoteRoot;
  Map<String, SyncedFile> files;

  Map<String, dynamic> toJson() => {
        'version': 1,
        'remote_root': remoteRoot,
        'files': files.map((k, v) => MapEntry(k, v.toJson())),
      };

  static SyncState fromJson(Map<String, dynamic> j) => SyncState(
        remoteRoot: (j['remote_root'] ?? '').toString(),
        files: ((j['files'] as Map?) ?? const {}).map(
          (k, v) => MapEntry(k.toString(), SyncedFile.fromJson((v as Map).cast<String, dynamic>())),
        ),
      );
}

class SyncStateStore {
  SyncStateStore(this.path);
  final String path;

  Future<SyncState> load() async {
    final f = File(path);
    if (!await f.exists()) return SyncState();
    try {
      final j = jsonDecode(await f.readAsString());
      if (j is Map) return SyncState.fromJson(j.cast<String, dynamic>());
    } catch (_) {}
    return SyncState();
  }

  Future<void> save(SyncState state) async {
    final f = File(path);
    await f.parent.create(recursive: true);
    await f.writeAsString(const JsonEncoder.withIndent(' ').convert(state.toJson()));
  }
}

class SyncReport {
  SyncReport({this.dryRun = false});

  final bool dryRun;
  int uploaded = 0;
  int downloaded = 0;
  int conflicts = 0;
  int remoteDeleted = 0;
  int localDeleted = 0;
  int unchanged = 0;
  int requests = 0;
  final List<String> conflictPaths = [];
  final List<String> errors = [];

  bool get hasChanges => uploaded + downloaded + conflicts + remoteDeleted + localDeleted > 0;

  String get summary {
    if (errors.isNotEmpty) {
      return '同步出错 ${errors.length} 处：${errors.first}';
    }
    if (!hasChanges) return '已是最新（${unchanged} 个文件，未发生变化）';
    final parts = <String>[];
    if (uploaded > 0) parts.add('上传 $uploaded');
    if (downloaded > 0) parts.add('下载 $downloaded');
    if (conflicts > 0) parts.add('冲突 $conflicts');
    if (remoteDeleted > 0) parts.add('删除服务器 $remoteDeleted');
    if (localDeleted > 0) parts.add('删除本地 $localDeleted');
    return '${dryRun ? "预演：" : ""}${parts.join("，")}（其余 $unchanged 个未变）';
  }
}

class SyncEngine {
  SyncEngine({
    required this.repo,
    required this.backend,
    required this.stateStore,
    required this.deviceName,
    required this.remoteRoot,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final VaultRepository repo;
  final WebdavBackend backend;
  final SyncStateStore stateStore;
  final String deviceName;
  final String remoteRoot;
  final DateTime Function() _clock;

  Future<SyncReport> sync({bool dryRun = false, void Function(String message)? onLog}) async {
    final report = SyncReport(dryRun: dryRun);
    final state = await stateStore.load();
    final rootKey = remoteRoot.replaceAll(RegExp(r'^/+'), '').replaceAll(RegExp(r'/+$'), '');

    if (state.remoteRoot != rootKey) {
      if (state.files.isNotEmpty) onLog?.call('同步目标变成 $rootKey，重新建立基准');
      state.files = {};
      state.remoteRoot = rootKey;
    }

    // base 是唯一的工作副本，所有改动都写它，最后整体存回
    final base = Map<String, SyncedFile>.from(state.files);
    final local = await _localManifest();
    final remote = await _remoteManifest(onLog);

    final paths = <String>{...local.keys, ...remote.keys, ...base.keys}.toList()..sort();

    for (final path in paths) {
      if (VaultLayout.isIgnored(path)) continue;
      final localEntry = local[path];
      final remoteEntry = remote[path];
      final baseEntry = base[path];

      final localExists = localEntry != null;
      final remoteExists = remoteEntry != null;
      final baseExists = baseEntry != null;

      final localDirty = localExists && (!baseExists || baseEntry.sha1 != localEntry.sha1);
      final remoteDirty = remoteExists && (!baseExists || baseEntry.etag != remoteEntry.etag);

      try {
        // ── 两边都有 ──
        if (localExists && remoteExists) {
          if (!localDirty && !remoteDirty) {
            report.unchanged++;
            continue;
          }
          if (localDirty && !remoteDirty) {
            await _upload(path, localEntry, remoteEntry, report, dryRun, base);
            continue;
          }
          if (!localDirty && remoteDirty) {
            await _download(path, remoteEntry, report, dryRun, base);
            continue;
          }
          // 两边都动过：先看内容是不是恰好一样（同一次改动）
          final remoteText = await backend.getString(path);
          if (remoteText != null && sha1Of(utf8.encode(remoteText)) == localEntry.sha1) {
            report.unchanged++;
            base[path] = SyncedFile(sha1: localEntry.sha1, etag: remoteEntry.etag, syncedAt: _clock());
            continue;
          }
          await _makeConflict(path, remoteText, remoteEntry, report, dryRun, base);
          continue;
        }

        // ── 只有本地有 ──
        if (localExists && !remoteExists) {
          if (!baseExists || localDirty) {
            // 服务器上没有了：可能是别人删的，也可能是刚新建的。
            // 只要本机有内容就传上去 —— 宁可多一个文件，也不丢数据。
            await _upload(path, localEntry, null, report, dryRun, base);
          } else {
            // 本机没改过、服务器上被删了 → 跟着删（进回收站）
            if (!dryRun) await repo.moveToTrash(path);
            base.remove(path);
            report.localDeleted++;
            onLog?.call('本机删除（服务器已删）：$path');
          }
          continue;
        }

        // ── 只有服务器有 ──
        if (!localExists && remoteExists) {
          if (!baseExists || remoteDirty) {
            await _download(path, remoteEntry, report, dryRun, base);
          } else {
            // 服务器没改过、本机删了 → 服务器上跟着删
            if (!dryRun) await backend.delete(path);
            base.remove(path);
            report.remoteDeleted++;
            onLog?.call('服务器删除（本机已删）：$path');
          }
          continue;
        }

        // ── 两边都没有 ──
        if (baseExists) base.remove(path);
      } catch (e) {
        report.errors.add('$path：$e');
        onLog?.call('出错 $path：$e');
      }
    }

    if (!dryRun) {
      state.files = base;
      await stateStore.save(state);
    }
    if (backend is WebdavClient) report.requests = (backend as WebdavClient).requestCount;
    return report;
  }

  // ─────────────────────── 具体动作 ───────────────────────

  Future<void> _upload(
    String path,
    _LocalEntry entry,
    WebdavEntry? remoteEntry,
    SyncReport report,
    bool dryRun,
    Map<String, SyncedFile> base,
  ) async {
    if (!dryRun) {
      final content = await repo.readFileOrNull(path);
      if (content == null) return;
      var etag = await backend.put(path, content);

      // 上传后**回读校验**：PUT 返回的 ETag 不可信 ——
      // 服务端可能因为权限/配额/路径问题拒绝了写入，却照样回一个 ETag，
      // 我们就会把状态记成「已同步」。下次同步于是认为本地干净、云端更新 →
      // 把云端旧内容下载回来覆盖本地（用户踩过：本地新改的被旧备份盖掉，
      // 现象就是「只能下载、无法上传」）。
      // 校验失败就抛错：调用方不会更新同步状态，本地继续保持「脏」，
      // 下次同步会重试上传，而且绝不会反向覆盖。
      final back = await backend.getString(path);
      if (back == null || sha1Of(utf8.encode(back)) != entry.sha1) {
        throw StateError('上传后回读内容不一致（服务器没真的写入）：$path');
      }

      etag ??= remoteEntry?.etag ?? await _fetchRemoteEtag(path);
      base[path] = SyncedFile(sha1: entry.sha1, etag: etag, syncedAt: _clock());
    }
    report.uploaded++;
  }

  Future<void> _download(
    String path,
    WebdavEntry remoteEntry,
    SyncReport report,
    bool dryRun,
    Map<String, SyncedFile> base,
  ) async {
    if (!dryRun) {
      final text = await backend.getString(path);
      if (text == null) return;

      // 最后一道防线：**覆盖本地之前，再核一次本地文件是不是真的没改过**。
      // 调用方是依据「本机同步状态」判定本地干净的；万一那份状态不准
      // （比如上次上传其实没成功、状态却被记成已同步），就会把用户刚改的
      // 内容用云端旧备份盖掉 —— 用户踩过这个坑。
      // 这里只要发现本地内容和记录里的哈希对不上，就按**冲突**处理（两边都留），
      // 宁可多一个文件，也绝不让静默覆盖发生。
      final baseEntry = base[path];
      final localNow = await repo.readFileOrNull(path);
      if (localNow != null &&
          localNow != text &&
          (baseEntry == null || sha1Of(utf8.encode(localNow)) != baseEntry.sha1)) {
        await _makeConflict(path, text, remoteEntry, report, dryRun, base);
        return;
      }

      await repo.writeFile(path, text);
      base[path] = SyncedFile(sha1: sha1Of(utf8.encode(text)), etag: remoteEntry.etag, syncedAt: _clock());
    }
    report.downloaded++;
  }

  Future<void> _makeConflict(
    String path,
    String? remoteText,
    WebdavEntry remoteEntry,
    SyncReport report,
    bool dryRun,
    Map<String, SyncedFile> base,
  ) async {
    final conflictPath = VaultLayout.conflictPath(path, deviceName, _clock());
    if (!dryRun) {
      final remote = remoteText ?? await backend.getString(path) ?? '';
      // 服务器那份另存为冲突副本；本机那份留在原路径。两个文件都同步上去。
      await repo.writeFile(conflictPath, remote);
      var conflictEtag = await backend.put(conflictPath, remote);
      conflictEtag ??= await _fetchRemoteEtag(conflictPath);

      final localText = await repo.readFileOrNull(path) ?? '';
      var localEtag = await backend.put(path, localText);
      localEtag ??= await _fetchRemoteEtag(path);

      base[conflictPath] = SyncedFile(
        sha1: sha1Of(utf8.encode(remote)),
        etag: conflictEtag,
        syncedAt: _clock(),
      );
      base[path] = SyncedFile(sha1: sha1Of(utf8.encode(localText)), etag: localEtag, syncedAt: _clock());
    }
    report.conflicts++;
    report.conflictPaths.add(conflictPath);
  }

  Future<String?> _fetchRemoteEtag(String path) async {
    try {
      final entries = await backend.list(_parentOf(path));
      for (final e in entries) {
        if (e.path == path) return e.etag;
      }
    } catch (_) {}
    return null;
  }

  static String _parentOf(String path) {
    final i = path.lastIndexOf('/');
    return i < 0 ? '' : path.substring(0, i);
  }

  // ─────────────────────── 清单 ───────────────────────

  Future<Map<String, _LocalEntry>> _localManifest() async {
    final files = await repo.scanFiles();
    final out = <String, _LocalEntry>{};
    for (final f in files) {
      final bytes = await File(repo.abs(f.relPath)).readAsBytes();
      out[f.relPath] = _LocalEntry(sha1: sha1Of(bytes), size: f.size, modified: f.modified);
    }
    return out;
  }

  Future<Map<String, WebdavEntry>> _remoteManifest(void Function(String)? onLog) async {
    final out = <String, WebdavEntry>{};
    final queue = <String>[''];
    // 已访问过的目录集合：万一某个服务器返回的路径有环，也绝不会无限发请求
    // （坚果云免费版 30 分钟只有 600 次请求，死循环几秒钟就能烧光）
    final visited = <String>{''};
    var dirs = 0;
    while (queue.isNotEmpty) {
      final dir = queue.removeAt(0);
      final entries = await backend.list(dir);
      dirs++;
      // 坚果云：单次 PROPFIND 最多返回 750 个条目，超出会分页。
      // 我们按月分文件夹天然满足，但万一某个目录涨太大，这里要吱一声，别静默漏文件。
      if (entries.length >= 750) {
        onLog?.call('⚠️ 目录「${dir.isEmpty ? "/" : dir}」有 ${entries.length} 个条目，'
            '已达坚果云单次 750 条上限，可能有文件没被列出来');
      }
      for (final e in entries) {
        if (VaultLayout.isIgnored(e.path)) continue;
        if (e.isDir) {
          if (visited.add(e.path)) queue.add(e.path);
        } else {
          out[e.path] = e;
        }
      }
    }
    onLog?.call('扫描服务器：$dirs 个目录，${out.length} 个文件');
    return out;
  }
}

/// 内容哈希（同步判断用）
String sha1Of(List<int> bytes) => sha1.convert(bytes).toString();

class _LocalEntry {
  const _LocalEntry({required this.sha1, required this.size, required this.modified});
  final String sha1;
  final int size;
  final DateTime modified;
}
