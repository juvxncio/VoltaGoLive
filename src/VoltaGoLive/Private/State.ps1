function Read-VglState {
    # Lê o estado salvo na última ativação. Devolve $null se não houver ou estiver corrompido.
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }
    try {
        return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Save-VglState {
    # Grava o estado da ativação (somente horário e canais do Discord; nada sensível).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [datetime]$StartedAt,

        [AllowEmptyCollection()]
        [string[]]$Channels = @()
    )

    $folder = Split-Path -Path $Path -Parent
    if (-not (Test-Path -LiteralPath $folder)) {
        $null = New-Item -Path $folder -ItemType Directory -Force
    }
    $state = [pscustomobject]@{
        StartedAt = $StartedAt.ToString('o')
        Channels  = @($Channels)
    }
    $json = $state | ConvertTo-Json -Depth 3
    [System.IO.File]::WriteAllText($Path, $json, (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false))
}

function Clear-VglRuntime {
    # Apaga os arquivos temporários: a cópia do .conf (que contém a chave) e o estado.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Paths
    )

    foreach ($item in @($Paths.RuntimeConf, $Paths.StateFile)) {
        if (Test-Path -LiteralPath $item) {
            Remove-Item -LiteralPath $item -Force -ErrorAction SilentlyContinue
        }
    }
    if (Test-Path -LiteralPath $Paths.RuntimeDir) {
        Remove-Item -LiteralPath $Paths.RuntimeDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
