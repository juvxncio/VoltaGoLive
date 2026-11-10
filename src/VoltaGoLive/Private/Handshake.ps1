function Get-VglHandshakeInfo {
    # Procura no log do túnel (linhas no formato "data | texto") a última linha que indica
    # handshake concluído. Devolve se foi confirmado e quando.
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Line,

        [string[]]$Pattern = $script:Vgl.HandshakePatterns
    )

    $regex = '(?i)(?:' + ($Pattern -join '|') + ')'
    $last = $null
    foreach ($entry in $Line) {
        if ($entry -match $regex) {
            $last = $entry
        }
    }

    $when = $null
    if ($null -ne $last -and $last -match '^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\s\|') {
        $when = [datetime]::ParseExact($Matches[1], 'yyyy-MM-ddTHH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
    }

    return [pscustomobject]@{
        Confirmed = ($null -ne $last)
        Time      = $when
    }
}

function Wait-VglHandshake {
    # Espera o handshake aparecer no log do túnel, até o limite de tempo.
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$LogPath,

        [int]$TimeoutSeconds = $script:Vgl.HandshakeTimeout
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $lines = [string[]]@()
        if (Test-Path -LiteralPath $LogPath -PathType Leaf) {
            $lines = [string[]]@(Get-Content -LiteralPath $LogPath -Encoding UTF8)
        }
        $info = Get-VglHandshakeInfo -Line $lines
        if ($info.Confirmed) {
            return $info
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)

    return $info
}
