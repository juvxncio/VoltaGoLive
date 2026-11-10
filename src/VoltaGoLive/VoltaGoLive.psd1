@{
    RootModule        = 'VoltaGoLive.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '6c1f0c0e-6b0f-4d0a-9a51-2f6f3c3b7e11'
    Author            = 'juvxncio'
    CompanyName       = 'Comunidade'
    Copyright         = '(c) juvxncio. Licenca MIT.'
    Description       = 'Coloca somente o Discord dentro de um tunel WireGuard usando o WireSock.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Enable-VoltaGoLive'
        'Disable-VoltaGoLive'
        'Get-VoltaGoLiveStatus'
        'New-VoltaGoLiveDiagnostic'
        'Install-VoltaGoLiveWireSock'
        'Protect-VoltaGoLiveText'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('WireGuard', 'WireSock', 'SplitTunnel', 'Windows')
            LicenseUri = 'https://github.com/juvxncio/VoltaGoLive/blob/main/LICENSE'
            ProjectUri = 'https://github.com/juvxncio/VoltaGoLive'
        }
    }
}
