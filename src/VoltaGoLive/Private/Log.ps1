function Write-VglLog {
    # Grava uma linha no log local. O texto SEMPRE passa pela redação antes de ir ao disco.
    # Falha de log nunca derruba a operação principal.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message,

        [ValidateSet('INFO', 'AVISO', 'ERRO')]
        [string]$Level = 'INFO',

        [string]$Path
    )

    try {
        if ([string]::IsNullOrEmpty($Path)) {
            $Path = (Get-VglPath).LogFile
        }
        $folder = Split-Path -Path $Path -Parent
        if (-not (Test-Path -LiteralPath $folder)) {
            $null = New-Item -Path $folder -ItemType Directory -Force
        }
        $safe = Protect-VoltaGoLiveText -Text $Message
        $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'), $Level, $safe
        Add-Content -LiteralPath $Path -Value $line -Encoding UTF8
    }
    catch {
        Write-Verbose -Message ('Não foi possível gravar no log: ' + $_.Exception.Message)
    }
}

function Write-VglMessage {
    # Mensagem para a pessoa na tela (com cor) e cópia redigida no log.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message,

        [ValidateSet('Info', 'Ok', 'Aviso', 'Erro')]
        [string]$Kind = 'Info'
    )

    $color = @{ Info = 'Gray'; Ok = 'Green'; Aviso = 'Yellow'; Erro = 'Red' }[$Kind]
    Write-Host -Object $Message -ForegroundColor $color

    $level = @{ Info = 'INFO'; Ok = 'INFO'; Aviso = 'AVISO'; Erro = 'ERRO' }[$Kind]
    Write-VglLog -Message $Message -Level $level
}

function Get-VglLogTail {
    # Últimas linhas de um arquivo de log, já redigidas de novo por segurança.
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [int]$Count = 40
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [string[]]@()
    }
    # Logs gravados por versões antigas podem conter a lista de programas abertos: fora.
    $lines = @(Get-Content -LiteralPath $Path -Tail ($Count * 4) -Encoding UTF8 |
            Where-Object { -not (Test-VglLogNoise -Line ([string]$_)) } |
            Select-Object -Last $Count |
            ForEach-Object { Protect-VoltaGoLiveText -Text ([string]$_) })
    return [string[]]$lines
}
