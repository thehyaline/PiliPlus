param(
    [string]$MatchHex = '',
    [int]$X0 = 0, [int]$Y0 = 0, [int]$X1 = 100, [int]$Y1 = 100,
    [int]$Step = 1,
    [int]$Tolerance = 40
)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
Write-Output "args: X0=$X0 Y0=$Y0 X1=$X1 Y1=$Y1 Step=$Step MatchHex=[$MatchHex] Tol=$Tolerance"
if ($MatchHex) {
    $mr = [Convert]::ToInt32($MatchHex.Substring(0, 2), 16)
    $mg = [Convert]::ToInt32($MatchHex.Substring(2, 2), 16)
    $mb = [Convert]::ToInt32($MatchHex.Substring(4, 2), 16)
}
$hits = 0
for ($y = $Y0; $y -le $Y1; $y += $Step) {
    for ($x = $X0; $x -le $X1; $x += $Step) {
        $c = $bmp.GetPixel($x, $y)
        if ($MatchHex) {
            if ([Math]::Abs($c.R - $mr) -le $Tolerance -and
                [Math]::Abs($c.G - $mg) -le $Tolerance -and
                [Math]::Abs($c.B - $mb) -le $Tolerance) {
                Write-Output "$x,$y = R=$($c.R) G=$($c.G) B=$($c.B) #$('{0:X2}{1:X2}{2:X2}' -f $c.R,$c.G,$c.B)"
                $hits++
            }
        } else {
            Write-Output "$x,$y = R=$($c.R) G=$($c.G) B=$($c.B) #$('{0:X2}{1:X2}{2:X2}' -f $c.R,$c.G,$c.B)"
        }
    }
}
Write-Output "hits=$hits"
$g.Dispose(); $bmp.Dispose()
