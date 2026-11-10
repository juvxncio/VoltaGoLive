function Get-VglDiscordAppName {
    # Nomes de executável que entram no AllowedApps (Stable, PTB e Canary).
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    $names = @($script:Vgl.DiscordChannels | ForEach-Object { $_.ProcessName + '.exe' })
    return [string[]]$names
}

function Find-VglDiscordInstall {
    # Detecta as instalações do Discord (Stable, PTB, Canary) na pasta de dados do usuário.
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param(
        [Parameter(Mandatory)]
        [string]$LocalAppData
    )

    $result = foreach ($channel in $script:Vgl.DiscordChannels) {
        $folder = Join-Path -Path $LocalAppData -ChildPath $channel.Folder
        $update = Join-Path -Path $folder -ChildPath 'Update.exe'
        $exeName = $channel.ProcessName + '.exe'
        $hasApp = $false
        if (Test-Path -LiteralPath $folder -PathType Container) {
            $hasApp = @(Get-ChildItem -LiteralPath $folder -Directory -Filter 'app-*' | Where-Object {
                    Test-Path -LiteralPath (Join-Path -Path $_.FullName -ChildPath $exeName) -PathType Leaf
                }).Count -gt 0
        }
        [pscustomobject]@{
            Channel     = $channel.Channel
            Folder      = $folder
            ProcessName = $channel.ProcessName
            ExeName     = $exeName
            UpdateExe   = $update
            Installed   = ($hasApp -and (Test-Path -LiteralPath $update -PathType Leaf))
        }
    }

    return @($result)
}

function Get-VglDiscordProcess {
    # Processos do Discord abertos agora (qualquer canal).
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param()

    $names = @($script:Vgl.DiscordChannels | ForEach-Object { $_.ProcessName })
    return @(Get-Process -Name $names -ErrorAction SilentlyContinue)
}

function Stop-VglDiscord {
    # Fecha o Discord e devolve os canais que estavam abertos, para reabrir depois.
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string[]])]
    param(
        [int]$TimeoutSeconds = 10
    )

    $running = @(Get-VglDiscordProcess)
    $names = @($running | ForEach-Object { $_.ProcessName } | Sort-Object -Unique)
    $channels = @($script:Vgl.DiscordChannels | Where-Object { $names -contains $_.ProcessName } | ForEach-Object { $_.Channel })

    if ($running.Count -gt 0 -and $PSCmdlet.ShouldProcess('Discord', 'Fechar')) {
        $running | Stop-Process -Force -ErrorAction SilentlyContinue
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        while (@(Get-VglDiscordProcess).Count -gt 0 -and (Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 300
        }
    }

    return [string[]]$channels
}

function Start-VglDiscord {
    # Abre o Discord pelos canais pedidos. Sem pedido, abre o primeiro canal instalado.
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string]$LocalAppData,

        [AllowEmptyCollection()]
        [string[]]$Channel = @()
    )

    $installed = @(Find-VglDiscordInstall -LocalAppData $LocalAppData | Where-Object { $_.Installed })
    $targets = @($installed | Where-Object { $Channel -contains $_.Channel })
    if ($targets.Count -eq 0) {
        $targets = @($installed | Select-Object -First 1)
    }

    $started = foreach ($target in $targets) {
        if ($PSCmdlet.ShouldProcess($target.Channel, 'Abrir o Discord')) {
            Start-Process -FilePath $target.UpdateExe -ArgumentList @('--processStart', $target.ExeName)
            $target.Channel
        }
    }

    return [string[]]@($started)
}
