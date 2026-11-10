BeforeDiscovery {
    # O InModuleScope precisa do módulo carregado já na fase de descoberta.
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/VoltaGoLive/VoltaGoLive.psd1') -Force
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers.ps1')
    Import-TestModule
}

InModuleScope VoltaGoLive {
    Describe 'Get-VglHandshakeInfo' {
        It 'não confirma com log vazio ou sem handshake' {
            (Get-VglHandshakeInfo -Line @()).Confirmed | Should -BeFalse
            (Get-VglHandshakeInfo -Line @('2026-01-02T10:00:00 | Sending handshake_initiation')).Confirmed | Should -BeFalse
        }

        It 'confirma com a linha "<Text>"' -ForEach @(
            @{ Text = '[TUN]: Received handshake_response' }
            @{ Text = 'Received handshake response from peer' }
            @{ Text = 'Handshake completed' }
            @{ Text = 'New session: 123456' }
            @{ Text = 'keypair 1 created for peer 1' }
        ) {
            (Get-VglHandshakeInfo -Line @("2026-01-02T10:00:00 | $Text")).Confirmed | Should -BeTrue
        }

        It 'devolve o horário da última confirmação' {
            $lines = @(
                '2026-01-02T10:00:00 | Received handshake_response'
                '2026-01-02T10:00:05 | outra coisa'
                '2026-01-02T10:02:07 | Received handshake_response'
                '2026-01-02T10:02:09 | Sending keepalive'
            )
            $info = Get-VglHandshakeInfo -Line $lines
            $info.Confirmed | Should -BeTrue
            $info.Time | Should -Be ([datetime]'2026-01-02T10:02:07')
        }

        It 'confirma mesmo sem horário no começo da linha' {
            $info = Get-VglHandshakeInfo -Line @('Received handshake_response')
            $info.Confirmed | Should -BeTrue
            $info.Time | Should -BeNullOrEmpty
        }
    }

    Describe 'Wait-VglHandshake' {
        BeforeEach {
            Mock Start-Sleep { }
        }

        It 'confirma assim que a linha aparece no log' {
            $log = Join-Path -Path $TestDrive -ChildPath 'ok.log'
            Set-Content -LiteralPath $log -Value '2026-01-02T10:00:00 | Received handshake_response'
            (Wait-VglHandshake -LogPath $log -TimeoutSeconds 5).Confirmed | Should -BeTrue
        }

        It 'desiste depois do tempo limite' {
            $log = Join-Path -Path $TestDrive -ChildPath 'nada.log'
            Set-Content -LiteralPath $log -Value '2026-01-02T10:00:00 | iniciando'
            (Wait-VglHandshake -LogPath $log -TimeoutSeconds 0).Confirmed | Should -BeFalse
            (Wait-VglHandshake -LogPath (Join-Path -Path $TestDrive -ChildPath 'sem-arquivo.log') -TimeoutSeconds 0).Confirmed | Should -BeFalse
        }
    }

    Describe 'Find-VglWireSock' {
        It 'encontra o executável dentro de uma pasta WireSock*' {
            $root = Join-Path -Path $TestDrive -ChildPath 'pf'
            $bin = Join-Path -Path (Join-Path -Path $root -ChildPath 'WireSock Secure Connect') -ChildPath 'bin'
            $null = New-Item -Path $bin -ItemType Directory -Force
            Set-Content -LiteralPath (Join-Path -Path $bin -ChildPath 'wiresock-client.exe') -Value 'x'
            $found = Find-VglWireSock -SearchRoot @($root)
            Split-Path -Path $found -Leaf | Should -Be 'wiresock-client.exe'
        }

        It 'devolve nulo quando não está instalado ou a pasta não existe' {
            $root = Join-Path -Path $TestDrive -ChildPath 'pf-vazio'
            $null = New-Item -Path (Join-Path -Path $root -ChildPath 'Outro Programa') -ItemType Directory -Force
            Set-Content -LiteralPath (Join-Path -Path (Join-Path -Path $root -ChildPath 'Outro Programa') -ChildPath 'wiresock-client.exe') -Value 'x'
            Find-VglWireSock -SearchRoot @($root) | Should -BeNullOrEmpty
            Find-VglWireSock -SearchRoot @((Join-Path -Path $TestDrive -ChildPath 'nao-existe')) | Should -BeNullOrEmpty
        }
    }

    Describe 'Test-VglSignature' {
        It 'reprova assinatura <Status>' -ForEach @(
            @{ Status = 'NotSigned' }
            @{ Status = 'HashMismatch' }
            @{ Status = 'NotTrusted' }
            @{ Status = 'UnknownError' }
        ) {
            $signature = [pscustomobject]@{ Status = $Status; Subject = 'CN=Editora Certa' }
            Test-VglSignature -Signature $signature -ExpectedSigner 'Editora Certa' | Should -BeFalse
        }

        It 'aprova assinatura válida do publicador esperado' {
            $signature = [pscustomobject]@{ Status = 'Valid'; Subject = 'CN=Editora Certa, O=Editora Certa, L=Cidade, C=XX' }
            Test-VglSignature -Signature $signature -ExpectedSigner 'Editora Certa' | Should -BeTrue
            Test-VglSignature -Signature $signature -ExpectedSigner 'editora certa' | Should -BeTrue
        }

        It 'aprova quando o nome vem entre aspas no certificado' {
            $signature = [pscustomobject]@{ Status = 'Valid'; Subject = 'CN="Editora Certa", C=XX' }
            Test-VglSignature -Signature $signature -ExpectedSigner 'Editora Certa' | Should -BeTrue
        }

        It 'reprova assinatura válida de outro publicador' {
            $signature = [pscustomobject]@{ Status = 'Valid'; Subject = 'CN=Editora Certa Falsa, C=XX' }
            Test-VglSignature -Signature $signature -ExpectedSigner 'Editora Certa' | Should -BeFalse
            $other = [pscustomobject]@{ Status = 'Valid'; Subject = 'CN=Outra, OU=Editora Certa, C=XX' }
            Test-VglSignature -Signature $other -ExpectedSigner 'Editora Certa' | Should -BeFalse
        }

        It 'sem publicador esperado, exige apenas assinatura válida' {
            Test-VglSignature -Signature ([pscustomobject]@{ Status = 'Valid'; Subject = 'CN=X' }) -ExpectedSigner '' | Should -BeTrue
            Test-VglSignature -Signature ([pscustomobject]@{ Status = 'NotSigned'; Subject = '' }) -ExpectedSigner '' | Should -BeFalse
        }
    }

    Describe 'Stop-VglTunnel' {
        BeforeEach {
            Mock Start-Sleep { }
            Mock Stop-Process { }
            $script:Paths = @{
                RuntimeConf = Join-Path -Path $TestDrive -ChildPath 'x.conf'
                StopFile    = Join-Path -Path $TestDrive -ChildPath 'sinal/parar-tunel.txt'
            }
        }

        It 'pede a parada pelo arquivo de sinal, sem precisar de administrador' {
            $script:Calls = 0
            $script:SignalSeen = $false
            Mock Get-VglTunnelProcess {
                $script:Calls++
                if (Test-Path -LiteralPath $script:Paths.StopFile) {
                    $script:SignalSeen = $true
                }
                if ($script:Calls -le 2) {
                    return @([pscustomobject]@{ ProcessId = 200; Name = 'wiresock-client.exe'; IsWireSock = $true })
                }
                return @()
            }
            Stop-VglTunnel -Paths $script:Paths | Should -Be 1
            $script:SignalSeen | Should -BeTrue
            Should -Invoke Stop-Process -Times 0
            Test-Path -LiteralPath $script:Paths.StopFile | Should -BeFalse
        }

        It 'explica o que fazer quando o WireSock não encerra' {
            Mock Get-VglTunnelProcess {
                return @([pscustomobject]@{ ProcessId = 200; Name = 'wiresock-client.exe'; IsWireSock = $true })
            }
            { Stop-VglTunnel -Paths $script:Paths -TimeoutSeconds 0 } | Should -Throw '*Reinicie o computador*'
            Should -Invoke Stop-Process -Times 1 -Exactly -ParameterFilter { $Id -eq 200 }
        }

        It 'devolve zero quando não há túnel' {
            Mock Get-VglTunnelProcess { return @() }
            Stop-VglTunnel -Paths $script:Paths | Should -Be 0
            Test-Path -LiteralPath $script:Paths.StopFile | Should -BeFalse
        }
    }

    Describe 'Start-VglTunnel' {
        BeforeEach {
            Mock Start-Sleep { }
            Mock Write-VglMessage { }
            Mock Test-VglAdministrator { return $false }
            $script:Paths = @{
                RuntimeConf = Join-Path -Path $TestDrive -ChildPath 'r.conf'
                TunnelLog   = Join-Path -Path $TestDrive -ChildPath 'tunel.log'
                StopFile    = Join-Path -Path $TestDrive -ChildPath 'parar-tunel.txt'
                TunnelHost  = Join-Path -Path $TestDrive -ChildPath 'TunnelHost.ps1'
            }
        }

        It 'inicia o processo do túnel como administrador e avisa a pessoa antes' {
            Mock Start-Process { }
            Mock Get-VglTunnelProcess { return @([pscustomobject]@{ ProcessId = 1; Name = 'wiresock-client.exe'; IsWireSock = $true }) }
            Set-Content -LiteralPath $script:Paths.StopFile -Value 'velho'
            Start-VglTunnel -ExePath 'wiresock-client.exe' -Paths $script:Paths
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
                $Verb -eq 'RunAs' -and $ArgumentList -like '*TunnelHost.ps1*' -and $ArgumentList -like '*-StopFile*'
            }
            Should -Invoke Write-VglMessage -ParameterFilter { $Message -like '*permissão de administrador*' }
            Test-Path -LiteralPath $script:Paths.StopFile | Should -BeFalse
        }

        It 'explica o que fazer quando a permissão de administrador é recusada' {
            Mock Start-Process { throw 'The operation was canceled by the user.' }
            Mock Get-VglTunnelProcess { return @() }
            { Start-VglTunnel -ExePath 'wiresock-client.exe' -Paths $script:Paths } | Should -Throw '*permissão de administrador não foi concedida*O que fazer:*'
        }

        It 'orienta a reiniciar quando o driver do WireSock não responde' {
            Mock Start-Process { }
            Mock Get-VglTunnelProcess { return @() }
            Set-Content -LiteralPath $script:Paths.RuntimeConf -Value 'x'
            Mock Get-VglLogTail { return 'x | Failed to run WireSock service: Windows Packet Filter driver is not available!' }
            { Start-VglTunnel -ExePath 'wiresock-client.exe' -Paths $script:Paths } | Should -Throw '*Reinicie o computador*'
        }
    }

    Describe 'Get-VglTunnelProcess' {
        It 'não considera túnel nosso quando a cópia do .conf não existe' {
            $paths = @{ RuntimeConf = Join-Path -Path $TestDrive -ChildPath 'nao-existe.conf' }
            @(Get-VglTunnelProcess -Paths $paths).Count | Should -Be 0
        }

        It 'procura o wiresock-client pelo nome quando a cópia existe' {
            $paths = @{ RuntimeConf = Join-Path -Path $TestDrive -ChildPath 'existe.conf' }
            Set-Content -LiteralPath $paths.RuntimeConf -Value 'x'
            Mock Get-Process { return @([pscustomobject]@{ Id = 77 }) } -ParameterFilter { $Name -eq 'wiresock-client' }
            $found = @(Get-VglTunnelProcess -Paths $paths)
            $found.Count | Should -Be 1
            $found[0].ProcessId | Should -Be 77
        }
    }

    Describe 'Test-VglLogNoise' {
        It 'descarta a linha que lista programas do computador: <Line>' -ForEach @(
            @{ Line = '{"log_level":"debug","message":"Resolved TCPv4 owner: pid=20200 tag=0 name=\"firefox.exe\" path=\"C:\\\\x\\\\firefox.exe\""}' }
            @{ Line = '{"log_level":"debug","message":"Resolved UDPv6 owner: pid=9288 tag=0 name=\"Jogo.exe\""}' }
            @{ Line = '{"log_level":"debug","message":"Failed to resolve UDPv4 owner: pid=9508 tag=0 error=module_not_found"}' }
            @{ Line = '{"log_level":"debug","message":"TCPv4 entry with system process PID = 0 (Idle) skipping resolution"}' }
            @{ Line = '{"log_level":"debug","message":"Successfully removed filter(s) with ID: 3 from driver"}' }
            @{ Line = '{"log_level":"debug","message":"Removing filter with ID: 3 from internal list at position: 0"}' }
        ) {
            Test-VglLogNoise -Line $Line | Should -BeTrue
        }

        It 'mantém a linha útil: <Line>' -ForEach @(
            @{ Line = '{"log_level":"info","message":"[TUN]: force_handshake: Handshake initiation sent to WireGuard server"}' }
            @{ Line = '{"log_level":"info","message":"[MGR]: Tunnel has started"}' }
            @{ Line = 'Failed to run WireSock service: Windows Packet Filter driver is not available!' }
            @{ Line = '{"log_level":"debug","message":"[FILTER]: DISCORD.EXE : TCP : a -> b"}' }
            @{ Line = '' }
        ) {
            Test-VglLogNoise -Line $Line | Should -BeFalse
        }
    }

    Describe 'Estado e arquivos temporários' {
        It 'grava e lê o estado' {
            $file = Join-Path -Path $TestDrive -ChildPath 'dados/estado.json'
            $when = [datetime]'2026-03-04T05:06:07'
            Save-VglState -Path $file -StartedAt $when -Channels @('Stable')
            $state = Read-VglState -Path $file
            ([datetime]$state.StartedAt) | Should -Be $when
            @($state.Channels) | Should -Be @('Stable')
        }

        It 'devolve nulo para estado inexistente ou corrompido' {
            Read-VglState -Path (Join-Path -Path $TestDrive -ChildPath 'nada.json') | Should -BeNullOrEmpty
            $broken = Join-Path -Path $TestDrive -ChildPath 'quebrado.json'
            Set-Content -LiteralPath $broken -Value '{ isto nao e json'
            Read-VglState -Path $broken | Should -BeNullOrEmpty
        }

        It 'apaga a cópia do .conf, o estado e a pasta temporária' {
            $runtime = Join-Path -Path $TestDrive -ChildPath 'limpar/runtime'
            $null = New-Item -Path $runtime -ItemType Directory -Force
            $paths = @{
                RuntimeDir  = $runtime
                RuntimeConf = Join-Path -Path $runtime -ChildPath 'voltagolive.conf'
                StateFile   = Join-Path -Path $TestDrive -ChildPath 'limpar/estado.json'
            }
            Set-Content -LiteralPath $paths.RuntimeConf -Value 'x'
            Set-Content -LiteralPath $paths.StateFile -Value '{}'
            Clear-VglRuntime -Paths $paths
            Test-Path -LiteralPath $paths.RuntimeConf | Should -BeFalse
            Test-Path -LiteralPath $paths.StateFile | Should -BeFalse
            Test-Path -LiteralPath $runtime | Should -BeFalse
            { Clear-VglRuntime -Paths $paths } | Should -Not -Throw
        }
    }

    Describe 'Find-VglUserConf' {
        It 'usa o único .conf da pasta config' {
            $dir = Join-Path -Path $TestDrive -ChildPath 'cfg1'
            $null = New-Item -Path $dir -ItemType Directory -Force
            Set-Content -LiteralPath (Join-Path -Path $dir -ChildPath 'proton.conf') -Value 'x'
            Set-Content -LiteralPath (Join-Path -Path $dir -ChildPath 'LEIA-ME.txt') -Value 'x'
            Split-Path -Path (Find-VglUserConf -ConfigPath '' -ConfigDir $dir) -Leaf | Should -Be 'proton.conf'
        }

        It 'explica o que fazer quando não há .conf' {
            $dir = Join-Path -Path $TestDrive -ChildPath 'cfg0'
            $null = New-Item -Path $dir -ItemType Directory -Force
            { Find-VglUserConf -ConfigPath '' -ConfigDir $dir } | Should -Throw '*O que fazer:*Proton*'
        }

        It 'explica o que fazer quando há mais de um .conf' {
            $dir = Join-Path -Path $TestDrive -ChildPath 'cfg2'
            $null = New-Item -Path $dir -ItemType Directory -Force
            Set-Content -LiteralPath (Join-Path -Path $dir -ChildPath 'a.conf') -Value 'x'
            Set-Content -LiteralPath (Join-Path -Path $dir -ChildPath 'b.conf') -Value 'x'
            { Find-VglUserConf -ConfigPath '' -ConfigDir $dir } | Should -Throw '*só um arquivo*'
        }

        It 'aceita um caminho informado e reclama se ele não existir' {
            $file = Join-Path -Path $TestDrive -ChildPath 'meu.conf'
            Set-Content -LiteralPath $file -Value 'x'
            Split-Path -Path (Find-VglUserConf -ConfigPath $file -ConfigDir $TestDrive) -Leaf | Should -Be 'meu.conf'
            { Find-VglUserConf -ConfigPath (Join-Path -Path $TestDrive -ChildPath 'sumiu.conf') -ConfigDir $TestDrive } | Should -Throw '*Não encontrei*'
        }
    }

    Describe 'Format-VglVersion' {
        BeforeAll {
            . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers.ps1')
        }

        It 'escreve a versão de um jeito que a redação não confunde com IP' {
            $formatted = Format-VglVersion -Version '3.8.2.1'
            $formatted | Should -Be '3-8-2-1'
            $identity = Get-TestIdentity -User '' -Machine '' -Folder ''
            Protect-VoltaGoLiveText -Text "Versão: $formatted" @identity | Should -Be 'Versão: 3-8-2-1'
            Format-VglVersion -Version $null | Should -Be 'desconhecida'
        }
    }
}
