<#
.SYNOPSIS
Garante o BOM UTF-8 nos arquivos PowerShell do projeto que têm acentos.

.DESCRIPTION
O Windows PowerShell 5.1 lê arquivos sem BOM como ANSI e estraga os acentos das mensagens.
Rode este script depois de criar ou editar arquivos .ps1, .psm1 ou .psd1.
#>
[CmdletBinding(SupportsShouldProcess)]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Path $PSScriptRoot -Parent
$files = Get-ChildItem -Path $root -Recurse -File -Include '*.ps1', '*.psm1', '*.psd1'

foreach ($file in $files) {
    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $hasNonAscii = @($bytes | Where-Object { $_ -gt 127 }).Count -gt 0
    if ($hasNonAscii -and -not $hasBom -and $PSCmdlet.ShouldProcess($file.Name, 'Adicionar BOM')) {
        [System.IO.File]::WriteAllBytes($file.FullName, ([byte[]](0xEF, 0xBB, 0xBF) + $bytes))
        Write-Output ('BOM adicionado: ' + $file.Name)
    }
}
