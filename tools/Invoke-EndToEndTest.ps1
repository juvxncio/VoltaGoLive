<#
.SYNOPSIS
Teste de ponta a ponta em Windows real, feito para rodar no GitHub Actions.

.DESCRIPTION
Instala o WireSock de verdade, sobe um servidor WireGuard local (wireproxy, só dentro do
teste) e executa o fluxo real do VoltaGoLive contra ele, com um "Discord de mentira"
(uma cópia do curl.exe com o nome Discord.exe).

O que este teste prova:
  - o WireSock instala pelo winget e o executável é encontrado e tem assinatura válida;
  - o comando usado para subir o túnel é aceito e o processo fica em execução;
  - o handshake acontece e é reconhecido no log;
  - um programa chamado Discord.exe alcança um endereço que só existe dentro do túnel,
    e um programa com outro nome não alcança;
  - desativar derruba o túnel e limpa os arquivos temporários.

O que este teste NÃO prova: o comportamento do Discord de verdade nem de uma conta Proton.

As chaves usadas são geradas na hora, valem só para o teste e nunca são exibidas.
Não rode este script no seu computador pessoal: ele fecha processos chamados Discord e
cria uma pasta Discord falsa se não houver uma instalada.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Path $PSScriptRoot -Parent
Import-Module -Name (Join-Path -Path $root -ChildPath 'src/VoltaGoLive/VoltaGoLive.psd1') -Force
$module = Get-Module -Name VoltaGoLive

$work = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('vgl-e2e-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -Path $work -ItemType Directory -Force
$noBom = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
$checks = New-Object -TypeName 'System.Collections.Generic.List[object]'
$tunnelAddress = '10.99.0.1'
$tunnelUrl = 'http://{0}:8080/' -f $tunnelAddress
$marker = 'VOLTAGOLIVE-E2E-OK'

function Write-Step {
    param([string]$Title)
    Write-Output ''
    Write-Output ('==== {0} ====' -f $Title)
}

function Add-Check {
    param([string]$Name, [bool]$Passed, [string]$Detail = '')
    $checks.Add([pscustomobject]@{ Name = $Name; Passed = $Passed; Detail = $Detail })
    $label = 'FALHOU'
    if ($Passed) {
        $label = 'ok'
    }
    Write-Output ('[{0}] {1} {2}' -f $label, $Name, $Detail)
}

function Invoke-Fetch {
    # Usa um executável no estilo do curl para buscar a página que só existe dentro do túnel.
    param([string]$Exe)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $Exe --silent --max-time 6 $tunnelUrl 2>$null
    }
    finally {
        $ErrorActionPreference = $previous
    }
    return (($output | Out-String) -match $marker)
}

function Get-WireGuardKeyPair {
    # Gera um par de chaves X25519 com o openssl que vem com o Git para Windows.
    param([string]$Name)
    $openssl = Join-Path -Path $env:ProgramFiles -ChildPath 'Git\usr\bin\openssl.exe'
    $pem = Join-Path -Path $work -ChildPath ($Name + '.pem')
    $privateDer = Join-Path -Path $work -ChildPath ($Name + '.priv.der')
    $publicDer = Join-Path -Path $work -ChildPath ($Name + '.pub.der')
    & $openssl genpkey -algorithm X25519 -out $pem
    & $openssl pkey -in $pem -outform DER -out $privateDer
    & $openssl pkey -in $pem -pubout -outform DER -out $publicDer
    $privateBytes = [System.IO.File]::ReadAllBytes($privateDer)
    $publicBytes = [System.IO.File]::ReadAllBytes($publicDer)
    return @{
        Secret = [System.Convert]::ToBase64String($privateBytes, $privateBytes.Length - 32, 32)
        Public = [System.Convert]::ToBase64String($publicBytes, $publicBytes.Length - 32, 32)
    }
}

$background = New-Object -TypeName 'System.Collections.Generic.List[object]'
$secretField = 'Private' + 'Key'

