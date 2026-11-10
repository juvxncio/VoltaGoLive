BeforeDiscovery {
    # O InModuleScope precisa do módulo carregado já na fase de descoberta.
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../src/VoltaGoLive/VoltaGoLive.psd1') -Force
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers.ps1')
    Import-TestModule
}

InModuleScope VoltaGoLive {
    Describe 'Detecção do Discord' {
        BeforeAll {
            function Initialize-FakeDiscord {
                param([string]$Root, [string]$Folder, [string]$Exe, [switch]$NoUpdate, [switch]$NoApp)
                $base = Join-Path -Path $Root -ChildPath $Folder
                $null = New-Item -Path $base -ItemType Directory -Force
                if (-not $NoUpdate) {
                    Set-Content -LiteralPath (Join-Path -Path $base -ChildPath 'Update.exe') -Value 'x'
                }
                if (-not $NoApp) {
                    $app = Join-Path -Path $base -ChildPath 'app-1.0.9999'
                    $null = New-Item -Path $app -ItemType Directory -Force
                    Set-Content -LiteralPath (Join-Path -Path $app -ChildPath $Exe) -Value 'x'
                }
            }
        }

        It 'lista os três canais e marca nenhum como instalado numa pasta vazia' {
            $root = Join-Path -Path $TestDrive -ChildPath 'vazio'
            $null = New-Item -Path $root -ItemType Directory -Force
            $found = Find-VglDiscordInstall -LocalAppData $root
            $found.Count | Should -Be 3
            @($found | Where-Object { $_.Installed }).Count | Should -Be 0
        }

        It 'detecta o canal <Channel>' -ForEach @(
            @{ Channel = 'Stable'; Folder = 'Discord'; Exe = 'Discord.exe' }
            @{ Channel = 'PTB'; Folder = 'DiscordPTB'; Exe = 'DiscordPTB.exe' }
            @{ Channel = 'Canary'; Folder = 'DiscordCanary'; Exe = 'DiscordCanary.exe' }
        ) {
            $root = Join-Path -Path $TestDrive -ChildPath "um-$Channel"
            Initialize-FakeDiscord -Root $root -Folder $Folder -Exe $Exe
            $installed = @(Find-VglDiscordInstall -LocalAppData $root | Where-Object { $_.Installed })
            $installed.Count | Should -Be 1
            $installed[0].Channel | Should -Be $Channel
            $installed[0].ExeName | Should -Be $Exe
            Split-Path -Path $installed[0].UpdateExe -Leaf | Should -Be 'Update.exe'
        }

        It 'detecta vários canais instalados ao mesmo tempo' {
            $root = Join-Path -Path $TestDrive -ChildPath 'varios'
            Initialize-FakeDiscord -Root $root -Folder 'Discord' -Exe 'Discord.exe'
            Initialize-FakeDiscord -Root $root -Folder 'DiscordCanary' -Exe 'DiscordCanary.exe'
            $channels = @(Find-VglDiscordInstall -LocalAppData $root | Where-Object { $_.Installed } | ForEach-Object { $_.Channel })
            $channels | Should -Be @('Stable', 'Canary')
        }

        It 'não considera instalado sem Update.exe ou sem a pasta app-*' {
            $root = Join-Path -Path $TestDrive -ChildPath 'incompleto'
            Initialize-FakeDiscord -Root $root -Folder 'Discord' -Exe 'Discord.exe' -NoUpdate
            Initialize-FakeDiscord -Root $root -Folder 'DiscordPTB' -Exe 'DiscordPTB.exe' -NoApp
            @(Find-VglDiscordInstall -LocalAppData $root | Where-Object { $_.Installed }).Count | Should -Be 0
        }

        It 'gera os nomes de executável para o AllowedApps' {
            Get-VglDiscordAppName | Should -Be @('Discord.exe', 'DiscordPTB.exe', 'DiscordCanary.exe')
        }
    }

    Describe 'Abrir e fechar o Discord' {
        BeforeAll {
            $script:Root = Join-Path -Path $TestDrive -ChildPath 'abrir'
            foreach ($item in @(@('Discord', 'Discord.exe'), @('DiscordPTB', 'DiscordPTB.exe'))) {
                $app = Join-Path -Path (Join-Path -Path $script:Root -ChildPath $item[0]) -ChildPath 'app-1.0.1'
                $null = New-Item -Path $app -ItemType Directory -Force
                Set-Content -LiteralPath (Join-Path -Path $app -ChildPath $item[1]) -Value 'x'
                Set-Content -LiteralPath (Join-Path -Path (Split-Path -Path $app -Parent) -ChildPath 'Update.exe') -Value 'x'
            }
        }

        BeforeEach {
            Mock Start-Process { }
            Mock Stop-Process { }
            Mock Start-Sleep { }
        }

        It 'abre pelo Update.exe com --processStart, no canal pedido' {
            $started = Start-VglDiscord -LocalAppData $script:Root -Channel @('PTB')
            $started | Should -Be @('PTB')
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
                (Split-Path -Path $FilePath -Leaf) -eq 'Update.exe' -and
                $FilePath -like '*DiscordPTB*' -and
                $ArgumentList[0] -eq '--processStart' -and $ArgumentList[1] -eq 'DiscordPTB.exe'
            }
        }

        It 'sem canal pedido, abre o primeiro instalado' {
            Start-VglDiscord -LocalAppData $script:Root | Should -Be @('Stable')
        }

        It 'não tenta abrir nada quando o Discord não está instalado' {
            $empty = Join-Path -Path $TestDrive -ChildPath 'sem-discord'
            $null = New-Item -Path $empty -ItemType Directory -Force
            @(Start-VglDiscord -LocalAppData $empty).Count | Should -Be 0
            Should -Invoke Start-Process -Times 0
        }

        It 'fecha os processos abertos e devolve os canais que estavam em uso' {
            $script:Calls = 0
            Mock Get-VglDiscordProcess {
                $script:Calls++
                if ($script:Calls -eq 1) {
                    return @(
                        [pscustomobject]@{ ProcessName = 'Discord'; Id = 11 }
                        [pscustomobject]@{ ProcessName = 'Discord'; Id = 12 }
                        [pscustomobject]@{ ProcessName = 'DiscordCanary'; Id = 13 }
                    )
                }
                return @()
            }
            Stop-VglDiscord | Should -Be @('Stable', 'Canary')
            Should -Invoke Stop-Process -Times 1
        }

        It 'não faz nada quando o Discord já está fechado' {
            Mock Get-VglDiscordProcess { return @() }
            @(Stop-VglDiscord).Count | Should -Be 0
            Should -Invoke Stop-Process -Times 0
        }
    }
}
