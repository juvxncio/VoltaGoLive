BeforeDiscovery {
    # O InModuleScope precisa do módulo carregado já na fase de descoberta.
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/VoltaGoLive/VoltaGoLive.psd1') -Force
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers.ps1')
    Import-TestModule
}

InModuleScope VoltaGoLive {
    Describe 'ConvertFrom-VglConf' {
        BeforeAll {
            . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers.ps1')
        }

        It 'separa seções, entradas, comentários e linhas vazias' {
            $parsed = @(ConvertFrom-VglConf -Text (Get-TestConf))
            @($parsed | Where-Object { $_.Kind -eq 'Section' }).Count | Should -Be 2
            @($parsed | Where-Object { $_.Kind -eq 'Comment' }).Count | Should -Be 2
            @(Get-VglConfValue -Parsed $parsed -Section 'Peer' -Key 'Endpoint')[0] | Should -Be '203.0.113.77:51820'
        }

        It 'aceita chaves e seções sem diferenciar maiúsculas' {
            $parsed = @(ConvertFrom-VglConf -Text "[peer]`nendpoint=a.b:1")
            @(Get-VglConfValue -Parsed $parsed -Section 'Peer' -Key 'Endpoint')[0] | Should -Be 'a.b:1'
        }

        It 'entende linhas com o prefixo #@ws: como entradas' {
            $parsed = @(ConvertFrom-VglConf -Text "[Peer]`n#@ws:AllowedApps = chrome, firefox")
            @(Get-VglConfValue -Parsed $parsed -Section 'Peer' -Key 'AllowedApps')[0] | Should -Be 'chrome, firefox'
        }

        It 'ignora o BOM no começo do arquivo' {
            $parsed = @(ConvertFrom-VglConf -Text (([string][char]0xFEFF) + "[Interface]`nAddress = x"))
            $parsed[0].Kind | Should -Be 'Section'
            $parsed[0].Section | Should -Be 'Interface'
        }

        It 'aceita texto vazio' {
            @(ConvertFrom-VglConf -Text '').Count | Should -Be 1
        }
    }

    Describe 'Test-VglConf' {
        BeforeAll {
            . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers.ps1')
        }

        It 'aprova uma configuração no formato da Proton' {
            @(Test-VglConf -Text (Get-TestConf)).Count | Should -Be 0
            @(Test-VglConf -Text (Get-TestConf -WithIpv6)).Count | Should -Be 0
        }

        It 'reprova arquivo vazio ou que não é WireGuard' {
            @(Test-VglConf -Text '').Count | Should -BeGreaterThan 0
            @(Test-VglConf -Text "client`ndev tun`nremote 1.2.3.4 1194").Count | Should -BeGreaterThan 0
        }

        It 'reprova quando falta o campo <Field>' -ForEach @(
            @{ Field = 'Address'; Expected = 'Address' }
            @{ Field = 'PublicKey'; Expected = 'PublicKey' }
            @{ Field = 'Endpoint'; Expected = 'Endpoint' }
            @{ Field = 'AllowedIPs'; Expected = 'AllowedIPs' }
        ) {
            $text = ((Get-TestConf) -split "`r`n" | Where-Object { $_ -notmatch "^$Field\s*=" }) -join "`r`n"
            $problems = @(Test-VglConf -Text $text)
            $problems.Count | Should -Be 1
            $problems[0] | Should -Match $Expected
        }

        It 'reprova quando falta a chave privada' {
            $name = Get-TestKeyName
            $text = ((Get-TestConf) -split "`r`n" | Where-Object { $_ -notmatch "^$name" }) -join "`r`n"
            $problems = @(Test-VglConf -Text $text)
            $problems.Count | Should -Be 1
            $problems[0] | Should -Match 'chave privada'
        }

        It 'reprova chave privada cortada e não mostra o valor na mensagem' {
            $text = (Get-TestConf).Replace((Get-TestKey -Fill 'A'), 'CHAVECORTADA123')
            $problems = @(Test-VglConf -Text $text)
            $problems.Count | Should -Be 1
            $problems[0] | Should -Not -Match 'CHAVECORTADA123'
        }

        It 'reprova Endpoint sem porta' {
            $text = (Get-TestConf).Replace('203.0.113.77:51820', '203.0.113.77')
            @(Test-VglConf -Text $text)[0] | Should -Match 'servidor:porta'
        }
    }

    Describe 'ConvertTo-VglTunnelConf' {
        BeforeAll {
            . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers.ps1')
            $script:Apps = @('Discord.exe', 'DiscordPTB.exe', 'DiscordCanary.exe')
        }

        It 'insere uma única linha AllowedApps dentro de [Peer]' {
            $result = ConvertTo-VglTunnelConf -Text (Get-TestConf) -Apps $script:Apps
            $parsed = @(ConvertFrom-VglConf -Text $result)
            $values = @(Get-VglConfValue -Parsed $parsed -Section 'Peer' -Key 'AllowedApps')
            $values.Count | Should -Be 1
            $values[0] | Should -Be 'Discord.exe, DiscordPTB.exe, DiscordCanary.exe'
            @(Get-VglConfValue -Parsed $parsed -Section 'Interface' -Key 'AllowedApps').Count | Should -Be 0
        }

        It 'grava a diretiva sem o prefixo de comentário' {
            $result = ConvertTo-VglTunnelConf -Text (Get-TestConf) -Apps $script:Apps
            $result | Should -Match '(?m)^AllowedApps = Discord\.exe'
            $result | Should -Not -Match '#@ws:'
        }

        It 'substitui AllowedApps e DisallowedApps que já existiam' -ForEach @(
            @{ Extra = 'AllowedApps = chrome.exe' }
            @{ Extra = '#@ws:AllowedApps = chrome.exe' }
            @{ Extra = 'DisallowedApps = Discord.exe' }
            @{ Extra = "allowedapps=chrome.exe`r`n#@ws: DisallowedApps = Discord" }
        ) {
            $result = ConvertTo-VglTunnelConf -Text (Get-TestConf -Extra $Extra) -Apps $script:Apps
            $result | Should -Not -Match 'chrome'
            $result | Should -Not -Match 'DisallowedApps'
            ([regex]::Matches($result, '(?i)AllowedApps')).Count | Should -Be 1
        }

        It 'mantém todos os outros campos iguais ao original' {
            $original = Get-TestConf -WithIpv6
            $result = ConvertTo-VglTunnelConf -Text $original -Apps $script:Apps
            $withoutDirective = (($result -split "`r`n") | Where-Object { $_ -notmatch '^AllowedApps' }) -join "`r`n"
            $withoutDirective | Should -Be $original
        }

        It 'é idempotente' {
            $once = ConvertTo-VglTunnelConf -Text (Get-TestConf) -Apps $script:Apps
            $twice = ConvertTo-VglTunnelConf -Text $once -Apps $script:Apps
            $twice | Should -Be $once
        }

        It 'insere em cada [Peer] quando há mais de um' {
            $text = (Get-TestConf) + "`r`n[Peer]`r`nPublicKey = x`r`nEndpoint = h:1`r`nAllowedIPs = 10.0.0.0/8`r`n"
            $result = ConvertTo-VglTunnelConf -Text $text -Apps $script:Apps
            ([regex]::Matches($result, '(?m)^AllowedApps = ')).Count | Should -Be 2
        }

        It 'continua válido depois da injeção' {
            $result = ConvertTo-VglTunnelConf -Text (Get-TestConf) -Apps $script:Apps
            @(Test-VglConf -Text $result).Count | Should -Be 0
        }

        It 'não começa com BOM (o WireSock leria errado)' {
            $result = ConvertTo-VglTunnelConf -Text (([string][char]0xFEFF) + (Get-TestConf)) -Apps $script:Apps
            [int][char]$result[0] | Should -Be ([int][char]'[')
        }
    }

    Describe 'Get-VglConfSummary' {
        BeforeAll {
            . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers.ps1')
        }

        It 'descreve a estrutura sem revelar nenhum valor' {
            $summary = (Get-VglConfSummary -Text (Get-TestConf -WithIpv6)) -join "`n"
            $summary | Should -Match 'Interface, Peer'
            $summary | Should -Match 'IPv6 inteiro: True'
            $summary | Should -Not -Match 'AAAA'
            $summary | Should -Not -Match '203\.0\.113'
            $summary | Should -Not -Match '10\.2\.0'
        }
    }
}
