<#
.SYNOPSIS
Verificações de higiene do repositório. Falha se alguma regra for quebrada.

.DESCRIPTION
Regras conferidas em todos os arquivos versionados (ou prontos para commit):
  1. Nenhum arquivo contém o nome do campo da chave privada do WireGuard por extenso.
  2. Nenhum arquivo contém travessão.
  3. Nenhum arquivo contém caminho absoluto de pasta pessoal de Linux.
  4. Nenhum arquivo .conf, .env, de log ou de diagnóstico está versionado.
  5. Arquivos PowerShell com acentos têm BOM (exigência do Windows PowerShell 5.1).
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Path $PSScriptRoot -Parent
Push-Location -Path $root
try {
    $files = @(& git ls-files --cached --others --exclude-standard)
}
finally {
    Pop-Location
}

# Os termos proibidos são montados em partes para este arquivo não reprovar a si mesmo.
$forbidden = @(
    @{ Name = 'campo da chave privada'; Pattern = 'Private' + 'Key' }
    @{ Name = 'travessão'; Pattern = [string][char]0x2014 }
    @{ Name = 'caminho absoluto de Linux'; Pattern = '(?<![\w.])/(?:ho' + 'me|ro' + 'ot)/\w' }
)
$blockedNames = '(?i)(\.conf$|(^|/)\.env|\.log$|(^|/)diagnostico-.*\.txt$)'
$failures = New-Object -TypeName 'System.Collections.Generic.List[string]'

foreach ($file in $files) {
    $full = Join-Path -Path $root -ChildPath $file
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        continue
    }
    if ($file -match $blockedNames) {
        $failures.Add("${file}: tipo de arquivo que não pode ser versionado")
        continue
    }

    $bytes = [System.IO.File]::ReadAllBytes($full)
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)

    foreach ($rule in $forbidden) {
        if ([regex]::IsMatch($text, $rule.Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            $failures.Add(('{0}: contém {1}' -f $file, $rule.Name))
        }
    }

    if ($file -match '\.(ps1|psm1|psd1)$') {
        $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        $hasNonAscii = @($bytes | Where-Object { $_ -gt 127 }).Count -gt 0
        if ($hasNonAscii -and -not $hasBom) {
            $failures.Add("${file}: tem acentos mas não tem BOM (o Windows PowerShell 5.1 leria errado)")
        }
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Output $_ }
    Write-Error -Message ('Verificação do repositório falhou: {0} problema(s).' -f $failures.Count)
    exit 1
}
Write-Output ('Verificação do repositório: {0} arquivos, nenhum problema.' -f $files.Count)
