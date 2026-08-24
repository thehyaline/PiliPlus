param([int]$AppPid = 16812)
$sig = '[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);'
$type = Add-Type -MemberDefinition $sig -Name Win32SetFg2 -Namespace Win32 -PassThru
$p = Get-Process -Id $AppPid
$type::SetForegroundWindow($p.MainWindowHandle)
