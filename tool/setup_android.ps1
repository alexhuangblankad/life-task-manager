# 装安卓构建工具链：JDK 17 + Android SDK（cmdline-tools）
#
# 用法：powershell -ExecutionPolicy Bypass -File tool\setup_android.ps1
# 工具都装自己目录（跟 Flutter / VS BuildTools 一样），不塞项目文件夹：
#   JDK      → winget 装到 Program Files
#   Android SDK → D:\android-sdk
# 本文件必须存成 UTF-8 带 BOM（PowerShell 5.1 按 GBK 读会解析失败）

$ErrorActionPreference = 'Continue'

$sdkRoot = 'D:\android-sdk'
$dl      = 'D:\dev\_downloads'
New-Item -ItemType Directory -Force -Path $dl | Out-Null
New-Item -ItemType Directory -Force -Path $sdkRoot | Out-Null

Write-Host '=== [1/4] 装 JDK 17（flutter 构建安卓要 JDK 17+）==='
$jdk = Get-ChildItem 'C:\Program Files\Eclipse Adoptium' -Directory -ErrorAction SilentlyContinue |
       Where-Object { $_.Name -like 'jdk-17*' } | Select-Object -First 1
if ($null -eq $jdk) {
  winget install --id EclipseAdoptium.Temurin.17.JDK -e --accept-source-agreements --accept-package-agreements --disable-interactivity
  $jdk = Get-ChildItem 'C:\Program Files\Eclipse Adoptium' -Directory -ErrorAction SilentlyContinue |
         Where-Object { $_.Name -like 'jdk-17*' } | Select-Object -First 1
}
if ($null -eq $jdk) { Write-Host '!! JDK 没装上，后面的步骤会失败'; exit 1 }
$env:JAVA_HOME = $jdk.FullName
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
Write-Host "JAVA_HOME = $env:JAVA_HOME"
& "$env:JAVA_HOME\bin\java.exe" -version

Write-Host ''
Write-Host '=== [2/4] 下 cmdline-tools ==='
$zip = Join-Path $dl 'cmdline-tools.zip'
if (-not (Test-Path $zip) -or (Get-Item $zip).Length -lt 50MB) {
  # Google 的包名带版本号，试几个已知的
  $urls = @(
    'https://dl.google.com/android/repository/commandlinetools-win-13114758_latest.zip',
    'https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip'
  )
  $ok = $false
  foreach ($u in $urls) {
    Write-Host "  试 $u"
    try {
      Invoke-WebRequest -Uri $u -OutFile $zip -TimeoutSec 600
      if ((Get-Item $zip).Length -gt 50MB) { $ok = $true; break }
    } catch { Write-Host "  这个不行：$($_.Exception.Message)" }
  }
  if (-not $ok) { Write-Host '!! cmdline-tools 下载失败'; exit 1 }
}
Write-Host "  已下载 $((Get-Item $zip).Length / 1MB) MB"

Write-Host ''
Write-Host '=== [3/4] 解压到 D:\android-sdk\cmdline-tools\latest ==='
$tmpExtract = Join-Path $dl 'cmdline-tools-extract'
if (Test-Path $tmpExtract) { Remove-Item $tmpExtract -Recurse -Force }
Expand-Archive -Path $zip -DestinationPath $tmpExtract -Force
$target = Join-Path $sdkRoot 'cmdline-tools\latest'
if (Test-Path $target) { Remove-Item $target -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
Move-Item (Join-Path $tmpExtract 'cmdline-tools') $target

$sdkmanager = Join-Path $target 'bin\sdkmanager.bat'
if (-not (Test-Path $sdkmanager)) { Write-Host "!! 找不到 sdkmanager：$sdkmanager"; exit 1 }

Write-Host ''
Write-Host '=== [4/4] 装 SDK 组件并接受许可 ==='
$pkgs = @('platform-tools', 'platforms;android-35', 'build-tools;35.0.0')
Write-Host '  接受许可…'
$yes = ('y' + [Environment]::NewLine) * 60
$yes | & $sdkmanager --sdk_root=$sdkRoot --licenses 2>&1 | Select-Object -Last 3
Write-Host '  装组件…'
& $sdkmanager --sdk_root=$sdkRoot @pkgs 2>&1 | Select-Object -Last 5

Write-Host ''
Write-Host '=== 让 flutter 认这个 SDK ==='
& 'D:\flutter\bin\flutter.bat' config --android-sdk $sdkRoot
& 'D:\flutter\bin\flutter.bat' config --jdk-dir $env:JAVA_HOME
Write-Host ''
Write-Host "完成。SDK 在 $sdkRoot"
