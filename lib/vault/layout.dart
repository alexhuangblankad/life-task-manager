/// vault 的目录约定 —— 全部是纯函数，方便单测。
///
///     <vault>/config/profile.json        人生期限配置
///     <vault>/大任务/<标题>.md            一个大任务一个文件
///     <vault>/日程/202609.json            当月日程
///     <vault>/杂记/202609/日记/2026-09-28.md
///     <vault>/杂记/202609/任务/2026-09-28_草坪机器人毕设.md
///     <vault>/杂记/202609/任务/2026-09-28_草坪机器人毕设-2.md   同一天同一任务的第二条
///     <vault>/附件/202609/xxx.png         杂记里插的图
///     <vault>/月报/202609-月报.md
///     <vault>/回收站/<时间戳>/...         删掉的东西先扔这儿
library;

class VaultLayout {
  static const String configDir = 'config';
  static const String taskDir = '大任务';
  static const String noteDir = '杂记';
  static const String eventDir = '日程';
  /// 周报、月报、季报都放这个文件夹
  static const String reportDir = '报告';
  static const String trashDir = '回收站';

  /// 杂记里插的图片（拖进来的图片复制到这里，杂记用相对路径引用）
  static const String attachmentDir = '附件';

  static const String profilePath = '$configDir/profile.json';

  /// 重复任务的「哪天做过」记录（按月记日期，用于日历上打勾）
  static const String repeatDonePath = '$configDir/repeat_done.json';

  /// 2026 年 9 月 → `202609`
  static String monthFolder(DateTime d) => '${d.year}${two(d.month)}';

  static String diaryDir(DateTime d) => '$noteDir/${monthFolder(d)}/日记';

  static String taskNoteDir(DateTime d) => '$noteDir/${monthFolder(d)}/任务';

  static String diaryPath(DateTime d) => '${diaryDir(d)}/${isoDate(d)}.md';

  /// 任务杂记路径：**一条杂记一个文件**。
  ///
  /// [seq] 是「同一天、同一个任务下的第几条」：1 → `2026-09-30_任务.md`，
  /// 2 → `2026-09-30_任务-2.md`，依次往后。
  ///
  /// 以前只有「日期_任务名」这一段，同一天在同一个大任务下写第二条杂记
  /// 就会落到同一个路径上，把前一条**直接覆盖掉**（用户报的「同大任务下
  /// 的小任务杂记互相盖掉」就是这个）。现在由 repository 负责找空位。
  static String taskNotePath(DateTime d, String slug, {int seq = 1}) {
    final base = '${isoDate(d)}_${sanitize(slug)}';
    return '${taskNoteDir(d)}/${seq <= 1 ? base : '$base-$seq'}.md';
  }

  /// 附件路径：附件/202609/图片名.png（按月分文件夹，和杂记的月份对齐）
  static String attachmentPath(DateTime d, String fileName) =>
      '$attachmentDir/${monthFolder(d)}/${sanitize(fileName, maxLength: 80)}';

  /// 报告文件路径：报告/2026-09-周报.md
  static String reportPath(String label, String suffix) => '$reportDir/$label-$suffix.md';

  static String eventMonthPath(DateTime d) => '$eventDir/${monthFolder(d)}.json';

  static String taskPath(DateTime created, String title) =>
      '$taskDir/${isoDate(created)}_${sanitize(title)}.md';

  static String trashPath(String relPath, DateTime now) {
    final stamp = '${isoDate(now)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
    return '$trashDir/$stamp/$relPath';
  }

  /// 目录结构（启动时确保存在）
  static List<String> baseDirectories() => const [
        configDir,
        taskDir,
        noteDir,
        eventDir,
        reportDir,
        attachmentDir,
        trashDir,
      ];

  static String isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';

  static String two(int n) => n.toString().padLeft(2, '0');

  /// 文件名清洗：去掉 Windows/Unix 非法字符，防止任务标题里带 `/` `:` 等把目录搞乱。
  static String sanitize(String name, {int maxLength = 60}) {
    var s = name
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'[. ]+$'), ''); // Windows 不允许结尾是点或空格
    if (s.isEmpty) s = '未命名';
    if (s.length > maxLength) s = s.substring(0, maxLength).trim();
    return s;
  }

  /// 判断路径是否属于回收站（同步时要忽略）
  static bool isTrash(String relPath) =>
      relPath == trashDir || relPath.startsWith('$trashDir/');

  /// 判断是否是同步时要忽略的临时/系统文件
  static bool isIgnored(String relPath) {
    if (isTrash(relPath)) return true;
    final name = relPath.split('/').last;
    if (name.startsWith('.')) return true;
    if (name.endsWith('.tmp') || name.endsWith('.swp') || name.endsWith('~')) return true;
    return false;
  }

  /// 冲突副本路径：同目录下加 `.冲突-设备-时间戳` 后缀。
  /// 注意：冲突副本**要参与同步**，否则用户在其他设备上看不到它。
  static String conflictPath(String relPath, String deviceName, DateTime now) {
    final stamp = '${isoDate(now)}-${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final safeDevice = sanitize(deviceName, maxLength: 20).replaceAll(' ', '-');
    final slash = relPath.lastIndexOf('/');
    final dir = slash < 0 ? '' : relPath.substring(0, slash + 1);
    final name = slash < 0 ? relPath : relPath.substring(slash + 1);
    final dot = name.lastIndexOf('.');
    final base = dot <= 0 ? name : name.substring(0, dot);
    final ext = dot <= 0 ? '' : name.substring(dot);
    return '$dir$base.冲突-$safeDevice-$stamp$ext';
  }
}
