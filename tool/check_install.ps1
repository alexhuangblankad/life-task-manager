$exe = 'D:\LifeTaskManager\life_task_manager.exe'
$ver = (Get-Item $exe).VersionInfo.FileVersion
$count = (Get-ChildItem 'D:\LifeTaskManager' -Recurse -File | Measure-Object).Count
$drop = Test-Path 'D:\LifeTaskManager\desktop_drop_plugin.dll'
$appso = (Get-Item 'D:\LifeTaskManager\data\app.so').Length
Write-Output ("安装目录 exe 版本 : {0}" -f $ver)
Write-Output ("安装目录文件数     : {0}" -f $count)
Write-Output ("desktop_drop 插件  : {0}" -f $drop)
Write-Output ("app.so 大小        : {0}" -f $appso)

$cfgCandidates = @("$env:USERPROFILE\Documents\LifeTaskManager", 'D:\LifeTaskManagerData', 'D:\LifeTaskManager\vault')
foreach ($c in $cfgCandidates) { Write-Output ("数据目录 {0} : {1}" -f $c, (Test-Path $c)) }

Write-Output "--- 安装目录里有没有混进用户数据（应该是纯程序文件）---"
Get-ChildItem 'D:\LifeTaskManager' | Select-Object -ExpandProperty Name

Write-Output "--- 卸载记录 ---"
Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall' | ForEach-Object {
  $p = Get-ItemProperty $_.PSPath
  if ($p.DisplayName -match '人生任务') {
    Write-Output ("{0} | {1} | {2} | 卸载命令 {3}" -f $p.DisplayName, $p.DisplayVersion, $p.InstallLocation, $p.UninstallString)
  }
}

Write-Output "--- 快捷方式 ---"
Get-ChildItem "$env:APPDATA\Microsoft\Windows\Start Menu\Programs" -Recurse -Filter '*.lnk' | Where-Object Name -match '人生任务' | ForEach-Object { Write-Output ("开始菜单: " + $_.FullName) }
Get-ChildItem "$env:USERPROFILE\Desktop" -Filter '*.lnk' | Where-Object Name -match '人生任务' | ForEach-Object { Write-Output ("桌面: " + $_.FullName) }

Write-Output "--- 快捷方式指向 ---"
$sh = New-Object -ComObject WScript.Shell
foreach ($l in (Get-ChildItem "$env:USERPROFILE\Desktop" -Filter '*.lnk' | Where-Object Name -match '人生任务')) {
  Write-Output ("{0} -> {1}" -f $l.Name, $sh.CreateShortcut($l.FullName).TargetPath)
}
