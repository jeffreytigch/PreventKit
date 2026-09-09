Set-StrictMode -Version Latest

$manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'PreventKit.psd1')
$script:ownerMarker = [string]$manifest.PrivateData.OwnerMarker
if ([string]::IsNullOrWhiteSpace($script:ownerMarker)) {
    throw 'PreventKit module manifest must declare a non-empty OwnerMarker in PrivateData.'
}

$privateFunctions = Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -File
$publicFunctions  = Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public')  -Filter '*.ps1' -File

foreach ($file in $privateFunctions) { . $file.FullName }
foreach ($file in $publicFunctions)  { . $file.FullName }

Export-ModuleMember -Function 'Invoke-PreventKitRun', 'Start-PreventKitRun', 'Get-PreventKitRunLog', 'New-PreventKitRunReport',
    'Register-CatalogueAdapter', 'Get-CatalogueAdapter', 'Get-CatalogueAdapterList', 'Unregister-CatalogueAdapter',
    'Get-PreventKitModuleIntegrity', 'New-PreventKitIntegrityBaseline'