param([int]$X = 2900, [int]$Y = 300, [int]$Amount = 360)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class M2 {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
}
"@
[M2]::SetCursorPos($X, $Y)
[M2]::mouse_event(0x0800, 0, 0, [uint32]$Amount, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 600
