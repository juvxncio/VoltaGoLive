# Valores fixos do projeto. Os nomes dos campos de chave do WireGuard são montados em
# duas partes de propósito: a verificação do repositório reprova qualquer arquivo
# versionado que contenha o nome do campo da chave privada por extenso.
$script:Vgl = @{
    Name               = 'VoltaGoLive'
    KeyPrivate         = 'Private' + 'Key'
    KeyPreshared       = 'Preshared' + 'Key'
    WireSockExe        = 'wiresock-client.exe'
    WireSockWingetId   = 'NTKERNEL.WireSockVPNClientCLI'
    WireSockSigner     = 'The Anti-Cloud Corporation'
    WingetHelp         = 'https://learn.microsoft.com/windows/package-manager/winget/'
    WireSockLicense    = 'https://wiresock.net/license/wiresock_eula'
    WireSockLogLevel   = 'debug'
    ProtonConfigUrl    = 'https://account.protonvpn.com/downloads'
    HandshakeTimeout   = 45
    TunnelStartTimeout = 20
    TunnelLogMaxBytes  = 2MB
    TunnelLogNoise     = '(?i)(?:resolve[d]? (?:TCP|UDP)v[46] owner|entry with system process PID|filter\(s\) with ID|Removing filter with ID)'
    HandshakePatterns  = @(
        'received handshake[_ ]response'
        'handshake[_ ](?:complete|completed|established|successful|succeeded|done)'
        'new session'
        'keypair \d+ created'
    )
    DiscordChannels    = @(
        @{ Channel = 'Stable'; Folder = 'Discord'; ProcessName = 'Discord' }
        @{ Channel = 'PTB'; Folder = 'DiscordPTB'; ProcessName = 'DiscordPTB' }
        @{ Channel = 'Canary'; Folder = 'DiscordCanary'; ProcessName = 'DiscordCanary' }
    )
}
