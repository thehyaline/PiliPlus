param([int]$X = 1500, [int]$Y = 300, [int]$Amount = 400)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class M {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
}
"@
[M]::SetCursorPos($X, $Y)
# wheel down scroll
[M]::mouse_event(0x0800, 0, 0, [uint32]$Amount, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 400
