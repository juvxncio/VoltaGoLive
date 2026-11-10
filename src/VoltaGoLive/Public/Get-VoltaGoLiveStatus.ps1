function Get-VoltaGoLiveStatus {
    <#
    .SYNOPSIS
    Mostra se o túnel está ativo, há quanto tempo e quando foi o último handshake.

    .DESCRIPTION
    Não altera nada. Verifica se o processo do WireSock iniciado pelo VoltaGoLive está
    em execução, lê o horário da ativação e procura no log do túnel a última confirmação
    de handshake.

    .EXAMPLE
    Get-VoltaGoLiveStatus

    Devolve um objeto com Active, StartedAt, Uptime, HandshakeConfirmed e LastHandshake.

    .OUTPUTS
    PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    Assert-VglWindows
    $paths = Get-VglPath

    $active = @(Get-VglTunnelProcess -Paths $paths | Where-Object { $_.IsWireSock }).Count -gt 0
    $state = Read-VglState -Path $paths.StateFile

    $startedAt = $null
    $uptime = $null
    if ($active -and $null -ne $state -and -not [string]::IsNullOrEmpty($state.StartedAt)) {
        $startedAt = [datetime]::Parse($state.StartedAt, [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::RoundtripKind)
        $uptime = (Get-Date) - $startedAt
    }

    $handshake = [pscustomobject]@{ Confirmed = $false; Time = $null }
    if ($active -and (Test-Path -LiteralPath $paths.TunnelLog -PathType Leaf)) {
        $lines = [string[]]@(Get-Content -LiteralPath $paths.TunnelLog -Encoding UTF8)
        $handshake = Get-VglHandshakeInfo -Line $lines
    }

    return [pscustomobject]@{
        Active             = $active
        StartedAt          = $startedAt
        Uptime             = $uptime
        HandshakeConfirmed = [bool]$handshake.Confirmed
        LastHandshake      = $handshake.Time
        DiscordRunning     = (@(Get-VglDiscordProcess).Count -gt 0)
    }
}
