BeforeDiscovery {
    # O InModuleScope precisa do módulo carregado já na fase de descoberta.
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/VoltaGoLive/VoltaGoLive.psd1') -Force
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers.ps1')
    Import-TestModule
}

# Fluxo completo com tudo que depende de Windows, rede ou administrador simulado.
# Estes testes provam a ORDEM e as GARANTIAS do fluxo, não que o túnel funciona de verdade.
InModuleScope VoltaGoLive {
    Describe 'Fluxo de ativação, desativação, status e diagnóstico' {
        BeforeAll {
            . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers.ps1')
        }

        BeforeEach {
            $base = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
            $data = Join-Path -Path $base -ChildPath 'dados'
            $script:TestPaths = @{
                Root          = $base
                ConfigDir     = Join-Path -Path $base -ChildPath 'config'
                LocalAppData  = $base
                DataDir       = $data
                LogDir        = Join-Path -Path $data -ChildPath 'logs'
                LogFile       = Join-Path -Path $data -ChildPath 'logs/voltagolive.log'
                TunnelLog     = Join-Path -Path $data -ChildPath 'logs/tunel.log'
                RuntimeDir    = Join-Path -Path $data -ChildPath 'runtime'
                RuntimeConf   = Join-Path -Path $data -ChildPath 'runtime/voltagolive.conf'
                StateFile     = Join-Path -Path $data -ChildPath 'estado.json'
                DiagnosticDir = Join-Path -Path $data -ChildPath 'diagnostico'
                TunnelHost    = Join-Path -Path $base -ChildPath 'TunnelHost.ps1'
            }
            $null = New-Item -Path $script:TestPaths.ConfigDir -ItemType Directory -Force
            $null = New-Item -Path $script:TestPaths.LogDir -ItemType Directory -Force
            $script:UserConf = Join-Path -Path $script:TestPaths.ConfigDir -ChildPath 'proton.conf'
            $script:Original = Get-TestConf -WithIpv6
            [System.IO.File]::WriteAllText($script:UserConf, $script:Original)
            $script:FakeExe = Join-Path -Path $base -ChildPath 'wiresock-client.exe'
            Set-Content -LiteralPath $script:FakeExe -Value 'x'
            $script:Order = New-Object -TypeName 'System.Collections.Generic.List[string]'
            $script:TunnelUp = $false

            Mock Assert-VglWindows { }
            Mock Get-VglPath { return $script:TestPaths }
            Mock Write-VglMessage { }
            Mock Start-Sleep { }
            Mock Find-VglWireSock { return $script:FakeExe }
            Mock Get-VglSignature { return [pscustomobject]@{ Status = 'Valid'; Subject = 'CN=Publicador' } }
            Mock Test-VglAdministrator { return $false }
            Mock Get-VglDiscordProcess { return @() }
            Mock Stop-VglDiscord { $script:Order.Add('fechar-discord'); return 'Stable' }
            Mock Start-VglDiscord { $script:Order.Add('abrir-discord'); return 'Stable' }
            Mock Start-VglTunnel {
                $script:Order.Add('subir-tunel')
                $script:TunnelUp = $true
                $script:ConfAtStart = Get-Content -LiteralPath $script:TestPaths.RuntimeConf -Raw
            }
            Mock Stop-VglTunnel {
                $script:Order.Add('derrubar-tunel')
                $was = $script:TunnelUp
                $script:TunnelUp = $false
                if ($was) { return 2 }
                return 0
            }
            Mock Get-VglTunnelProcess {
                if ($script:TunnelUp) {
                    return @([pscustomobject]@{ ProcessId = 4242; Name = 'wiresock-client.exe'; IsWireSock = $true })
                }
                return @()
            }
            Mock Wait-VglHandshake {
                $script:Order.Add('esperar-handshake')
                return [pscustomobject]@{ Confirmed = $true; Time = (Get-Date) }
            }
        }

        Context 'Enable-VoltaGoLive' {
            It 'segue a ordem: fechar Discord, subir túnel, abrir Discord, esperar handshake' {
                $null = Enable-VoltaGoLive
                ($script:Order -join ' > ') | Should -Be 'derrubar-tunel > fechar-discord > subir-tunel > abrir-discord > esperar-handshake'
            }

            It 'nunca altera o .conf original do usuário' {
                $null = Enable-VoltaGoLive
                [System.IO.File]::ReadAllText($script:UserConf) | Should -BeExactly $script:Original
            }

            It 'sobe o túnel com uma cópia que restringe o túnel ao Discord' {
                $null = Enable-VoltaGoLive
                $script:ConfAtStart | Should -Match '(?m)^AllowedApps = Discord\.exe, DiscordPTB\.exe, DiscordCanary\.exe\r?$'
                $script:TestPaths.RuntimeConf | Should -Not -Be $script:UserConf
            }

            It 'devolve o estado ativo e grava o horário da ativação' {
                $status = Enable-VoltaGoLive
                $status.Active | Should -BeTrue
                $status.StartedAt | Should -Not -BeNullOrEmpty
                Test-Path -LiteralPath $script:TestPaths.StateFile | Should -BeTrue
            }

            It 'para sem mexer em nada quando o WireSock não está instalado' {
                Mock Find-VglWireSock { return $null }
                { Enable-VoltaGoLive } | Should -Throw '*WireSock não está instalado*O que fazer:*'
                $script:Order.Count | Should -Be 0
            }

            It 'recusa executar o WireSock com assinatura inválida' {
                Mock Get-VglSignature { return [pscustomobject]@{ Status = 'HashMismatch'; Subject = '' } }
                { Enable-VoltaGoLive } | Should -Throw '*assinatura digital*'
                $script:Order.Count | Should -Be 0
            }

            It 'para sem fechar o Discord quando o .conf é inválido' {
                [System.IO.File]::WriteAllText($script:UserConf, "[Interface]`nAddress = 10.2.0.2/32")
                { Enable-VoltaGoLive } | Should -Throw '*problemas*'
                $script:Order.Count | Should -Be 0
            }

            It 'para sem fechar o Discord quando não há .conf' {
                Remove-Item -LiteralPath $script:UserConf
                { Enable-VoltaGoLive } | Should -Throw '*pasta "config"*'
                $script:Order.Count | Should -Be 0
            }

            It 'se o túnel não sobe, limpa a cópia do .conf e reabre o Discord' {
                Mock Start-VglTunnel { throw 'falhou de propósito' }
                { Enable-VoltaGoLive } | Should -Throw '*falhou de propósito*'
                Test-Path -LiteralPath $script:TestPaths.RuntimeConf | Should -BeFalse
                $script:Order | Should -Contain 'abrir-discord'
            }

            It 'avisa, sem dar erro, quando o handshake não é confirmado' {
                Mock Wait-VglHandshake { return [pscustomobject]@{ Confirmed = $false; Time = $null } }
                { Enable-VoltaGoLive } | Should -Not -Throw
                Should -Invoke Write-VglMessage -ParameterFilter { $Kind -eq 'Aviso' -and $Message -like '*não consegui confirmar*' }
            }

            It 'não faz nada com -WhatIf' {
                $null = Enable-VoltaGoLive -WhatIf
                $script:Order.Count | Should -Be 0
            }

            It 'não grava a chave no log' {
                $null = Enable-VoltaGoLive
                $log = Get-Content -LiteralPath $script:TestPaths.LogFile -Raw
                $log | Should -Not -Match 'A{10}'
            }
        }

        Context 'Disable-VoltaGoLive' {
            It 'derruba o túnel, apaga a cópia do .conf e reabre o Discord' {
                $null = Enable-VoltaGoLive
                $script:Order.Clear()
                $status = Disable-VoltaGoLive
                ($script:Order -join ' > ') | Should -Be 'derrubar-tunel > fechar-discord > abrir-discord'
                $status.Active | Should -BeFalse
                Test-Path -LiteralPath $script:TestPaths.RuntimeConf | Should -BeFalse
                Test-Path -LiteralPath $script:TestPaths.StateFile | Should -BeFalse
                Test-Path -LiteralPath $script:UserConf | Should -BeTrue
            }

            It 'pode ser executada com o túnel já desativado' {
                { Disable-VoltaGoLive } | Should -Not -Throw
                Should -Invoke Write-VglMessage -ParameterFilter { $Message -like '*já estava desativado*' }
            }

            It 'não reabre o Discord com -NoRestartDiscord' {
                $null = Disable-VoltaGoLive -NoRestartDiscord
                $script:Order | Should -Not -Contain 'abrir-discord'
            }
        }

        Context 'Get-VoltaGoLiveStatus' {
            It 'mostra desativado quando não há processo do túnel' {
                $status = Get-VoltaGoLiveStatus
                $status.Active | Should -BeFalse
                $status.Uptime | Should -BeNullOrEmpty
                $status.HandshakeConfirmed | Should -BeFalse
            }

            It 'mostra tempo ativo e último handshake a partir do estado e do log' {
                $script:TunnelUp = $true
                Save-VglState -Path $script:TestPaths.StateFile -StartedAt (Get-Date).AddMinutes(-90) -Channels @('Stable')
                Set-Content -LiteralPath $script:TestPaths.TunnelLog -Value @(
                    '2026-01-02T10:00:00 | Received handshake_response'
                    '2026-01-02T10:02:00 | Received handshake_response'
                )
                $status = Get-VoltaGoLiveStatus
                $status.Active | Should -BeTrue
                [math]::Round($status.Uptime.TotalMinutes) | Should -Be 90
                $status.HandshakeConfirmed | Should -BeTrue
                $status.LastHandshake | Should -Be ([datetime]'2026-01-02T10:02:00')
            }

            It 'ignora log e estado antigos quando o túnel não está em execução' {
                Save-VglState -Path $script:TestPaths.StateFile -StartedAt (Get-Date).AddHours(-5)
                Set-Content -LiteralPath $script:TestPaths.TunnelLog -Value '2026-01-02T10:00:00 | Received handshake_response'
                $status = Get-VoltaGoLiveStatus
                $status.Active | Should -BeFalse
                $status.HandshakeConfirmed | Should -BeFalse
            }
        }

        Context 'New-VoltaGoLiveDiagnostic' {
            BeforeEach {
                # Simula vazamentos em todos os lugares de onde o relatório lê.
                $script:TunnelUp = $true
                $leak = 'usuario zeca em NOTE-ZECA, C:\Users\zeca\AppData, ip 198.51.100.23, v6 2001:db8::beef, ' +
                    (Get-TestKeyName) + ' = ' + (Get-TestKey -Fill 'Q')
                Set-Content -LiteralPath $script:TestPaths.TunnelLog -Value @("2026-01-02T10:00:00 | $leak")
                Set-Content -LiteralPath $script:TestPaths.LogFile -Value @("2026-01-02T10:00:01 [INFO] $leak")
                $null = New-Item -Path $script:TestPaths.RuntimeDir -ItemType Directory -Force
                [System.IO.File]::WriteAllText($script:TestPaths.RuntimeConf,
                    (ConvertTo-VglTunnelConf -Text $script:Original -Apps (Get-VglDiscordAppName)))
                Mock Protect-VoltaGoLiveText {
                    $identity = Get-TestIdentity -User 'zeca' -Machine 'NOTE-ZECA' -Folder 'C:\Users\zeca'
                    & (Get-Command -Name Protect-VoltaGoLiveText -CommandType Function) -Text $Text `
                        @identity
                }
            }

            It 'gera um relatório sem chave, IP, usuário, computador ou caminho do perfil' {
                $result = New-VoltaGoLiveDiagnostic -NoClipboard
                foreach ($text in @($result.Text, (Get-Content -LiteralPath $result.Path -Raw))) {
                    $text | Should -Not -Match 'Q{10}'
                    $text | Should -Not -Match 'A{10}'
                    $text | Should -Not -Match 'B{10}'
                    $text | Should -Not -Match '198\.51\.100'
                    $text | Should -Not -Match '203\.0\.113'
                    $text | Should -Not -Match '10\.2\.0'
                    $text | Should -Not -Match 'beef'
                    $text | Should -Not -Match '(?i)zeca'
                    $text | Should -Not -Match '(?i)\\Users\\'
                    $text | Should -Match '<USUARIO>'
                    $text | Should -Match '<PC>'
                    $text | Should -Match '%USERPROFILE%'
                }
            }

            It 'inclui as seções que ajudam a entender o problema' {
                $text = (New-VoltaGoLiveDiagnostic -NoClipboard).Text
                foreach ($section in @('Sistema', 'WireSock', 'Arquivo .conf', 'Discord', 'Túnel', 'Log do túnel', 'Log do VoltaGoLive')) {
                    $text | Should -Match ([regex]::Escape("== $section"))
                }
                $text | Should -Match 'Ativo: True'
                $text | Should -Match 'AllowedApps na cópia: Discord\.exe, DiscordPTB\.exe, DiscordCanary\.exe'
                $text | Should -Match 'Assinatura: Valid'
            }

            It 'continua mesmo quando uma parte da coleta falha' {
                Remove-Item -LiteralPath $script:UserConf
                $text = (New-VoltaGoLiveDiagnostic -NoClipboard).Text
                $text | Should -Match 'ERRO ao coletar'
                $text | Should -Match '== Discord =='
            }

            It 'não grava arquivo com -WhatIf' {
                $result = New-VoltaGoLiveDiagnostic -NoClipboard -WhatIf
                Test-Path -LiteralPath $result.Path | Should -BeFalse
            }
        }
    }
}
