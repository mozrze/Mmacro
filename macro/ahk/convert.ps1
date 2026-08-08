Add-Type -AssemblyName System.Drawing
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$dir = Join-Path $scriptDir "..\images"
$dir = (Resolve-Path $dir).Path
$imgs = @("StartGame.png", "Start.png")
foreach ($name in $imgs) {
    $path = Join-Path $dir $name
    if (!(Test-Path $path)) {
        Write-Host ("Файл не найден: {0}" -f $path)
        continue
    }
    $bmpPath = $path -replace "\.png$", ".bmp"
    $img = [System.Drawing.Image]::FromFile($path)
    $bmp = New-Object System.Drawing.Bitmap($img)
    $bmp.Save($bmpPath, [System.Drawing.Imaging.ImageFormat]::Bmp)
    $cx = [int]($img.Width / 2)
    $cy = [int]($img.Height / 2)
    $color = $bmp.GetPixel($cx, $cy)
    $hex = "0x{0:X2}{1:X2}{2:X2}" -f $color.R, $color.G, $color.B
    Write-Host ("{0}: {1}x{2} center=({3},{4}) color={5}" -f $name, $img.Width, $img.Height, $cx, $cy, $hex)
    $bmp.Dispose()
    $img.Dispose()
}