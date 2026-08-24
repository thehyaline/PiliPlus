param([int]$AppId = 10708)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W33 {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int cmd);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
}
"@
$p = Get-Process -Id $AppId
$h = $p.MainWindowHandle
[W33]::ShowWindow($h, 6) | Out-Null  # SW_MINIMIZE
Start-Sleep -Milliseconds 500
Write-Host "visible: $([W33]::IsWindowVisible($h))"
