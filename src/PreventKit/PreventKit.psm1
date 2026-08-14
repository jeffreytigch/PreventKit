Set-StrictMode -Version Latest

$privateFunctions = Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -File
$publicFunctions  = Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public')  -Filter '*.ps1' -File

foreach ($file in $privateFunctions) { . $file.FullName }
foreach ($file in $publicFunctions)  { . $file.FullName }

Export-ModuleMember -Function 'Invoke-PreventKitRun'
