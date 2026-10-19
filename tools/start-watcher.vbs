' ==========================================================================
' WorkBuddy Anime Boot - 静默启动器（无窗口）
' --------------------------------------------------------------------------
' 作用：以"完全隐藏"的方式启动看护脚本 watch.ps1。
'   · sh.Run 的第二个参数 0 = 窗口隐藏（SW_HIDE），控制台根本不会出现
'   · 第三个参数 False = 不等待，启动后立刻退出（不会留下任何窗口）
'
' 这个文件就是开机自启项。手动启用时也可以双击运行（无窗口、无提示）。
' ==========================================================================
Dim sh, fso, scriptPath
Set sh  = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptPath = sh.ExpandEnvironmentStrings("%USERPROFILE%") & "\.workbuddy-anime\watcher\watch.ps1"

If fso.FileExists(scriptPath) Then
    sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & scriptPath & """", 0, False
End If

Set fso = Nothing
Set sh  = Nothing
