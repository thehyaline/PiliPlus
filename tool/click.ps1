param([int]$X = 1719, [int]$Y = 1355)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32Click {
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
}
"@
[Win32Click]::SetCursorPos($X, $Y) | Out-Null
[Win32Click]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)  # LEFTDOWN
Start-Sleep -Milliseconds 60
[Win32Click]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)  # LEFTUP
Write-Output "clicked $X,$Y"
