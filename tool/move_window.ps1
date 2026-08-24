param([int]$AppId = 10708, [int]$Dx = 200, [int]$Dy = 0)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W32 {
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr h, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  public struct RECT { public int L, T, R, B; }
}
"@
$p = Get-Process -Id $AppId
$h = $p.MainWindowHandle
$r = New-Object W32+RECT
[W32]::GetWindowRect($h, [ref]$r) | Out-Null
Write-Host "before: $($r.L),$($r.T) - $($r.R),$($r.B)"
[W32]::SetWindowPos($h, [IntPtr]::Zero, $r.L + $Dx, $r.T + $Dy, 0, 0, 0x0001 -bor 0x0004) | Out-Null
Start-Sleep -Milliseconds 300
[W32]::GetWindowRect($h, [ref]$r) | Out-Null
Write-Host "after: $($r.L),$($r.T) - $($r.R),$($r.B)"
