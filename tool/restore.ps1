param([int]$AppId = 10708)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W34 {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int cmd);
}
"@
$p = Get-Process -Id $AppId
[W34]::ShowWindow($p.MainWindowHandle, 9) | Out-Null
