Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ModuleRoot = $PSScriptRoot

foreach ($folder in @('Private', 'Public')) {
    $path = Join-Path -Path $PSScriptRoot -ChildPath $folder
    Get-ChildItem -Path $path -Filter '*.ps1' | Sort-Object -Property Name | ForEach-Object {
        . $_.FullName
    }
}

Export-ModuleMember -Function @(
    'Enable-VoltaGoLive'
    'Disable-VoltaGoLive'
    'Get-VoltaGoLiveStatus'
    'New-VoltaGoLiveDiagnostic'
    'Install-VoltaGoLiveWireSock'
    'Protect-VoltaGoLiveText'
)
