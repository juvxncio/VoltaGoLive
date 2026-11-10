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
    # Processos do túnel que pertencem ao VoltaGoLive: o wiresock-client iniciado com a
    # nossa cópia do .conf e o PowerShell oculto que grava o log redigido.
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Paths
    )

    $exe = $script:Vgl.WireSockExe
    $all = @(Get-CimInstance -ClassName Win32_Process -ErrorAction SilentlyContinue | Where-Object {
            $commandLine = [string]$_.CommandLine
            $hasConf = $commandLine.IndexOf($Paths.RuntimeConf, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
            $hasHost = $commandLine.IndexOf($Paths.TunnelHost, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
            $isShell = ($_.Name -like '*powershell*') -or ($_.Name -like 'pwsh*')
            (($_.Name -eq $exe) -and $hasConf) -or ($isShell -and $hasHost)
        })

    $result = foreach ($process in $all) {
        [pscustomobject]@{
            ProcessId  = [int]$process.ProcessId
            Name       = [string]$process.Name
            IsWireSock = ($process.Name -eq $exe)
        }
    }
    return @($result)
}

function Start-VglTunnel {
    # Sobe o túnel: abre um PowerShell oculto (TunnelHost.ps1) que executa o wiresock-client
    # e grava a saída dele, já redigida, no log do túnel.
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

    if (Test-Path -LiteralPath $Paths.TunnelLog) {
        Remove-Item -LiteralPath $Paths.TunnelLog -Force -ErrorAction SilentlyContinue
    }

    $shell = (Get-Process -Id $PID).Path
    $arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -ExePath "{1}" -ConfigPath "{2}" -LogPath "{3}" -LogLevel {4} -MaxBytes {5}' -f `
        $Paths.TunnelHost, $ExePath, $Paths.RuntimeConf, $Paths.TunnelLog, $script:Vgl.WireSockLogLevel, $script:Vgl.TunnelLogMaxBytes

    $null = Start-Process -FilePath $shell -ArgumentList $arguments -WindowStyle Hidden -PassThru

    $deadline = (Get-Date).AddSeconds($script:Vgl.TunnelStartTimeout)
    do {
        Start-Sleep -Milliseconds 500
        $alive = @(Get-VglTunnelProcess -Paths $Paths | Where-Object { $_.IsWireSock }).Count -gt 0
    } while (-not $alive -and (Get-Date) -lt $deadline)

    # Dá um instante para o WireSock recusar a configuração, se for o caso.
    Start-Sleep -Seconds 2
    $alive = @(Get-VglTunnelProcess -Paths $Paths | Where-Object { $_.IsWireSock }).Count -gt 0
    if (-not $alive) {
        $tail = (Get-VglLogTail -Path $Paths.TunnelLog -Count 15) -join "`n    "
        throw (New-VglProblem -Message ("O WireSock não ficou em execução. Últimas linhas do log do túnel:`n    " + $tail) `
                -Fix 'Confira se o arquivo .conf é o que você baixou da Proton. Se continuar, rode o Diagnostico.bat e envie o relatório.')
    }
}

function Stop-VglTunnel {
    # Derruba o túnel: encerra o wiresock-client e, em seguida, o PowerShell oculto.
    # Devolve quantos processos foram encerrados.
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Paths
    )

    $processes = @(Get-VglTunnelProcess -Paths $Paths)
    if ($processes.Count -eq 0 -or -not $PSCmdlet.ShouldProcess('WireSock', 'Derrubar o túnel')) {
        return 0
    }

    foreach ($process in @($processes | Where-Object { $_.IsWireSock })) {
        Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 800
    foreach ($process in @(Get-VglTunnelProcess -Paths $Paths)) {
        Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
    }

    return $processes.Count
}
