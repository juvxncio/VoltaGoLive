function Protect-VoltaGoLiveText {
    <#
    .SYNOPSIS
    Remove dados sensíveis e pessoais de um texto antes de ele ir para log ou relatório.

    .DESCRIPTION
    Substitui por marcadores: chaves do WireGuard (privada, pré-compartilhada e qualquer
    chave em base64), endereços IPv4 e IPv6 (incluindo o endereço do túnel e o IP público),
    o caminho do perfil do usuário, o nome do usuário do Windows e o nome do computador.

    Todo texto que o VoltaGoLive grava em disco ou mostra no diagnóstico passa por aqui.

    .PARAMETER Text
    Texto a redigir. Aceita entrada pelo pipeline.

    .PARAMETER UserName
    Nome do usuário a esconder. Por padrão, o usuário atual do Windows.

    .PARAMETER ComputerName
    Nome do computador a esconder. Por padrão, o computador atual.

    .PARAMETER UserProfile
    Pasta do perfil a esconder. Por padrão, a pasta do usuário atual.

    .EXAMPLE
    'Endpoint = 203.0.113.7:51820' | Protect-VoltaGoLiveText

    Devolve 'Endpoint = <IP>:51820'.

    .OUTPUTS
    System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyString()]
        [string]$Text,

        [AllowEmptyString()]
        [AllowNull()]
        [string]$UserName = $env:USERNAME,

        [AllowEmptyString()]
        [AllowNull()]
        [string]$ComputerName = $env:COMPUTERNAME,

        [AllowEmptyString()]
        [AllowNull()]
        [string]$UserProfile = $env:USERPROFILE
    )

    begin {
        $options = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        $boundaryStart = '(?<![A-Za-z0-9_])'
        $boundaryEnd = '(?![A-Za-z0-9_])'
    }

    process {
        $result = $Text

        # 1. Campos de chave: tudo depois do sinal de igual (ou dois pontos) some.
        $result = [regex]::Replace(
            $result,
            '\b((?:Private|Preshared)Key)\b(\s*[=:]\s*)[^\r\n]*',
            '$1$2<REDIGIDO>',
            $options)

        # 2. Qualquer chave WireGuard solta no texto (32 bytes em base64).
        $result = [regex]::Replace($result, '(?<![A-Za-z0-9+/])[A-Za-z0-9+/]{43}=', '<CHAVE>')

        # 3. Pasta do perfil, nas duas formas de barra, e qualquer outra pasta de usuário.
        if (-not [string]::IsNullOrEmpty($UserProfile)) {
            $profilePattern = [regex]::Escape($UserProfile) -replace '(\\\\|/)', '[\\/]+'
            $result = [regex]::Replace($result, $profilePattern, '%USERPROFILE%', $options)
        }
        $result = [regex]::Replace(
            $result,
            '[A-Za-z]:[\\/]+Users[\\/]+[^\\/\s"''<>|:*?]+',
            '%USERPROFILE%',
            $options)

        # 4. IPv4. Sobram apenas 0.0.0.0 (usado em AllowedIPs) e o loopback.
        $result = [regex]::Replace(
            $result,
            '(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])',
            {
                param($match)
                if ($match.Value -eq '0.0.0.0' -or $match.Value -like '127.*') {
                    return $match.Value
                }
                return '<IP>'
            })

        # 5. IPv6: forma completa e formas abreviadas com "::". O "::" sozinho (de "::/0") fica.
        $hex = '[0-9A-Fa-f]{1,4}'
        $ipv6Patterns = @(
            "(?<![\w:.])(?:${hex}:){7}${hex}(?![\w:])"
            "(?<![\w:.])(?:${hex}:){1,7}:(?:${hex}(?::${hex}){0,6})?(?![\w:])"
            "(?<![\w:.\]])::${hex}(?::${hex}){0,6}(?![\w:])"
        )
        foreach ($pattern in $ipv6Patterns) {
            $result = [regex]::Replace($result, $pattern, '<IP>')
        }

        # 6. Nome do computador e, depois, do usuário, como palavras inteiras. O computador
        #    vem primeiro porque o nome dele costuma conter o nome do usuário.
        if (-not [string]::IsNullOrEmpty($ComputerName)) {
            $result = [regex]::Replace(
                $result,
                $boundaryStart + [regex]::Escape($ComputerName) + $boundaryEnd,
                '<PC>',
                $options)
        }
        if (-not [string]::IsNullOrEmpty($UserName)) {
            $result = [regex]::Replace(
                $result,
                $boundaryStart + [regex]::Escape($UserName) + $boundaryEnd,
                '<USUARIO>',
                $options)
        }

        return $result
    }
}
