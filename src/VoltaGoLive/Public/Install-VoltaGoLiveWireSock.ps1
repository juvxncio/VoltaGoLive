function Install-VoltaGoLiveWireSock {
    <#
    .SYNOPSIS
    Instala o WireSock Secure Connect pelo winget, a partir da fonte oficial.

    .DESCRIPTION
    Usa o winget (que já vem no Windows 10 e 11) com o identificador oficial do pacote.
    O winget baixa o instalador do site do WireSock, confere o SHA256 publicado no
    repositório de pacotes da Microsoft e pede permissão de administrador, porque o
    WireSock instala um driver de rede.

    O VoltaGoLive não baixa nem redistribui nenhum arquivo do WireSock por conta própria.
    O pacote instalado é o "WireSock Secure Connect CLI" (NTKERNEL.WireSockVPNClientCLI),
    que traz o wiresock-client.exe. O pacote com interface gráfica não traz esse arquivo.
    Se o winget não existir no computador, a função explica o que fazer.

    .EXAMPLE
    Install-VoltaGoLiveWireSock

    Instala o WireSock e devolve o caminho do wiresock-client.exe.

    .OUTPUTS
    System.String. Caminho do wiresock-client.exe instalado.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([string])]
    param()

    Assert-VglWindows

    $winget = Get-Command -Name 'winget.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $winget) {
        throw (New-VglProblem -Message 'O winget (instalador de programas do Windows) não está disponível neste computador.' `
                -Fix ('Instale o "Instalador de Aplicativo" pela Microsoft Store (ele traz o winget; veja {0}) e rode o Ativar.bat de novo.' -f $script:Vgl.WingetHelp))
    }

    Write-VglMessage -Message 'Vou instalar o WireSock Secure Connect CLI pelo winget (fonte oficial).'
    Write-VglMessage -Message 'O Windows vai pedir permissão de administrador: o WireSock instala um driver de rede, e isso exige essa permissão.'
    Write-VglMessage -Message ('O WireSock é gratuito para uso pessoal. Licença: {0}' -f $script:Vgl.WireSockLicense)

    if ($PSCmdlet.ShouldProcess($script:Vgl.WireSockWingetId, 'Instalar pelo winget')) {
        $arguments = @(
            'install', '--id', $script:Vgl.WireSockWingetId, '--exact', '--source', 'winget',
            '--accept-package-agreements', '--accept-source-agreements'
        )
        & $winget.Source @arguments | Out-Host
        Write-VglLog -Message ('winget terminou com código {0}.' -f $LASTEXITCODE)
    }

    $path = Find-VglWireSock
    if ([string]::IsNullOrEmpty($path)) {
        throw (New-VglProblem -Message 'A instalação terminou, mas não encontrei o wiresock-client.exe.' `
                -Fix ('Abra o PowerShell, rode "winget install --id {0} --exact --source winget" e depois rode o Ativar.bat de novo.' -f $script:Vgl.WireSockWingetId))
    }
    return $path
}
