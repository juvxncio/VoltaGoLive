function Assert-VglWindows {
    # O VoltaGoLive só faz sentido no Windows. Em outro sistema, para com mensagem clara.
    [CmdletBinding()]
    param()

    if ($env:OS -ne 'Windows_NT') {
        throw 'O VoltaGoLive só funciona no Windows.'
    }
}

function Get-VglPath {
    # Todos os caminhos usados pelo projeto, num lugar só.
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowEmptyString()]
        [AllowNull()]
        [string]$LocalAppData = $env:LOCALAPPDATA
    )

    if ([string]::IsNullOrEmpty($LocalAppData)) {
        throw 'Não encontrei a pasta de dados do usuário (LOCALAPPDATA).'
    }

    $root = Split-Path -Path (Split-Path -Path $script:ModuleRoot -Parent) -Parent
    $data = Join-Path -Path $LocalAppData -ChildPath $script:Vgl.Name
    $logs = Join-Path -Path $data -ChildPath 'logs'
    $runtime = Join-Path -Path $data -ChildPath 'runtime'

    return @{
        Root          = $root
        ConfigDir     = Join-Path -Path $root -ChildPath 'config'
        LocalAppData  = $LocalAppData
        DataDir       = $data
        LogDir        = $logs
        LogFile       = Join-Path -Path $logs -ChildPath 'voltagolive.log'
        TunnelLog     = Join-Path -Path $logs -ChildPath 'tunel.log'
        RuntimeDir    = $runtime
        RuntimeConf   = Join-Path -Path $runtime -ChildPath 'voltagolive.conf'
        StateFile     = Join-Path -Path $data -ChildPath 'estado.json'
        DiagnosticDir = Join-Path -Path $data -ChildPath 'diagnostico'
        TunnelHost    = Join-Path -Path $script:ModuleRoot -ChildPath 'TunnelHost.ps1'
    }
}

function Find-VglUserConf {
    # Localiza o .conf do usuário: o caminho informado ou o único .conf da pasta config.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()]
        [AllowNull()]
        [string]$ConfigPath,

        [Parameter(Mandatory)]
        [string]$ConfigDir
    )

    if (-not [string]::IsNullOrEmpty($ConfigPath)) {
        if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
            throw (New-VglProblem -Message 'Não encontrei o arquivo de configuração informado.' `
                    -Fix 'Confira o caminho do arquivo .conf e tente de novo.')
        }
        return (Resolve-Path -LiteralPath $ConfigPath).ProviderPath
    }

    $found = @()
    if (Test-Path -LiteralPath $ConfigDir -PathType Container) {
        $found = @(Get-ChildItem -LiteralPath $ConfigDir -Filter '*.conf' -File)
    }

    if ($found.Count -eq 0) {
        throw (New-VglProblem -Message 'Não encontrei nenhum arquivo .conf na pasta "config".' `
                -Fix ('Baixe a configuração WireGuard na sua conta Proton ({0}, opção "WireGuard configuration") e coloque o arquivo .conf dentro da pasta "config", ao lado do Ativar.bat.' -f $script:Vgl.ProtonConfigUrl))
    }
    if ($found.Count -gt 1) {
        throw (New-VglProblem -Message ('Há {0} arquivos .conf na pasta "config" e eu não sei qual usar.' -f $found.Count) `
                -Fix 'Deixe só um arquivo .conf na pasta "config" e tente de novo.')
    }

    return $found[0].FullName
}

function New-VglProblem {
    # Monta a mensagem padrão de erro: o que aconteceu e o que a pessoa deve fazer.
    [CmdletBinding()]
    [OutputType([string])]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Só monta um texto, não altera nada.')]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory)]
        [string]$Fix
    )

    return "$Message`n  O que fazer: $Fix"
}
