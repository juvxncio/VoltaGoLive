<#
.SYNOPSIS
Monta o zip de distribuição, o arquivo SHA256SUMS e as notas da versão.

.DESCRIPTION
O zip contém só o que a pessoa precisa para usar: os lançadores .bat, a pasta scripts,
o módulo (src), a pasta config com as instruções, o README, a licença e o CHANGELOG.
Nenhum binário de terceiros entra no pacote.

.PARAMETER Tag
Tag da versão, no formato vX.Y.Z. Precisa ser igual à versão do manifesto do módulo.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^v\d+\.\d+\.\d+$')]
    [string]$Tag
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Path $PSScriptRoot -Parent
$manifest = Import-PowerShellDataFile -Path (Join-Path -Path $root -ChildPath 'src/VoltaGoLive/VoltaGoLive.psd1')
$version = $Tag.TrimStart('v')
if ($manifest.ModuleVersion -ne $version) {
    throw ('A tag {0} não bate com a versão do módulo ({1}).' -f $Tag, $manifest.ModuleVersion)
}

$changelog = Get-Content -LiteralPath (Join-Path -Path $root -ChildPath 'CHANGELOG.md') -Raw -Encoding UTF8
$pattern = '(?ms)^## \[' + [regex]::Escape($version) + '\][^\n]*\n(.*?)(?=^## \[|\z)'
$match = [regex]::Match($changelog, $pattern)
if (-not $match.Success) {
    throw ('O CHANGELOG não tem uma seção para a versão {0}.' -f $version)
}

$dist = Join-Path -Path $root -ChildPath 'dist'
if (Test-Path -LiteralPath $dist) {
    Remove-Item -LiteralPath $dist -Recurse -Force
}
$name = 'VoltaGoLive-' + $Tag
$stage = Join-Path -Path (Join-Path -Path $dist -ChildPath 'stage') -ChildPath $name
$null = New-Item -Path $stage -ItemType Directory -Force

$items = @(
    'VoltaGoLive.bat', 'Ativar.bat', 'Desativar.bat', 'Status.bat', 'Diagnostico.bat',
    'README.md', 'LICENSE', 'CHANGELOG.md', 'scripts', 'src', 'config'
)
foreach ($item in $items) {
    Copy-Item -Path (Join-Path -Path $root -ChildPath $item) -Destination $stage -Recurse -Force
}

# Garantia extra: nada de configuração ou chave dentro do pacote.
$forbidden = @(Get-ChildItem -Path $stage -Recurse -File | Where-Object { $_.Extension -in @('.conf', '.key', '.log', '.env') })
if ($forbidden.Count -gt 0) {
    throw 'Há arquivos que não podem ser distribuídos dentro do pacote.'
}

$zip = Join-Path -Path $dist -ChildPath ($name + '.zip')
Compress-Archive -Path $stage -DestinationPath $zip -CompressionLevel Optimal
Remove-Item -LiteralPath (Join-Path -Path $dist -ChildPath 'stage') -Recurse -Force

$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
$sums = '{0}  {1}' -f $hash, ($name + '.zip')
[System.IO.File]::WriteAllText((Join-Path -Path $dist -ChildPath 'SHA256SUMS'), $sums + "`n", (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false))

$notes = $match.Groups[1].Value.Trim() + "`n`n## Conferir o download`n`nSHA256 do arquivo ``$name.zip``:`n`n``````text`n$hash`n```````n"
[System.IO.File]::WriteAllText((Join-Path -Path $dist -ChildPath 'notas.md'), $notes, (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false))

Write-Output $sums
