function Disable-VoltaGoLive {
    <#
    .SYNOPSIS
    Desativa o túnel e devolve o Discord para a conexão normal.

    .DESCRIPTION
    Encerra o WireSock iniciado pelo VoltaGoLive, fecha o Discord, apaga os arquivos
    temporários (a cópia do .conf e o estado) e reabre o Discord fora do túnel.
    Pode ser executada mesmo que o túnel não esteja ativo: nesse caso só faz a limpeza.

    .PARAMETER NoRestartDiscord
    Não reabre o Discord depois de desativar.

    .EXAMPLE
    Disable-VoltaGoLive

    Desativa o túnel e reabre o Discord normalmente.

    .OUTPUTS
    PSCustomObject com o estado depois da desativação.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [switch]$NoRestartDiscord
    )

    Assert-VglWindows
    $paths = Get-VglPath

    if (-not $PSCmdlet.ShouldProcess('Discord', 'Desativar o túnel')) {
        return
    }

    Write-VglLog -Message 'Desativação iniciada.'
    $state = Read-VglState -Path $paths.StateFile

    Write-VglMessage -Message 'Derrubando o túnel...'
    $stopped = Stop-VglTunnel -Paths $paths

    Write-VglMessage -Message 'Fechando o Discord...'
    $channels = @(Stop-VglDiscord)
    if ($channels.Count -eq 0 -and $null -ne $state -and $null -ne $state.Channels) {
        $channels = @($state.Channels)
    }

    Clear-VglRuntime -Paths $paths

    if (-not $NoRestartDiscord) {
        Write-VglMessage -Message 'Abrindo o Discord na conexão normal...'
        $null = Start-VglDiscord -LocalAppData $paths.LocalAppData -Channel $channels
    }

    if ($stopped -gt 0) {
        Write-VglMessage -Message 'Túnel desativado. O Discord voltou para a conexão normal.' -Kind 'Ok'
    }
    else {
        Write-VglMessage -Message 'O túnel já estava desativado. Arquivos temporários limpos.' -Kind 'Ok'
    }

    return (Get-VoltaGoLiveStatus)
}
