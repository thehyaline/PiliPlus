param(
    [int]$X = 100,
    [int]$Y = 100,
    [string]$Out = 'E:\Repo\PiliPlus\build\win_shot.png'
)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
$c = $bmp.GetPixel($X, $Y)
Write-Output "pixel($X,$Y) = R=$($c.R) G=$($c.G) B=$($c.B) A=$($c.A) #$('{0:X2}{1:X2}{2:X2}' -f $c.R,$c.G,$c.B)"
$bmp.Save($Out)
$g.Dispose(); $bmp.Dispose()
