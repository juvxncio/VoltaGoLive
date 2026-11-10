function Find-VglWireSock {
    # Procura o wiresock-client.exe: primeiro no PATH, depois nas pastas de instalação.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyCollection()]
        [string[]]$SearchRoot
    )

    $exe = $script:Vgl.WireSockExe

    if (-not $PSBoundParameters.ContainsKey('SearchRoot')) {
        $command = Get-Command -Name $exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $command) {
            return $command.Source
        }
        $SearchRoot = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { -not [string]::IsNullOrEmpty($_) }
    }

    foreach ($root in $SearchRoot) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) {
            continue
        }
        $folders = @(Get-ChildItem -LiteralPath $root -Directory -Filter 'WireSock*' -ErrorAction SilentlyContinue)
        foreach ($folder in $folders) {
            $match = Get-ChildItem -LiteralPath $folder.FullName -Recurse -File -Filter $exe -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($null -ne $match) {
                return $match.FullName
            }
        }
    }

    return $null
}

function Get-VglSignature {
    # Lê a assinatura digital (Authenticode) de um arquivo. Isolado para poder ser simulado nos testes.
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    $subject = ''
    if ($null -ne $signature.SignerCertificate) {
        $subject = $signature.SignerCertificate.Subject
    }
    return [pscustomobject]@{
        Status  = [string]$signature.Status
        Subject = $subject
    }
}

function Test-VglSignature {
    # Confere se a assinatura é válida e, quando há um publicador esperado, se é dele.
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Signature,

        [AllowEmptyString()]
        [string]$ExpectedSigner = $script:Vgl.WireSockSigner
    )

    if ($Signature.Status -ne 'Valid') {
        return $false
    }
    if ([string]::IsNullOrEmpty($ExpectedSigner)) {
        return $true
    }
    # Compara o campo CN (ou O) inteiro do certificado, não um trecho solto.
    $pattern = '(?i)(?:^|,\s*)(?:CN|O)="?' + [regex]::Escape($ExpectedSigner) + '"?(?:,|$)'
    return ($Signature.Subject -match $pattern)
}

function Get-VglTunnelProcess {
    # Processos wiresock-client em execução. O túnel roda como administrador, e um processo
    # comum não consegue ler a linha de comando de um processo elevado; por isso a busca é
    # pelo nome. Quem decide se o túnel é "nosso" é a presença da cópia do .conf.
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Paths
    )

    if (-not (Test-Path -LiteralPath $Paths.RuntimeConf -PathType Leaf)) {
        return @()
    }
    $name = [System.IO.Path]::GetFileNameWithoutExtension($script:Vgl.WireSockExe)
    $result = foreach ($process in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
        [pscustomobject]@{
            ProcessId  = [int]$process.Id
            Name       = $script:Vgl.WireSockExe
            IsWireSock = $true
        }
    }
    return @($result)
}

function Test-VglLogNoise {
    # Diz se uma linha do log do WireSock deve ser descartada. No nível de detalhe usado,
    # o WireSock lista todos os programas do computador que têm conexão aberta. Isso não
    # ajuda no diagnóstico e é dado pessoal, então nunca vai para o disco.
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Line
    )

    return ($Line -match $script:Vgl.TunnelLogNoise)
}

function Get-VglTunnelFailureFix {
    # Escolhe a orientação certa para a pessoa a partir do que o WireSock escreveu no log.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Line = @()
    )

    $text = $Line -join "`n"
    if ($text -match '(?i)Packet Filter driver is not available') {
        return 'O driver de rede do WireSock não respondeu. Reinicie o computador e tente de novo. Se continuar, reinstale o WireSock: abra o PowerShell e rode "winget install --id {0} --exact --source winget --force".' -f $script:Vgl.WireSockWingetId
    }
    return 'Confira se o arquivo .conf é o que você baixou da Proton, sem edição. Se continuar, gere o diagnóstico e envie o relatório.'
}