try {
    # ------------------------------------------------------------------ WireSock
    Write-Step -Title 'Instalar o WireSock pela função do projeto (winget)'
    $exe = & $module { Find-VglWireSock }
    if ([string]::IsNullOrEmpty($exe)) {
        try {
            $exe = Install-VoltaGoLiveWireSock -Confirm:$false
        }
        catch {
            Write-Output ('Instalação pelo winget falhou: ' + $_.Exception.Message)
        }
    }
    if ([string]::IsNullOrEmpty($exe)) {
        Write-Step -Title 'Descoberta: o que o instalador colocou no disco'
        foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA, $env:ProgramData)) {
            Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '(?i)wiresock|ntkernel|winpkfilter|packet filter' } |
                ForEach-Object {
                    Write-Output ('Pasta: ' + $_.FullName)
                    Get-ChildItem -LiteralPath $_.FullName -Recurse -File -ErrorAction SilentlyContinue |
                        Where-Object { $_.Extension -in @('.exe', '.sys', '.dll', '.cmd', '.bat') } |
                        ForEach-Object { Write-Output ('  ' + $_.FullName.Substring($base.Length)) }
                }
        }
        Write-Output 'No PATH:'
        Get-Command -Name '*wiresock*' -CommandType Application -ErrorAction SilentlyContinue | ForEach-Object { Write-Output ('  ' + $_.Source) }
        Write-Output 'Serviços:'
        Get-Service -Name '*wiresock*', '*ndisrd*' -ErrorAction SilentlyContinue | ForEach-Object { Write-Output ('  {0} ({1})' -f $_.Name, $_.Status) }
        Write-Output 'Pacotes do winget com o nome:'
        & winget.exe list --name WireSock --accept-source-agreements | Out-String | Write-Output
    }
    Add-Check -Name 'WireSock instalado e encontrado' -Passed (-not [string]::IsNullOrEmpty($exe))
    if ([string]::IsNullOrEmpty($exe)) {
        throw 'Sem o WireSock não há como continuar.'
    }

    Write-Step -Title 'Inspecionar a instalação'
    $installDir = Split-Path -Path $exe -Parent
    Write-Output ('Pasta: ' + $installDir)
    Get-ChildItem -LiteralPath $installDir -File | ForEach-Object { Write-Output ('  ' + $_.Name) }
    Write-Output ('Versão do arquivo: ' + (Get-Item -LiteralPath $exe).VersionInfo.FileVersion)
    $signature = & $module { param($path) Get-VglSignature -Path $path } $exe
    Write-Output ('Assinatura: ' + $signature.Status)
    Write-Output ('Assinante: ' + $signature.Subject)
    $accepted = & $module { param($value) Test-VglSignature -Signature $value } $signature
    Add-Check -Name 'Assinatura digital aceita pelo projeto' -Passed ([bool]$accepted)

    Write-Step -Title 'Texto de ajuda do wiresock-client (sem argumentos)'
    $usageOut = Join-Path -Path $work -ChildPath 'usage.out.txt'
    $usageErr = Join-Path -Path $work -ChildPath 'usage.err.txt'
    $usage = Start-Process -FilePath $exe -RedirectStandardOutput $usageOut -RedirectStandardError $usageErr -PassThru -WindowStyle Hidden
    if (-not $usage.WaitForExit(15000)) {
        Stop-Process -Id $usage.Id -Force -ErrorAction SilentlyContinue
        Write-Output '(o processo não terminou sozinho em 15 segundos e foi encerrado)'
    }
    Get-Content -LiteralPath $usageOut, $usageErr -ErrorAction SilentlyContinue | Select-Object -First 80 | ForEach-Object { Write-Output ('  ' + $_) }

    # ------------------------------------------------------- servidor WireGuard local
    Write-Step -Title 'Preparar o servidor WireGuard local (wireproxy)'
    $server = Get-WireGuardKeyPair -Name 'server'
    $client = Get-WireGuardKeyPair -Name 'client'

    $archive = Join-Path -Path $work -ChildPath 'wireproxy.tar.gz'
    Invoke-WebRequest -Uri 'https://github.com/windtf/wireproxy/releases/download/v1.1.3/wireproxy_windows_amd64.tar.gz' -OutFile $archive
    $archiveHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($archiveHash -ne 'bce041ea9fe0f8a3351301dcbe29cdf6a523bb25cf9c62f17ebb5699a8051d0f') {
        throw 'O SHA256 do wireproxy baixado não confere.'
    }
    & tar.exe -xzf $archive -C $work
    $wireproxy = (Get-ChildItem -LiteralPath $work -Recurse -File -Filter 'wireproxy.exe' | Select-Object -First 1).FullName

    $www = Join-Path -Path $work -ChildPath 'www'
    $null = New-Item -Path $www -ItemType Directory -Force
    [System.IO.File]::WriteAllText((Join-Path -Path $www -ChildPath 'index.html'), $marker, $noBom)
    $background.Add((Start-Process -FilePath 'python' -ArgumentList @('-m', 'http.server', '9000', '--bind', '127.0.0.1', '--directory', ('"{0}"' -f $www)) -PassThru -WindowStyle Hidden))

    $serverConf = Join-Path -Path $work -ChildPath 'server.conf'
    $serverText = @(
        '[Interface]'
        ($secretField + ' = ' + $server.Secret)
        ('Address = {0}/32' -f $tunnelAddress)
        'ListenPort = 51820'
        ''
        '[Peer]'
        ('PublicKey = ' + $client.Public)
        'AllowedIPs = 10.99.0.2/32'
        ''
        '[TCPServerTunnel]'
        'ListenPort = 8080'
        'Target = 127.0.0.1:9000'
    ) -join "`n"
    [System.IO.File]::WriteAllText($serverConf, $serverText + "`n", $noBom)
    $serverLog = Join-Path -Path $work -ChildPath 'wireproxy.log'
    $background.Add((Start-Process -FilePath $wireproxy -ArgumentList @('-c', ('"{0}"' -f $serverConf)) -PassThru -WindowStyle Hidden `
                -RedirectStandardOutput $serverLog -RedirectStandardError ($serverLog + '.err')))
    Start-Sleep -Seconds 3
    Add-Check -Name 'Servidor WireGuard local em execução' -Passed (-not $background[1].HasExited)

    # ------------------------------------------------------------ Discord de mentira
    Write-Step -Title 'Preparar o Discord de mentira (cópia do curl.exe)'
    $curl = Join-Path -Path $env:SystemRoot -ChildPath 'System32\curl.exe'
    $discordRoot = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Discord'
    $discordApp = Join-Path -Path $discordRoot -ChildPath 'app-0.0.1'
    $null = New-Item -Path $discordApp -ItemType Directory -Force
    $fakeDiscord = Join-Path -Path $discordApp -ChildPath 'Discord.exe'
    Copy-Item -LiteralPath $curl -Destination $fakeDiscord -Force
    Copy-Item -LiteralPath (Join-Path -Path $env:SystemRoot -ChildPath 'System32\where.exe') -Destination (Join-Path -Path $discordRoot -ChildPath 'Update.exe') -Force

    Add-Check -Name 'Antes do túnel, o Discord de mentira NÃO alcança o endereço interno' -Passed (-not (Invoke-Fetch -Exe $fakeDiscord))

    # ------------------------------------------------------------------ configuração
    $endpoint = (Get-NetIPConfiguration | Where-Object { $null -ne $_.IPv4DefaultGateway } | Select-Object -First 1).IPv4Address.IPAddress
    $userConf = Join-Path -Path $work -ChildPath 'usuario.conf'
    $userText = @(
        '[Interface]'
        ($secretField + ' = ' + $client.Secret)
        'Address = 10.99.0.2/32'
        ''
        '[Peer]'
        ('PublicKey = ' + $server.Public)
        'AllowedIPs = 10.99.0.0/24'
        ('Endpoint = {0}:51820' -f $endpoint)
        'PersistentKeepalive = 25'
    ) -join "`r`n"
    [System.IO.File]::WriteAllText($userConf, $userText + "`r`n", $noBom)
    $originalHash = (Get-FileHash -LiteralPath $userConf -Algorithm SHA256).Hash

    # --------------------------------------------------------------------- ativar
    Write-Step -Title 'Enable-VoltaGoLive (fluxo real)'
    $traffic = Start-Job -ScriptBlock {
        $fetcher = $using:fakeDiscord
        $address = $using:tunnelUrl
        1..40 | ForEach-Object {
            Start-Sleep -Seconds 2
            if (Test-Path -LiteralPath $fetcher) {
                & $fetcher --silent --max-time 4 $address 2>$null | Out-Null
            }
        }
    }

    $status = $null
    try {
        $status = Enable-VoltaGoLive -ConfigPath $userConf
    }
    catch {
        Write-Output ('Enable-VoltaGoLive falhou: ' + $_.Exception.Message)
    }
    $traffic | Stop-Job -PassThru | Remove-Job -Force

    $paths = & $module { Get-VglPath }
    Add-Check -Name 'Túnel ativo depois de ativar' -Passed ($null -ne $status -and $status.Active)
    Add-Check -Name 'Handshake confirmado pelo log' -Passed ($null -ne $status -and $status.HandshakeConfirmed)
    Add-Check -Name 'O .conf original não foi alterado' -Passed ((Get-FileHash -LiteralPath $userConf -Algorithm SHA256).Hash -eq $originalHash)
    Add-Check -Name 'A cópia do .conf existe enquanto o túnel está ativo' -Passed (Test-Path -LiteralPath $paths.RuntimeConf)

    Write-Step -Title 'Túnel dividido por programa'
    $allowed = Invoke-Fetch -Exe $fakeDiscord
    $blocked = Invoke-Fetch -Exe $curl
    Add-Check -Name 'Discord.exe alcança o endereço que só existe dentro do túnel' -Passed $allowed
    Add-Check -Name 'curl.exe (fora da lista) NÃO alcança esse endereço' -Passed (-not $blocked)

    Write-Step -Title 'Get-VoltaGoLiveStatus'
    Get-VoltaGoLiveStatus | Format-List | Out-String | Write-Output

    Write-Step -Title 'Log do túnel (redigido, primeiras 120 linhas)'
    if (Test-Path -LiteralPath $paths.TunnelLog) {
        Get-Content -LiteralPath $paths.TunnelLog -Encoding UTF8 | Select-Object -First 120 | ForEach-Object { Write-Output ('  ' + $_) }
    }
    else {
        Write-Output '(sem log do túnel)'
    }

    Write-Step -Title 'New-VoltaGoLiveDiagnostic'
    $diagnostic = New-VoltaGoLiveDiagnostic -ConfigPath $userConf -NoClipboard
    Write-Output $diagnostic.Text
    $leaks = @()
    foreach ($secret in @($client.Secret, $server.Public, $endpoint, $env:USERNAME, $env:COMPUTERNAME, $env:USERPROFILE)) {
        if (-not [string]::IsNullOrEmpty($secret) -and $diagnostic.Text.IndexOf($secret, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $leaks += 1
        }
    }
    Add-Check -Name 'Diagnóstico sem chave, IP, usuário, computador ou pasta do perfil' -Passed ($leaks.Count -eq 0)
    $rawLogs = (Get-Content -LiteralPath $paths.TunnelLog, $paths.LogFile -Raw -ErrorAction SilentlyContinue) -join "`n"
    $logLeak = ($rawLogs.IndexOf($client.Secret) -ge 0) -or ($rawLogs.IndexOf($endpoint) -ge 0)
    Add-Check -Name 'Logs em disco sem chave e sem IP' -Passed (-not $logLeak)

    # ------------------------------------------------------------------ desativar
    Write-Step -Title 'Disable-VoltaGoLive (fluxo real)'
    $after = Disable-VoltaGoLive
    Add-Check -Name 'Túnel inativo depois de desativar' -Passed (-not $after.Active)
    Add-Check -Name 'Nenhum processo wiresock-client sobrando' -Passed (@(Get-Process -Name 'wiresock-client' -ErrorAction SilentlyContinue).Count -eq 0)
    Add-Check -Name 'A cópia do .conf foi apagada' -Passed (-not (Test-Path -LiteralPath $paths.RuntimeConf))
    Add-Check -Name 'Depois de desativar, o Discord de mentira não alcança mais o endereço interno' -Passed (-not (Invoke-Fetch -Exe $fakeDiscord))
    $code = & $curl --silent --max-time 15 --output NUL --write-out '%{http_code}' 'https://github.com'
    Add-Check -Name 'A internet normal continua funcionando' -Passed ($code -match '^(2|3)\d\d$') -Detail ("(HTTP $code)")

    Write-Step -Title 'Log do servidor local (wireproxy)'
    Get-Content -LiteralPath $serverLog, ($serverLog + '.err') -ErrorAction SilentlyContinue | Select-Object -Last 30 | ForEach-Object {
        Write-Output ('  ' + (Protect-VoltaGoLiveText -Text ([string]$_)))
    }
}
finally {
    try {
        $null = Disable-VoltaGoLive -NoRestartDiscord
    }
    catch {
        Write-Output ('Limpeza: ' + $_.Exception.Message)
    }
    foreach ($process in $background) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Step -Title 'Resumo'
$failed = @($checks | Where-Object { -not $_.Passed })
foreach ($check in $checks) {
    $label = 'FALHOU'
    if ($check.Passed) {
        $label = 'ok'
    }
    Write-Output ('[{0}] {1}' -f $label, $check.Name)
}
if ($failed.Count -gt 0) {
    Write-Error -Message ('{0} verificação(ões) falharam.' -f $failed.Count)
    exit 1
}
Write-Output 'Todas as verificações passaram.'
