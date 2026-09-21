$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $root "windows\runner\resources"
$outFile = Join-Path $outDir "app_icon.ico"

New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$size = 256
$bitmap = New-Object System.Drawing.Bitmap $size, $size
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

$rect = New-Object System.Drawing.Rectangle 0, 0, $size, $size
$graphics.FillRectangle((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(4,5,9))), $rect)

$gradientRect = New-Object System.Drawing.Rectangle 24, 24, 208, 208
$brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
  $gradientRect,
  [System.Drawing.Color]::FromArgb(24,160,255),
  [System.Drawing.Color]::FromArgb(122,77,255),
  35
)
$graphics.FillRoundedRectangle = $null
$graphics.FillEllipse($brush, $gradientRect)

$inner = New-Object System.Drawing.Rectangle 35, 35, 186, 186
$graphics.FillEllipse(
  (New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(225,4,5,9))),
  $inner
)

$font = New-Object System.Drawing.Font("Arial", 72, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel))
$textBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
$format = New-Object System.Drawing.StringFormat
$format.Alignment = [System.Drawing.StringAlignment]::Center
$format.LineAlignment = [System.Drawing.StringAlignment]::Center
$graphics.DrawString("SB", $font, $textBrush, $rect, $format)

$icon = [System.Drawing.Icon]::FromHandle($bitmap.GetHicon())
$stream = [System.IO.File]::Create($outFile)
$icon.Save($stream)
$stream.Close()

$icon.Dispose()
$format.Dispose()
$textBrush.Dispose()
$font.Dispose()
$brush.Dispose()
$graphics.Dispose()
$bitmap.Dispose()

Write-Host "Generated $outFile"
