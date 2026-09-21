param(
  [Parameter(Mandatory=$true)][string]$ProviderUrl
)
flutter build windows --release --dart-define=SB_LOCKED=true --dart-define=SB_PROVIDER_BASE_URL=$ProviderUrl
