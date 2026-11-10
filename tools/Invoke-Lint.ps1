<#
.SYNOPSIS
Roda o PSScriptAnalyzer no projeto inteiro e falha se houver qualquer aviso.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name PSScriptAnalyzer

$findings = @(Invoke-ScriptAnalyzer -Path $root -Recurse -Settings (Join-Path -Path $root -ChildPath 'PSScriptAnalyzerSettings.psd1'))
foreach ($finding in $findings) {
    $relative = $finding.ScriptPath.Substring($root.Length).TrimStart('\', '/')
    Write-Output ('{0}:{1} [{2}] {3}: {4}' -f $relative, $finding.Line, $finding.Severity, $finding.RuleName, $finding.Message)
}

if ($findings.Count -gt 0) {
    Write-Error -Message ('PSScriptAnalyzer encontrou {0} problema(s).' -f $findings.Count)
    exit 1
}
Write-Output 'PSScriptAnalyzer: nenhum aviso.'
