BeforeDiscovery {
    # O InModuleScope precisa do módulo carregado já na fase de descoberta.
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/VoltaGoLive/VoltaGoLive.psd1') -Force
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers.ps1')
    Import-TestModule

    function Invoke-Protect {
        param([string]$Text)
        $identity = Get-TestIdentity -User 'joao.silva' -Machine 'DESKTOP-ABC123' -Folder 'C:\Users\joao.silva'
        Protect-VoltaGoLiveText -Text $Text @identity
    }
}

Describe 'Protect-VoltaGoLiveText' {
    Context 'chaves' {
        It 'esconde o valor da chave privada' {
            $line = (Get-TestKeyName) + ' = ' + (Get-TestKey -Fill 'A')
            $result = Invoke-Protect -Text $line
            $result | Should -Be ((Get-TestKeyName) + ' = <REDIGIDO>')
        }

        It 'esconde a chave privada mesmo em formato inesperado' {
            $result = Invoke-Protect -Text ((Get-TestKeyName).ToLower() + ':   qualquer coisa aqui')
            $result | Should -Not -Match 'qualquer'
        }

        It 'esconde a chave pré-compartilhada' {
            $result = Invoke-Protect -Text ('PresharedKey = ' + (Get-TestKey -Fill 'C'))
            $result | Should -Be 'PresharedKey = <REDIGIDO>'
        }

        It 'esconde qualquer chave solta no texto' {
            $result = Invoke-Protect -Text ('peer ' + (Get-TestKey -Fill 'B') + ' conectado')
            $result | Should -Be 'peer <CHAVE> conectado'
        }
    }

    Context 'endereços IP' {
        It 'esconde o IP público e o endereço do túnel' {
            Invoke-Protect -Text 'Endpoint = 203.0.113.77:51820' | Should -Be 'Endpoint = <IP>:51820'
            Invoke-Protect -Text 'Address = 10.2.0.2/32' | Should -Be 'Address = <IP>/32'
            Invoke-Protect -Text 'DNS = 10.2.0.1, 1.1.1.1' | Should -Be 'DNS = <IP>, <IP>'
        }

        It 'mantém 0.0.0.0/0 e o loopback, que não identificam ninguém' {
            Invoke-Protect -Text 'AllowedIPs = 0.0.0.0/0, ::/0' | Should -Be 'AllowedIPs = 0.0.0.0/0, ::/0'
            Invoke-Protect -Text 'escutando em 127.0.0.1:8080' | Should -Be 'escutando em 127.0.0.1:8080'
        }

        It 'esconde IPv6 <Address>' -ForEach @(
            @{ Address = '2001:0db8:85a3:0000:0000:8a2e:0370:7334' }
            @{ Address = '2a07:b944::2:2' }
            @{ Address = 'fe80::1' }
            @{ Address = '2001:db8::' }
            @{ Address = '::1' }
        ) {
            Invoke-Protect -Text "origem $Address fim" | Should -Be 'origem <IP> fim'
        }

        It 'não confunde horário com IPv6' {
            Invoke-Protect -Text '2026-01-02T12:34:56 | ok' | Should -Be '2026-01-02T12:34:56 | ok'
        }
    }

    Context 'dados pessoais' {
        It 'troca a pasta do perfil por %USERPROFILE%' {
            Invoke-Protect -Text 'C:\Users\joao.silva\AppData\Local\Discord\Update.exe' |
                Should -Be '%USERPROFILE%\AppData\Local\Discord\Update.exe'
        }

        It 'troca a pasta do perfil escrita com barras normais ou em minúsculas' {
            Invoke-Protect -Text 'c:/users/JOAO.SILVA/Downloads/x.txt' | Should -Be '%USERPROFILE%/Downloads/x.txt'
        }

        It 'troca a pasta de perfil de outro usuário' {
            Invoke-Protect -Text 'D:\Users\maria\x' | Should -Be '%USERPROFILE%\x'
        }

        It 'troca a pasta do perfil quando o nome tem espaço' {
            $identity = Get-TestIdentity -User 'Ana Souza' -Machine 'PC1' -Folder 'C:\Users\Ana Souza'
            $result = Protect-VoltaGoLiveText -Text 'C:\Users\Ana Souza\AppData' @identity
            $result | Should -Be '%USERPROFILE%\AppData'
        }

        It 'esconde o nome do usuário e o nome do computador' {
            Invoke-Protect -Text 'usuario joao.silva em DESKTOP-ABC123\joao.silva' | Should -Be 'usuario <USUARIO> em <PC>\<USUARIO>'
            Invoke-Protect -Text 'host desktop-abc123 respondeu' | Should -Be 'host <PC> respondeu'
        }

        It 'não mexe em palavras que só contêm o nome' {
            $identity = Get-TestIdentity -User 'ana' -Machine 'PC1' -Folder 'C:\Users\ana'
            $result = Protect-VoltaGoLiveText -Text 'anabela e banana' @identity
            $result | Should -Be 'anabela e banana'
        }

        It 'funciona quando usuário, computador e perfil não são informados' {
            $identity = Get-TestIdentity -User '' -Machine '' -Folder ''
            Protect-VoltaGoLiveText -Text 'texto simples' @identity | Should -Be 'texto simples'
        }
    }

    Context 'texto completo' {
        It 'não deixa passar nada sensível de um .conf inteiro' {
            $conf = Get-TestConf -WithIpv6 -Extra ('PresharedKey = ' + (Get-TestKey -Fill 'C'))
            $result = Invoke-Protect -Text $conf
            $result | Should -Not -Match 'A{10}'
            $result | Should -Not -Match 'B{10}'
            $result | Should -Not -Match 'C{10}'
            $result | Should -Not -Match '203\.0\.113'
            $result | Should -Not -Match '10\.2\.0'
            $result | Should -Match '\[Interface\]'
        }

        It 'aceita entrada pelo pipeline, linha por linha' {
            $identity = Get-TestIdentity -User '' -Machine '' -Folder ''
            $result = @('a 8.8.8.8', 'b') | Protect-VoltaGoLiveText @identity
            $result | Should -Be @('a <IP>', 'b')
        }

        It 'aceita texto vazio' {
            Invoke-Protect -Text '' | Should -Be ''
        }
    }
}

