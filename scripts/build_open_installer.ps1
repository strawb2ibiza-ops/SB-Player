param(
  [string]$Iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root

try {
  flutter config --enable-windows-desktop
  flutter create --project-name sb_player --platforms=windows .
  & "$PSScriptRoot\generate_windows_brand_icon.ps1"
  flutter pub get
  flutter build windows --release

  if (-not (Test-Path $Iscc)) {
    throw "Inno Setup 6 was not found at $Iscc"
  }

  & $Iscc "$root\installer\SBPlayer.iss"
  Write-Host ""
  Write-Host "Installer created at:"
  Write-Host "$root\dist\SB-Player-Setup-v0.6.0.exe"
} finally {
  Pop-Location
}