function Start-VglTunnel {
    # Sobe o túnel: abre, como administrador, um PowerShell oculto (TunnelHost.ps1) que
    # executa o wiresock-client e grava a saída dele, já redigida, no log do túnel.
    # O WireSock só consegue usar o driver de rede com permissão de administrador.
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$ExePath,

        [Parameter(Mandatory)]
        [hashtable]$Paths
    )

    if (-not $PSCmdlet.ShouldProcess('WireSock', 'Subir o túnel')) {
        return
    }

    foreach ($stale in @($Paths.TunnelLog, $Paths.StopFile)) {
        if (Test-Path -LiteralPath $stale) {
            Remove-Item -LiteralPath $stale -Force -ErrorAction SilentlyContinue
        }
    }

    $shell = (Get-Process -Id $PID).Path
    $arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -ExePath "{1}" -ConfigPath "{2}" -LogPath "{3}" -StopFile "{4}" -LogLevel {5} -MaxBytes {6}' -f `
        $Paths.TunnelHost, $ExePath, $Paths.RuntimeConf, $Paths.TunnelLog, $Paths.StopFile, $script:Vgl.WireSockLogLevel, $script:Vgl.TunnelLogMaxBytes

    if (-not (Test-VglAdministrator)) {
        Write-VglMessage -Message 'O Windows vai pedir permissão de administrador: o WireSock precisa dela para usar o driver de rede. Clique em Sim.'
    }
    try {
        $null = Start-Process -FilePath $shell -ArgumentList $arguments -WindowStyle Hidden -Verb RunAs -PassThru
    }
    catch {
        throw (New-VglProblem -Message 'O túnel não foi iniciado porque a permissão de administrador não foi concedida.' `
                -Fix 'Tente ativar de novo e clique em Sim quando o Windows perguntar. Sem essa permissão o WireSock não consegue criar o túnel.')
    }

    $deadline = (Get-Date).AddSeconds($script:Vgl.TunnelStartTimeout)
    do {
        Start-Sleep -Milliseconds 500
        $alive = @(Get-VglTunnelProcess -Paths $Paths).Count -gt 0
    } while (-not $alive -and (Get-Date) -lt $deadline)

    # Dá um instante para o WireSock recusar a configuração, se for o caso.
    Start-Sleep -Seconds 3
    $alive = @(Get-VglTunnelProcess -Paths $Paths).Count -gt 0
    if (-not $alive) {
        $lines = @(Get-VglLogTail -Path $Paths.TunnelLog -Count 15)
        throw (New-VglProblem -Message ("O WireSock não ficou em execução. Últimas linhas do log do túnel:`n    " + ($lines -join "`n    ")) `
                -Fix (Get-VglTunnelFailureFix -Line $lines))
    }
}

function Stop-VglTunnel {
    # Derruba o túnel. O processo do túnel roda como administrador e não pode ser encerrado
    # por um processo comum, então o pedido é feito por um arquivo de sinal: o TunnelHost.ps1
    # vê o arquivo, encerra o wiresock-client e termina. Assim não é preciso pedir
    # permissão de administrador outra vez. Devolve quantos processos havia.
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Paths,

        [int]$TimeoutSeconds = 15
    )

    $processes = @(Get-VglTunnelProcess -Paths $Paths)
    if ($processes.Count -eq 0 -or -not $PSCmdlet.ShouldProcess('WireSock', 'Derrubar o túnel')) {
        return 0
    }

    $folder = Split-Path -Path $Paths.StopFile -Parent
    if (-not (Test-Path -LiteralPath $folder)) {
        $null = New-Item -Path $folder -ItemType Directory -Force
    }
    [System.IO.File]::WriteAllText($Paths.StopFile, 'parar')

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while (@(Get-VglTunnelProcess -Paths $Paths).Count -gt 0 -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
    }

    # Último recurso: funciona quando quem chama também é administrador.
    foreach ($process in @(Get-VglTunnelProcess -Paths $Paths)) {
        Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $Paths.StopFile -Force -ErrorAction SilentlyContinue

    if (@(Get-VglTunnelProcess -Paths $Paths).Count -gt 0) {
        throw (New-VglProblem -Message 'Não consegui encerrar o WireSock.' `
                -Fix 'Reinicie o computador: isso derruba o túnel. Depois, se quiser, gere o diagnóstico e envie o relatório.')
    }
    return $processes.Count
}
