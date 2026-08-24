param([int]$ProcessId = 0)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinActivate {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
}
"@
$proc = Get-Process -Id $ProcessId -ErrorAction Stop
$hwnd = $proc.MainWindowHandle
if ($hwnd -eq [IntPtr]::Zero) { Write-Error "no main window for pid $ProcessId"; exit 1 }
# SW_RESTORE 确保窗口没有最小化
[WinActivate]::ShowWindow($hwnd, 9) | Out-Null
# Alt 键技巧绕过前台锁限制
[WinActivate]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)          # ALT down
[WinActivate]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)          # ALT up
[WinActivate]::SetForegroundWindow($hwnd) | Out-Null
Start-Sleep -Milliseconds 300
$fg = [WinActivate]::GetForegroundWindow()
Write-Output "hwnd=$hwnd foreground_now=$fg $([bool]($fg -eq $hwnd))"
