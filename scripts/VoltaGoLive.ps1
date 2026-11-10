<#
.SYNOPSIS
Ponto de entrada dos lançadores (.bat) do VoltaGoLive.

.DESCRIPTION
Carrega o módulo, executa a ação pedida e mostra o resultado em português simples.
Erros aparecem com a explicação do que fazer.

.PARAMETER Action
Ativar, Desativar, Status ou Diagnostico.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Ativar', 'Desativar', 'Status', 'Diagnostico')]
    [string]$Action
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Line {
    param([string]$Text = '', [string]$Color = 'Gray')
    Write-Host -Object $Text -ForegroundColor $Color
}

function Format-Duration {
    param([timespan]$Duration)
    return ('{0}h {1:00}min' -f [int][math]::Floor($Duration.TotalHours), $Duration.Minutes)
}

function Show-Status {
    param([pscustomobject]$Status)
    Write-Line
    if ($Status.Active) {
        Write-Line -Text 'Túnel: ATIVO' -Color 'Green'
        if ($null -ne $Status.Uptime) {
            Write-Line -Text ('Ativo há: ' + (Format-Duration -Duration $Status.Uptime))
        }
        if ($Status.HandshakeConfirmed) {
            $when = 'horário não registrado'
            if ($null -ne $Status.LastHandshake) {
                $when = $Status.LastHandshake.ToString('dd/MM/yyyy HH:mm:ss')
            }
            Write-Line -Text ('Último handshake: ' + $when)
        }
        else {
            Write-Line -Text 'Último handshake: ainda não confirmado' -Color 'Yellow'
        }
    }
    else {
        Write-Line -Text 'Túnel: DESATIVADO' -Color 'Yellow'
    }
    $discord = 'fechado'
    if ($Status.DiscordRunning) {
        $discord = 'aberto'
    }
    Write-Line -Text ('Discord: ' + $discord)
}

try {
    $module = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'src\VoltaGoLive\VoltaGoLive.psd1'
    Import-Module -Name $module -Force

    Write-Line -Text ('VoltaGoLive: ' + $Action) -Color 'Cyan'
    Write-Line

    switch ($Action) {
        'Ativar' {
            try {
                $status = Enable-VoltaGoLive
            }
            catch {
                if ($_.Exception.Message -notlike 'O WireSock não está instalado.*') {
                    throw
                }
                Write-Line -Text 'O WireSock (programa que cria o túnel) ainda não está instalado.' -Color 'Yellow'
                $answer = Read-Host -Prompt 'Quer instalar agora pela fonte oficial? (S/N)'
                if ($answer -notmatch '^\s*[sS]') {
                    throw
                }
                $status = Enable-VoltaGoLive -InstallWireSock
            }
            Show-Status -Status $status
        }
        'Desativar' {
            Show-Status -Status (Disable-VoltaGoLive)
        }
        'Status' {
            Show-Status -Status (Get-VoltaGoLiveStatus)
        }
        'Diagnostico' {
            $result = New-VoltaGoLiveDiagnostic
            Write-Line -Text $result.Text
            Write-Line -Text 'Relatório gerado e copiado. É só colar (Ctrl+V) onde pediram.' -Color 'Green'
            Write-Line -Text 'Chaves, IPs, seu nome de usuário e o nome do computador já foram removidos.'
            Write-Line -Text ('Arquivo salvo em: ' + $result.Path)
        }
    }
    $exitCode = 0
}
catch {
    Write-Line
    Write-Line -Text ('ERRO: ' + $_.Exception.Message) -Color 'Red'
    if ($_.Exception.Message -notmatch 'O que fazer:') {
        Write-Line -Text '  O que fazer: rode o Diagnostico.bat e envie o relatório para quem está te ajudando.' -Color 'Red'
    }
    $exitCode = 1
}

Write-Line
exit $exitCode
