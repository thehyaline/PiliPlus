param([int]$AppPid = 16812)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32Top {
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
}
"@
$p = Get-Process -Id $AppPid
$h = $p.MainWindowHandle
[Win32Top]::ShowWindow($h, 9) | Out-Null  # SW_RESTORE
# 置顶再取消置顶，以绕过前台锁
[Win32Top]::SetWindowPos($h, [IntPtr](-1), 0, 0, 0, 0, 0x0001 -bor 0x0002) | Out-Null  # HWND_TOPMOST, SWP_NOMOVE|SWP_NOSIZE
[Win32Top]::SetWindowPos($h, [IntPtr](-2), 0, 0, 0, 0, 0x0001 -bor 0x0002 -bor 0x0040) | Out-Null  # HWND_NOTOPMOST + SWP_SHOWWINDOW
[Win32Top]::SetForegroundWindow($h) | Out-Null
$rect = New-Object Win32Top+RECT
[Win32Top]::GetWindowRect($h, [ref]$rect) | Out-Null
Write-Output "rect: $($rect.Left),$($rect.Top) - $($rect.Right),$($rect.Bottom)"
