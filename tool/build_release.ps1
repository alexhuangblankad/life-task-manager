# 出 Windows 发布版（release）。
#
# 为什么不能直接在本目录 build：
#   Flutter 的 AOT 汇编步骤（flutter_assemble）在中文路径下会崩 ——
#   MSBuild 把项目路径按 GBK 解成乱码，读不到 app.dill。
#   debug 构建不走 AOT 所以没事，release 必崩。
#
# 办法：把源码复制到一个纯 ASCII 路径编译，再把产物拷回来。
# 用法：powershell -ExecutionPolicy Bypass -File tool\build_release.ps1
# （本文件必须以 UTF-8 BOM 保存，否则 PowerShell 5.1 会按 GBK 读，中文注释会解析失败）

$ErrorActionPreference = 'Stop'

$src      = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$tmp      = 'E:\ltm_release_build'
$flutter  = 'D:\flutter\bin\flutter.bat'
$outDir   = Join-Path $src 'dist'

Write-Host "项目目录 : $src"
Write-Host "编译目录 : $tmp"

if (-not (Test-Path $flutter)) { throw "找不到 flutter: $flutter" }

Write-Host ""
# 增量：临时目录**不删**，只把改动过的文件同步过去。
# 之前每次都删掉重建，编译缓存全丢，重编一次要 3 分钟；
# 保留临时目录后 Flutter 只重编改动部分，几十秒就够了。
Write-Host "[1/4] 增量同步源码到 ASCII 目录..."
if (-not (Test-Path $tmp)) { New-Item -ItemType Directory -Path $tmp | Out-Null }
# /XO = 只覆盖源里更新的文件；不删目标里的东西，缓存才留得住
robocopy $src $tmp /E /XO /XD build .dart_tool .idea .git .vscode dist dist_installer ephemeral /XF *.log /NFL /NDL /NJH /NJS /NP | Out-Null

Write-Host "[2/4] 编译 release（第一次会比较慢）..."
Push-Location $tmp
& $flutter build windows --release
$code = $LASTEXITCODE
Pop-Location
if ($code -ne 0) { throw "编译失败，退出码 $code" }

$built = Join-Path $tmp 'build\windows\x64\runner\Release'
if (-not (Test-Path $built)) { throw "没找到产物目录: $built" }

Write-Host "[3/4] 复制产物到 dist ..."
if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
robocopy $built $outDir /E /NFL /NDL /NJH /NJS /NP | Out-Null

$exe = Join-Path $outDir 'life_task_manager.exe'
$size = [math]::Round((Get-Item $exe).Length / 1MB, 1)
Write-Host "[4/4] 完成: $exe  ($size MB)"
Write-Host ""
Write-Host "发布版在 dist 文件夹里，整个文件夹拷走即可运行（用户数据仍在 vault 目录，不在程序目录）。"
