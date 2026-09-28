# 一键出 Windows 安装包。
#
# 做三件事：1) 出 release 产物到 dist/  2) 用 Inno Setup 打包  3) 报路径
# 用法：powershell -ExecutionPolicy Bypass -File tool\build_installer.ps1
# （本文件必须存成 UTF-8 带 BOM，否则 PowerShell 5.1 按 GBK 读会解析失败）

$ErrorActionPreference = 'Stop'

$root     = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$iscc     = Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'
$iss      = Join-Path $root 'installer\LifeTaskManager.iss'
$dist     = Join-Path $root 'dist'
$outDir   = Join-Path $root 'dist_installer'

if (-not (Test-Path $iscc)) { throw "找不到 Inno Setup 的 ISCC.exe：$iscc" }
if (-not (Test-Path $iss))  { throw "找不到脚本：$iss" }

# 1. 先出 release（没有 dist 或强制重建时）
if (-not (Test-Path (Join-Path $dist 'life_task_manager.exe'))) {
  Write-Host "[1/2] dist 里没有产物，先跑 build_release.ps1 ..."
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tool\build_release.ps1')
} else {
  Write-Host "[1/2] 用现有的 dist（要重编就先跑 tool\build_release.ps1）"
}

# 2. 打包
Write-Host "[2/2] Inno Setup 打包 ..."
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
& $iscc $iss
if ($LASTEXITCODE -ne 0) { throw "打包失败，退出码 $LASTEXITCODE" }

$setup = Get-ChildItem $outDir -Filter '*-setup.exe' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($null -eq $setup) { throw "没找到生成的 setup.exe" }
$mb = [math]::Round($setup.Length / 1MB, 1)
Write-Host ""
Write-Host "完成：$($setup.FullName)  ($mb MB)"
Write-Host "这是一个标准 Windows 安装程序：双击 → 一路下一步（能自己选安装位置）→ 装完可选立刻启动。"