InModuleScope VoltaGoLive {
    Describe 'Write-VglLog' {
        BeforeAll {
            . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers.ps1')
        }

        It 'grava no arquivo somente texto redigido' {
            $log = Join-Path -Path $TestDrive -ChildPath 'logs/teste.log'
            $secret = (Get-TestKeyName) + ' = ' + (Get-TestKey -Fill 'Z')
            Write-VglLog -Message "servidor 198.51.100.9 com $secret" -Path $log
            $content = Get-Content -LiteralPath $log -Raw
            $content | Should -Match '<REDIGIDO>'
            $content | Should -Match '<IP>'
            $content | Should -Not -Match 'Z{10}'
            $content | Should -Not -Match '198\.51\.100\.9'
        }

        It 'não interrompe a operação quando o log não pode ser gravado' {
            $folderAsFile = Join-Path -Path $TestDrive -ChildPath 'bloqueado'
            Set-Content -LiteralPath $folderAsFile -Value 'x'
            { Write-VglLog -Message 'teste' -Path (Join-Path -Path $folderAsFile -ChildPath 'a.log') } | Should -Not -Throw
        }

        It 'relê o fim do log passando pela redação outra vez' {
            $log = Join-Path -Path $TestDrive -ChildPath 'cru.log'
            Set-Content -LiteralPath $log -Value @('linha 1', 'vazou 192.0.2.44')
            $tail = @(Get-VglLogTail -Path $log -Count 5)
            $tail[1] | Should -Be 'vazou <IP>'
            @(Get-VglLogTail -Path (Join-Path -Path $TestDrive -ChildPath 'nao-existe.log')).Count | Should -Be 0
        }
    }
}
