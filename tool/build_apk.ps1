# 出 Android APK。
#
# 为什么不能直接在本目录 build：
#   Gradle 会因为「路径里有非 ASCII 字符」直接拒绝构建（中文路径），
#   报 "Your project path contains non-ASCII characters"。
#   跟 Windows release 那个 AOT 的中文路径问题是两码事，但解法一样：
#   复制到纯 ASCII 路径编译，再把 APK 拷回来。
#
# 用法：powershell -ExecutionPolicy Bypass -File tool\build_apk.ps1
# （本文件必须存成 UTF-8 带 BOM）

$ErrorActionPreference = 'Stop'

$src     = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$tmp     = 'E:\ltm_apk_build'  # 注意：别用之前那个目录名
                               # 如果有进程的当前目录停在里面，Windows 会锁住整个目录删不掉
$flutter = 'D:\flutter\bin\flutter.bat'
$outDir  = Join-Path $src 'dist_installer'

Write-Host "项目目录 : $src"
Write-Host "编译目录 : $tmp"

if (-not (Test-Path $flutter)) { throw "找不到 flutter: $flutter" }

Write-Host ""
Write-Host "[1/4] 复制源码到 ASCII 目录..."
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
robocopy $src $tmp /E /XD build .dart_tool .idea .git .vscode dist dist_installer ephemeral /XF *.log /NFL /NDL /NJH /NJS /NP | Out-Null

Write-Host "[2/4] 编译 release APK（第一次会比较慢）..."
Push-Location $tmp
# 按 CPU 架构分三个包（胖包 74MB，拆开每个约 25-30MB，用户按手机下对应的就行）
& $flutter build apk --release --split-per-abi
$code = $LASTEXITCODE
Pop-Location
if ($code -ne 0) { throw "APK 编译失败，退出码 $code" }

$map = @{
  'app-arm64-v8a-release.apk'   = 'LifeTaskManager-1.1.3-arm64-v8a.apk'
  'app-armeabi-v7a-release.apk' = 'LifeTaskManager-1.1.3-armeabi-v7a.apk'
  'app-x86_64-release.apk'      = 'LifeTaskManager-1.1.3-x86_64.apk'
}
$apkDir = Join-Path $tmp 'build\app\outputs\flutter-apk'
# --split-per-abi 出的是三个 app-<abi>-release.apk，没有 app-release.apk 这个胖包，
# 所以不能去 Test-Path 胖包（以前这里会直接抛「没找到 APK」让整轮打包白跑）
foreach ($k in $map.Keys) {
  $srcApk = Join-Path $apkDir $k
  if (Test-Path $srcApk) {
    $dst = Join-Path $outDir $map[$k]
    Copy-Item $srcApk $dst -Force
    $mb = [math]::Round((Get-Item $dst).Length / 1MB, 1)
    Write-Host "      $($map[$k])  ($mb MB)"
  }
}
Write-Host "[4/4] 完成，三个架构包都在 $outDir"
Write-Host ""
Write-Host "传到手机上：数据线拷过去点安装，或者 adb install -r 这个文件。"
Write-Host "首次安装需要在手机设置里允许「安装未知来源应用」。"
