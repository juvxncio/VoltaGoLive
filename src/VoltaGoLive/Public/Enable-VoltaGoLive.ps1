function Enable-VoltaGoLive {
    <#
    .SYNOPSIS
    Ativa o túnel: coloca somente o Discord dentro da VPN.

    .DESCRIPTION
    Passo a passo do que a função faz:
      1. Confere se o WireSock está instalado e com assinatura digital válida.
      2. Localiza e valida o arquivo .conf WireGuard (pasta "config" ou -ConfigPath).
      3. Fecha o Discord, para que ele abra as conexões de novo já dentro do túnel.
      4. Cria uma CÓPIA do .conf com a linha AllowedApps restrita ao Discord.
         O arquivo original nunca é alterado.
      5. Sobe o túnel com o WireSock e reabre o Discord.
      6. Espera a confirmação de handshake no log do túnel.

    O resto do computador continua usando a conexão normal.

    .PARAMETER ConfigPath
    Caminho de um arquivo .conf específico. Sem ele, usa o único .conf da pasta "config".

    .PARAMETER InstallWireSock
    Instala o WireSock pelo winget, sem perguntar, caso ele não esteja instalado.

    .EXAMPLE
    Enable-VoltaGoLive

    Ativa usando o .conf que está na pasta "config".

    .EXAMPLE
    Enable-VoltaGoLive -ConfigPath 'D:\vpn\proton.conf'

    Ativa usando um arquivo específico.

    .OUTPUTS
    PSCustomObject com o resultado da ativação (mesmo formato do Get-VoltaGoLiveStatus).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [string]$ConfigPath,

        [switch]$InstallWireSock
    )

    Assert-VglWindows
    $paths = Get-VglPath
    Write-VglLog -Message 'Ativação iniciada.'

    # 1. WireSock instalado e assinado
    $exe = Find-VglWireSock
    if ([string]::IsNullOrEmpty($exe)) {
        if (-not $InstallWireSock) {
            throw (New-VglProblem -Message 'O WireSock não está instalado.' `
                    -Fix ('Rode o Ativar.bat e responda S quando ele oferecer a instalação. Se preferir instalar à mão, abra o PowerShell e rode "winget install --id {0} --exact --source winget".' -f $script:Vgl.WireSockWingetId))
        }
        $exe = Install-VoltaGoLiveWireSock
    }
    $signature = Get-VglSignature -Path $exe
    if (-not (Test-VglSignature -Signature $signature)) {
        throw (New-VglProblem -Message ('O arquivo do WireSock não tem uma assinatura digital válida do publicador esperado (situação: {0}).' -f $signature.Status) `
                -Fix ('Por segurança, não vou executar esse arquivo. Reinstale o WireSock: abra o PowerShell e rode "winget install --id {0} --exact --source winget --force".' -f $script:Vgl.WireSockWingetId))
    }

    # 2. .conf presente e válido
    $source = Find-VglUserConf -ConfigPath $ConfigPath -ConfigDir $paths.ConfigDir
    $text = Get-Content -LiteralPath $source -Raw -Encoding UTF8
    if ($null -eq $text) {
        $text = ''
    }
    $problems = @(Test-VglConf -Text $text)
    if ($problems.Count -gt 0) {
        throw (New-VglProblem -Message ("O arquivo .conf tem problemas:`n    - " + ($problems -join "`n    - ")) `
                -Fix ('Baixe o arquivo de novo na sua conta Proton ({0}), escolhendo WireGuard e a plataforma Windows, sem editar nada.' -f $script:Vgl.ProtonConfigUrl))
    }

    if (-not $PSCmdlet.ShouldProcess('Discord', 'Ativar o túnel')) {
        return
    }

    # Se já estava ativo, recomeça do zero.
    $null = Stop-VglTunnel -Paths $paths

    # 3. Fecha o Discord
    Write-VglMessage -Message 'Fechando o Discord...'
    $channels = @(Stop-VglDiscord)

    try {
        # 4. Cópia do .conf com AllowedApps (o original não é tocado)
        if (-not (Test-Path -LiteralPath $paths.RuntimeDir)) {
            $null = New-Item -Path $paths.RuntimeDir -ItemType Directory -Force
        }
        $tunnelText = ConvertTo-VglTunnelConf -Text $text -Apps (Get-VglDiscordAppName)
        [System.IO.File]::WriteAllText($paths.RuntimeConf, $tunnelText, (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false))

        # 5. Sobe o túnel e reabre o Discord
        Write-VglMessage -Message 'Subindo o túnel...'
        Start-VglTunnel -ExePath $exe -Paths $paths
        Save-VglState -Path $paths.StateFile -StartedAt (Get-Date) -Channels $channels
    }
    catch {
        Write-VglLog -Message ('Falha na ativação: ' + $_.Exception.Message) -Level 'ERRO'
        $null = Stop-VglTunnel -Paths $paths
        Clear-VglRuntime -Paths $paths
        $null = Start-VglDiscord -LocalAppData $paths.LocalAppData -Channel $channels
        throw
    }

    Write-VglMessage -Message 'Abrindo o Discord dentro do túnel...'
    $opened = @(Start-VglDiscord -LocalAppData $paths.LocalAppData -Channel $channels)
    if ($opened.Count -eq 0) {
        Write-VglMessage -Message 'Não encontrei o Discord instalado para abrir. Abra o Discord manualmente.' -Kind 'Aviso'
    }

    # 6. Confirma o handshake
    Write-VglMessage -Message ('Aguardando a confirmação do túnel (até {0} segundos)...' -f $script:Vgl.HandshakeTimeout)
    $handshake = Wait-VglHandshake -LogPath $paths.TunnelLog

    if ($handshake.Confirmed) {
        Write-VglMessage -Message 'Pronto! O túnel está ativo e o Discord está passando por ele.' -Kind 'Ok'
    }
    else {
        Write-VglMessage -Kind 'Aviso' -Message 'O túnel foi iniciado, mas não consegui confirmar o handshake pelo log.'
        Write-VglMessage -Kind 'Aviso' -Message 'Teste o Go Live no Discord. Se não funcionar, rode o Diagnostico.bat e envie o relatório.'
    }

    return (Get-VoltaGoLiveStatus)
}
