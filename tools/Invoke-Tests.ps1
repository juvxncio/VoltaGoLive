<#
.SYNOPSIS
Roda os testes Pester 5 do projeto e falha se algum teste falhar.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Path $PSScriptRoot -Parent
Get-Module -Name Pester | Remove-Module -Force
Import-Module -Name Pester -MinimumVersion 5.5.0 -MaximumVersion 5.99.99

$configuration = New-PesterConfiguration
$configuration.Run.Path = Join-Path -Path $root -ChildPath 'tests'
$configuration.Run.Exit = $true
$configuration.Output.Verbosity = 'Detailed'
Invoke-Pester -Configuration $configuration
