function ConvertFrom-VglConf {
    # Lê o texto de um .conf WireGuard e devolve uma linha de objeto por linha de texto.
    # Linhas com o prefixo "#@ws:" (extensão do WireSock) são tratadas como entradas normais.
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    $clean = $Text.TrimStart([char]0xFEFF)
    $section = ''
    $result = New-Object -TypeName 'System.Collections.Generic.List[object]'

    foreach ($raw in ($clean -split "`r?`n")) {
        $line = $raw.Trim()
        if ($line -match '^#@ws:\s*(.*)$') {
            $line = $Matches[1].Trim()
        }

        $kind = 'Other'
        $key = ''
        $value = ''

        if ($line -eq '') {
            $kind = 'Blank'
        }
        elseif ($line -match '^\[(.+)\]$') {
            $kind = 'Section'
            $section = $Matches[1].Trim()
        }
        elseif ($line -match '^[#;]') {
            $kind = 'Comment'
        }
        elseif ($line -match '^([^=]+?)\s*=\s*(.*)$') {
            $kind = 'Entry'
            $key = $Matches[1].Trim()
            $value = $Matches[2].Trim()
        }

        $result.Add([pscustomobject]@{
                Raw     = $raw
                Kind    = $kind
                Section = $section
                Key     = $key
                Value   = $value
            })
    }

    return $result.ToArray()
}

function Get-VglConfValue {
    # Devolve todos os valores de uma chave dentro de uma seção (comparação sem diferenciar maiúsculas).
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Parsed,

        [Parameter(Mandatory)]
        [string]$Section,

        [Parameter(Mandatory)]
        [string]$Key
    )

    $values = @($Parsed | Where-Object {
            $_.Kind -eq 'Entry' -and $_.Section -eq $Section -and $_.Key -eq $Key
        } | ForEach-Object { $_.Value })

    return [string[]]$values
}

function Test-VglConf {
    # Valida um .conf WireGuard. Devolve a lista de problemas encontrados (vazia = válido).
    # Nunca inclui valores do arquivo nas mensagens.
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    $problems = New-Object -TypeName 'System.Collections.Generic.List[string]'
    $parsed = @(ConvertFrom-VglConf -Text $Text)
    $sections = @($parsed | Where-Object { $_.Kind -eq 'Section' } | ForEach-Object { $_.Section })

    if ($sections -notcontains 'Interface') {
        $problems.Add('Falta a seção [Interface]. O arquivo não parece ser uma configuração WireGuard.')
    }
    if ($sections -notcontains 'Peer') {
        $problems.Add('Falta a seção [Peer]. O arquivo não parece ser uma configuração WireGuard.')
    }
    if ($problems.Count -gt 0) {
        return $problems.ToArray()
    }

    $keyPattern = '^[A-Za-z0-9+/]{43}=$'

    $private = @(Get-VglConfValue -Parsed $parsed -Section 'Interface' -Key $script:Vgl.KeyPrivate)
    if ($private.Count -eq 0) {
        $problems.Add('Falta a chave privada na seção [Interface].')
    }
    elseif ($private[0] -notmatch $keyPattern) {
        $problems.Add('A chave privada da seção [Interface] está em formato inválido (arquivo cortado ou editado?).')
    }

    $address = @(Get-VglConfValue -Parsed $parsed -Section 'Interface' -Key 'Address')
    if ($address.Count -eq 0 -or $address[0] -eq '') {
        $problems.Add('Falta o campo Address na seção [Interface].')
    }

    $public = @(Get-VglConfValue -Parsed $parsed -Section 'Peer' -Key 'PublicKey')
    if ($public.Count -eq 0) {
        $problems.Add('Falta o campo PublicKey na seção [Peer].')
    }
    elseif ($public[0] -notmatch $keyPattern) {
        $problems.Add('O campo PublicKey da seção [Peer] está em formato inválido.')
    }

    $endpoint = @(Get-VglConfValue -Parsed $parsed -Section 'Peer' -Key 'Endpoint')
    if ($endpoint.Count -eq 0) {
        $problems.Add('Falta o campo Endpoint na seção [Peer].')
    }
    elseif ($endpoint[0] -notmatch '^\S+:\d{1,5}$') {
        $problems.Add('O campo Endpoint da seção [Peer] precisa estar no formato servidor:porta.')
    }

    $allowedIps = @(Get-VglConfValue -Parsed $parsed -Section 'Peer' -Key 'AllowedIPs')
    if ($allowedIps.Count -eq 0 -or $allowedIps[0] -eq '') {
        $problems.Add('Falta o campo AllowedIPs na seção [Peer].')
    }

    return $problems.ToArray()
}

function ConvertTo-VglTunnelConf {
    # Gera o texto do .conf usado pelo túnel: igual ao original, mas com uma única linha
    # AllowedApps em cada [Peer] restringindo o túnel aos aplicativos informados.
    # Qualquer AllowedApps ou DisallowedApps que já exista é descartado.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Apps
    )

    $parsed = @(ConvertFrom-VglConf -Text $Text)
    $directive = 'AllowedApps = ' + ($Apps -join ', ')
    $output = New-Object -TypeName 'System.Collections.Generic.List[string]'
    $inPeer = $false

    $closePeer = {
        # Insere a diretiva logo depois da última linha não vazia da seção.
        $index = $output.Count
        while ($index -gt 0 -and $output[$index - 1].Trim() -eq '') {
            $index--
        }
        $output.Insert($index, $directive)
    }

    foreach ($line in $parsed) {
        if ($line.Kind -eq 'Section') {
            if ($inPeer) {
                & $closePeer
            }
            $inPeer = ($line.Section -eq 'Peer')
            $output.Add($line.Raw.Trim())
            continue
        }
        if ($inPeer -and $line.Kind -eq 'Entry' -and @('AllowedApps', 'DisallowedApps') -contains $line.Key) {
            continue
        }
        $output.Add($line.Raw.TrimEnd())
    }
    if ($inPeer) {
        & $closePeer
    }

    while ($output.Count -gt 0 -and $output[$output.Count - 1].Trim() -eq '') {
        $output.RemoveAt($output.Count - 1)
    }

    return (($output.ToArray() -join "`r`n") + "`r`n").TrimStart([char]0xFEFF)
}

function Get-VglConfSummary {
    # Resumo do .conf para o diagnóstico: só estrutura, nunca valores sensíveis.
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    $parsed = @(ConvertFrom-VglConf -Text $Text)
    $lines = New-Object -TypeName 'System.Collections.Generic.List[string]'
    $sections = @($parsed | Where-Object { $_.Kind -eq 'Section' } | ForEach-Object { $_.Section })
    $lines.Add('Seções: ' + ($sections -join ', '))

    foreach ($section in @('Interface', 'Peer')) {
        $keys = @($parsed | Where-Object { $_.Kind -eq 'Entry' -and $_.Section -eq $section } | ForEach-Object { $_.Key })
        $lines.Add("Campos em [$section]: " + ($keys -join ', '))
    }

    $allowedIps = (Get-VglConfValue -Parsed $parsed -Section 'Peer' -Key 'AllowedIPs') -join ','
    $lines.Add('AllowedIPs cobre IPv4 inteiro: ' + ($allowedIps -match '(^|,|\s)0\.0\.0\.0/0'))
    $lines.Add('AllowedIPs cobre IPv6 inteiro: ' + ($allowedIps -match '(^|,|\s)::/0'))
    $lines.Add('Problemas de validação: ' + @(Test-VglConf -Text $Text).Count)

    return $lines.ToArray()
}
