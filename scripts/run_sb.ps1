param(
  [Parameter(Mandatory=$true)][string]$ProviderUrl
)
flutter run -d windows --dart-define=SB_LOCKED=true --dart-define=SB_PROVIDER_BASE_URL=$ProviderUrl
