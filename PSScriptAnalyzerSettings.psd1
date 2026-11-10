@{
    Severity     = @('Error', 'Warning', 'Information')
    ExcludeRules = @(
        # O projeto fala com a pessoa pela tela, com cores. O Write-Host fica restrito a
        # Write-VglMessage (módulo) e Write-Line (scripts/VoltaGoLive.ps1).
        'PSAvoidUsingWriteHost'
    )
    Rules        = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.2')
        }
    }
}
