function Test-VglAdministrator {
    # Diz se o PowerShell atual está rodando como administrador.
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object -TypeName System.Security.Principal.WindowsPrincipal -ArgumentList $identity
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Format-VglVersion {
    # Escreve versões com hífens (3-8-2-1) para a redação não confundir com endereço IP.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object]$Version
    )

    if ($null -eq $Version) {
        return 'desconhecida'
    }
    return (([string]$Version).Trim() -replace '[.,]\s*', '-')
}
