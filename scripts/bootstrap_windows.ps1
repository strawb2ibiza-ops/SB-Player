$ErrorActionPreference = 'Stop'
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw 'Flutter is not installed or is not on PATH.'
}
flutter create --project-name sb_player --platforms=windows,android .
flutter pub get
Write-Host 'SB Player project bootstrapped.' -ForegroundColor Green
Write-Host 'Run .\\scripts\\run_open.ps1 for the open edition.'
