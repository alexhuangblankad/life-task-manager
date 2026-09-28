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
$tmp     = 'E:\ltm_android_build'
$flutter = 'D:\flutter\bin\flutter.bat'
$outDir  = Join-Path $src 'dist_installer'

Write-Host "项目目录 : $src"
Write-Host "编译目录 : $tmp"

if (-not (Test-Path $flutter)) { throw "找不到 flutter: $flutter" }

Write-Host ""
Write-Host "[1/4] 复制源码到 ASCII 目录..."
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
robocopy $src $tmp /E /XD build .dart_tool .idea .git .vscode dist dist_installer ephemeral /XF *.log /NFL /NDL /NJH /NJS /NP | Out-Null

Write-Host "[2/4] 编译 release APK（第一次会比较慢）..."
Push-Location $tmp
& $flutter build apk --release
$code = $LASTEXITCODE
Pop-Location
if ($code -ne 0) { throw "APK 编译失败，退出码 $code" }

$built = Join-Path $tmp 'build\app\outputs\flutter-apk\app-release.apk'
if (-not (Test-Path $built)) { throw "没找到 APK：$built" }

Write-Host "[3/4] 复制 APK 到 dist_installer ..."
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$dst = Join-Path $outDir 'LifeTaskManager-1.0.3.apk'
Copy-Item $built $dst -Force

$mb = [math]::Round((Get-Item $dst).Length / 1MB, 1)
Write-Host "[4/4] 完成: $dst  ($mb MB)"
Write-Host ""
Write-Host "传到手机上：数据线拷过去点安装，或者 adb install -r 这个文件。"
Write-Host "首次安装需要在手机设置里允许「安装未知来源应用」。"
