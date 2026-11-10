<#
.SYNOPSIS
Processo oculto que mantém o túnel do VoltaGoLive aberto.

.DESCRIPTION
Executa o wiresock-client com a configuração informada e grava a saída dele no log do
túnel, uma linha por vez, sempre redigida (sem chaves, IPs, usuário ou nome do computador).
Quando o log passa do tamanho máximo, o arquivo atual vira ".1" e um novo começa.

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

    [string]$LogLevel = 'debug',

    [long]$MaxBytes = 2097152
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'VoltaGoLive.psd1') -Force

$folder = Split-Path -Path $LogPath -Parent
if (-not (Test-Path -LiteralPath $folder)) {
    $null = New-Item -Path $folder -ItemType Directory -Force
}

$encoding = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
$script:written = 0L

function Open-LogWriter {
    $stream = New-Object -TypeName System.IO.FileStream -ArgumentList @(
        $LogPath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
    $writer = New-Object -TypeName System.IO.StreamWriter -ArgumentList @($stream, $encoding)
    $writer.AutoFlush = $true
    $script:written = $stream.Length
    return $writer
}

$writer = Open-LogWriter
try {
    # A saída de erro de programas nativos vira registro de erro no PowerShell 5.1.
    # Aqui ela é só texto de log, então não pode interromper o túnel.
    $ErrorActionPreference = 'Continue'
    & $ExePath run -config $ConfigPath -log-level $LogLevel 2>&1 | ForEach-Object {
        $text = Protect-VoltaGoLiveText -Text ([string]$_)
        $line = '{0} | {1}' -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'), $text
        $writer.WriteLine($line)
        $script:written += $line.Length + 2
        if ($script:written -gt $MaxBytes) {
            $writer.Dispose()
            Move-Item -LiteralPath $LogPath -Destination ($LogPath + '.1') -Force
            $writer = Open-LogWriter
        }
    }
    $writer.WriteLine(('{0} | [VoltaGoLive] O wiresock-client encerrou.' -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')))
}
finally {
    $writer.Dispose()
}
