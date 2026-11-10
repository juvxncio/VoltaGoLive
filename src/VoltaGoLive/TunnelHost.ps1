<#
.SYNOPSIS
Processo oculto que mantém o túnel do VoltaGoLive aberto.

.DESCRIPTION
Executa o wiresock-client com a configuração informada e grava a saída dele no log do
túnel, uma linha por vez, sempre redigida (sem chaves, IPs, usuário ou nome do computador)
e sem as linhas em que o WireSock lista os programas abertos no computador.

Roda como administrador, porque o WireSock precisa disso para usar o driver de rede.
Para parar, basta existir o arquivo de sinal (-StopFile): este processo encerra o
wiresock-client e termina. Quando o log passa do tamanho máximo, o arquivo atual vira
".1" e um novo começa.

Este arquivo é iniciado pelo módulo (Start-VglTunnel). Não precisa ser aberto à mão.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ExePath,

    [Parameter(Mandatory)]
    [string]$ConfigPath,

    [Parameter(Mandatory)]
    [string]$LogPath,

    [Parameter(Mandatory)]
    [string]$StopFile,

    [string]$LogLevel = 'debug',

    [long]$MaxBytes = 2097152
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'VoltaGoLive.psd1') -Force
$noise = & (Get-Module -Name VoltaGoLive) { $script:Vgl.TunnelLogNoise }

$folder = Split-Path -Path $LogPath -Parent
if (-not (Test-Path -LiteralPath $folder)) {
    $null = New-Item -Path $folder -ItemType Directory -Force
}

$encoding = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
$script:Written = 0L
$script:Limit = $MaxBytes
$script:Writer = $null

function Open-LogWriter {
    $stream = New-Object -TypeName System.IO.FileStream -ArgumentList @(
        $LogPath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
    $script:Writer = New-Object -TypeName System.IO.StreamWriter -ArgumentList @($stream, $encoding)
    $script:Writer.AutoFlush = $true
    $script:Written = $stream.Length
}

function Write-TunnelLine {
    param([string]$Text)

    if ($Text -match $noise) {
        return
    }
    $line = '{0} | {1}' -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'), (Protect-VoltaGoLiveText -Text $Text)
    $script:Writer.WriteLine($line)
    $script:Written += $line.Length + 2
    if ($script:Written -gt $script:Limit) {
        $script:Writer.Dispose()
        Move-Item -LiteralPath $LogPath -Destination ($LogPath + '.1') -Force
        Open-LogWriter
    }
}

Open-LogWriter
$process = $null
try {
    $info = New-Object -TypeName System.Diagnostics.ProcessStartInfo
    $info.FileName = $ExePath
    $info.Arguments = 'run -config "{0}" -log-level {1}' -f $ConfigPath, $LogLevel
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::Start($info)
    $readers = @($process.StandardOutput, $process.StandardError)
    $tasks = @($readers[0].ReadLineAsync(), $readers[1].ReadLineAsync())
    $open = @($true, $true)

    while ($open[0] -or $open[1]) {
        foreach ($index in 0, 1) {
            if ($open[$index] -and $tasks[$index].Wait(200)) {
                $text = $tasks[$index].Result
                if ($null -eq $text) {
                    $open[$index] = $false
                }
                else {
                    Write-TunnelLine -Text $text
                    $tasks[$index] = $readers[$index].ReadLineAsync()
                }
            }
        }
        if (Test-Path -LiteralPath $StopFile) {
            Write-TunnelLine -Text '[VoltaGoLive] Pedido de desativação recebido.'
            break
        }
    }
}
catch {
    Write-TunnelLine -Text ('[VoltaGoLive] Erro no processo do túnel: ' + $_.Exception.Message)
}
finally {
    if ($null -ne $process -and -not $process.HasExited) {
        try {
            $process.Kill()
            $null = $process.WaitForExit(5000)
        }
        catch {
            Write-TunnelLine -Text ('[VoltaGoLive] Não foi possível encerrar o wiresock-client: ' + $_.Exception.Message)
        }
    }
    Write-TunnelLine -Text '[VoltaGoLive] O wiresock-client encerrou.'
    $script:Writer.Dispose()
}
