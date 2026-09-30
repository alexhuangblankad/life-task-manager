/// 应用信息（版本号只在这一个地方写，关于页和后续更新检查都读它）
library;

const String kAppName = '人生任务管理器';
const String kAppVersion = '1.1.10';
const String kAppRepoUrl = 'https://github.com/alexhuangblankad/life-task-manager';
const String kAppTagline = '人生倒计时 · 日历 · 待办 · 杂记';
const String kAppLicense = 'MIT 开源许可';

/// 这一版改了什么（关于页直接列出来，省得用户去翻仓库）
const List<String> kAppChangelog = [
  '杂记：一条杂记一个文件（同一天、同一个大任务下写第二条不会再互相覆盖）',
  '杂记页和待办页同构：大任务分组 + 进度条，点小任务看它名下所有杂记',
  '杂记编辑器支持拖图片进来，自动存好并插进正文（桌面端）',
  '修：同步「只能下载、无法上传」—— 上传后回读校验，服务端没真写进去就报错重试',
  '（1.1.7）修暗色主题下顶部那条白带',
  '（1.1.6）点桌面图标不会再开新进程',
  '（1.1.5）界面铺满窗口，修好安卓顶部那条白带；刘海/挖孔屏适配',
  '（1.1.4）点桌面图标不再开新进程；手机新建任务按钮够得着',
  '（1.1.3）日历：数字对齐、圆点不压农历、长节日名不挤数字',
];
