# Funções de apoio aos testes. As configurações de exemplo são montadas em tempo de
# execução, com chaves falsas, para que nenhum arquivo versionado contenha o nome do
# campo da chave privada nem algo parecido com uma chave real.

function Get-TestKeyName {
    return ('Private' + 'Key')
}

function Get-TestKey {
    param([char]$Fill = 'A')
    return (([string]$Fill) * 43) + '='
}

function Get-TestConf {
    param(
        [string]$Extra = '',
        [switch]$WithIpv6
    )

    $allowed = '0.0.0.0/0'
    if ($WithIpv6) {
        $allowed = '0.0.0.0/0, ::/0'
    }
    $lines = @(
        '[Interface]'
        '# Key for teste'
        ((Get-TestKeyName) + ' = ' + (Get-TestKey -Fill 'A'))
        'Address = 10.2.0.2/32'
        'DNS = 10.2.0.1'
        ''
        '[Peer]'
        '# NL-FREE#1'
        ('PublicKey = ' + (Get-TestKey -Fill 'B'))
        "AllowedIPs = $allowed"
        'Endpoint = 203.0.113.77:51820'
    )
    if ($Extra -ne '') {
        $lines += $Extra
    }
    return ($lines -join "`r`n") + "`r`n"
}

function Import-TestModule {
    $manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/VoltaGoLive/VoltaGoLive.psd1'
    Import-Module -Name $manifest -Force
}

function Get-TestIdentity {
    # Identidade falsa para os testes de redação (evita nomes de computador fixos nas chamadas).
    param([string]$User, [string]$Machine, [string]$Folder)
    return @{ UserName = $User; ComputerName = $Machine; UserProfile = $Folder }
}
