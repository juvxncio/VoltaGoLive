function New-VoltaGoLiveDiagnostic {
    <#
    .SYNOPSIS
    Gera um relatório de diagnóstico já redigido, pronto para colar num pedido de ajuda.

    .DESCRIPTION
    Reúne informações sobre o Windows, o WireSock, o arquivo .conf (somente a estrutura,
    nunca os valores), o Discord, o estado do túnel e as últimas linhas dos logs.

    Antes de ser gravado ou exibido, o relatório inteiro passa pela redação: chaves,
    endereços IP, nome do usuário, nome do computador e caminhos do perfil são trocados
    por marcadores. O relatório não lê nem lista variáveis de ambiente.

    O arquivo é salvo na pasta de dados do VoltaGoLive e o texto é copiado para a área
    de transferência.

    .PARAMETER ConfigPath
    Caminho de um arquivo .conf específico. Sem ele, usa o único .conf da pasta "config".

    .PARAMETER NoClipboard
    Não copia o relatório para a área de transferência.

    .EXAMPLE
    New-VoltaGoLiveDiagnostic

    Gera o relatório, salva em arquivo e copia para a área de transferência.

    .OUTPUTS
    PSCustomObject com Path (arquivo gerado) e Text (conteúdo redigido).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [string]$ConfigPath,

        [switch]$NoClipboard
    )

    Assert-VglWindows
    $paths = Get-VglPath
    $requestedConf = $ConfigPath
    $report = New-Object -TypeName 'System.Collections.Generic.List[string]'
    $safely = {
        # Cada bloco roda isolado: um erro vira uma linha no relatório, não interrompe o resto.
        param([string]$Title, [scriptblock]$Block)
        $report.Add('')
        $report.Add("== $Title ==")
        try {
            foreach ($line in @(& $Block)) {
                $report.Add([string]$line)
            }
        }
        catch {
            $report.Add('ERRO ao coletar: ' + $_.Exception.Message)
        }
    }

    $module = $MyInvocation.MyCommand.Module
    $report.Add('Relatório de diagnóstico do VoltaGoLive')
    $report.Add('Gerado em: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    $report.Add('Versão do VoltaGoLive: ' + (Format-VglVersion -Version $module.Version))

    & $safely 'Sistema' {
        'Windows: ' + [System.Environment]::OSVersion.Version.Build
        'Sistema de 64 bits: ' + [System.Environment]::Is64BitOperatingSystem
        'PowerShell: ' + $PSVersionTable.PSVersion.Major + '.' + $PSVersionTable.PSVersion.Minor
        'Executando como administrador: ' + (Test-VglAdministrator)
    }

    & $safely 'WireSock' {
        $exe = Find-VglWireSock
        if ([string]::IsNullOrEmpty($exe)) {
            'Instalado: False'
        }
        else {
            'Instalado: True'
            'Caminho: ' + $exe
            'Versão: ' + (Format-VglVersion -Version (Get-Item -LiteralPath $exe).VersionInfo.FileVersion)
            $signature = Get-VglSignature -Path $exe
            'Assinatura: ' + $signature.Status
            'Assinante: ' + $signature.Subject
            'Assinatura aceita: ' + (Test-VglSignature -Signature $signature)
        }
        'winget disponível: ' + ($null -ne (Get-Command -Name 'winget.exe' -ErrorAction SilentlyContinue))
    }

    & $safely 'Arquivo .conf (somente estrutura)' {
        $source = Find-VglUserConf -ConfigPath $requestedConf -ConfigDir $paths.ConfigDir
        $text = [string](Get-Content -LiteralPath $source -Raw -Encoding UTF8)
        Get-VglConfSummary -Text $text
        Test-VglConf -Text $text | ForEach-Object { 'Problema: ' + $_ }
    }

    & $safely 'Discord' {
        foreach ($install in @(Find-VglDiscordInstall -LocalAppData $paths.LocalAppData)) {
            '{0}: instalado = {1}' -f $install.Channel, $install.Installed
        }
        $running = @(Get-VglDiscordProcess)
        'Processos abertos: ' + $running.Count
        'Nomes: ' + ((@($running | ForEach-Object { $_.ProcessName } | Sort-Object -Unique)) -join ', ')
    }

    & $safely 'Túnel' {
        $status = Get-VoltaGoLiveStatus
        'Ativo: ' + $status.Active
        'Ativo desde: ' + $status.StartedAt
        'Handshake confirmado: ' + $status.HandshakeConfirmed
        'Último handshake: ' + $status.LastHandshake
        foreach ($process in @(Get-VglTunnelProcess -Paths $paths)) {
            'Processo: {0} (PID {1})' -f $process.Name, $process.ProcessId
        }
        'Cópia do .conf existe: ' + (Test-Path -LiteralPath $paths.RuntimeConf)
        if (Test-Path -LiteralPath $paths.RuntimeConf) {
            $copy = [string](Get-Content -LiteralPath $paths.RuntimeConf -Raw -Encoding UTF8)
            $apps = @(@(ConvertFrom-VglConf -Text $copy) | Where-Object { $_.Kind -eq 'Entry' -and $_.Key -eq 'AllowedApps' } | ForEach-Object { $_.Value })
            'AllowedApps na cópia: ' + ($apps -join ' | ')
        }
    }

    & $safely 'Log do túnel (últimas 60 linhas)' {
        Get-VglLogTail -Path $paths.TunnelLog -Count 60
    }

    & $safely 'Log do VoltaGoLive (últimas 60 linhas)' {
        Get-VglLogTail -Path $paths.LogFile -Count 60
    }

    # Redação final do relatório inteiro, linha por linha.
    $text = (@($report | ForEach-Object { Protect-VoltaGoLiveText -Text $_ }) -join "`r`n") + "`r`n"

    $file = Join-Path -Path $paths.DiagnosticDir -ChildPath ('diagnostico-{0}.txt' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    if ($PSCmdlet.ShouldProcess($file, 'Gravar o relatório')) {
        if (-not (Test-Path -LiteralPath $paths.DiagnosticDir)) {
            $null = New-Item -Path $paths.DiagnosticDir -ItemType Directory -Force
        }
        [System.IO.File]::WriteAllText($file, $text, (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $true))
        if (-not $NoClipboard) {
            try {
                Set-Clipboard -Value $text
            }
            catch {
                Write-VglLog -Message 'Não foi possível copiar o relatório para a área de transferência.' -Level 'AVISO'
            }
        }
    }

    return [pscustomobject]@{
        Path = $file
        Text = $text
    }
}
