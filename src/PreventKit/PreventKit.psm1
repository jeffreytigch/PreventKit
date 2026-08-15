Set-StrictMode -Version Latest

$manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'PreventKit.psd1')
$script:provenanceNamespace = [string]$manifest.PrivateData.ProvenanceNamespace
if ([string]::IsNullOrWhiteSpace($script:provenanceNamespace)) {
    throw 'PreventKit module manifest must declare a non-empty ProvenanceNamespace in PrivateData.'
}

$privateFunctions = Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -File
$publicFunctions  = Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public')  -Filter '*.ps1' -File

foreach ($file in $privateFunctions) { . $file.FullName }
foreach ($file in $publicFunctions)  { . $file.FullName }

Export-ModuleMember -Function 'Invoke-PreventKitRun', 'Start-PreventKitRun'