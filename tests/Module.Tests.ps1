BeforeDiscovery {
    $script:Root = Split-Path -Path $PSScriptRoot -Parent
    $script:PublicFiles = @(Get-ChildItem -Path (Join-Path -Path $script:Root -ChildPath 'src/VoltaGoLive/Public') -Filter '*.ps1' |
            ForEach-Object { @{ Name = $_.BaseName } })
    $script:SourceFiles = @(Get-ChildItem -Path (Join-Path -Path $script:Root -ChildPath 'src'), (Join-Path -Path $script:Root -ChildPath 'scripts') -Recurse -Filter '*.ps*1' |
            ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } })
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers.ps1')
    Import-TestModule
    $script:Root = Split-Path -Path $PSScriptRoot -Parent
}

Describe 'Módulo VoltaGoLive' {
    It 'tem um manifesto válido' {
        $manifest = Test-ModuleManifest -Path (Join-Path -Path $script:Root -ChildPath 'src/VoltaGoLive/VoltaGoLive.psd1')
        $manifest.Version.ToString() | Should -Match '^\d+\.\d+\.\d+$'
        $manifest.PowerShellVersion.ToString() | Should -Be '5.1'
    }

    It 'exporta exatamente as funções públicas' {
        $exported = @((Get-Module -Name VoltaGoLive).ExportedFunctions.Keys | Sort-Object)
        $files = @(Get-ChildItem -Path (Join-Path -Path $script:Root -ChildPath 'src/VoltaGoLive/Public') -Filter '*.ps1' |
                ForEach-Object { $_.BaseName } | Sort-Object)
        $exported | Should -Be $files
    }

    It 'a versão do manifesto aparece no CHANGELOG' {
        $version = (Get-Module -Name VoltaGoLive).Version.ToString()
        $changelog = Get-Content -LiteralPath (Join-Path -Path $script:Root -ChildPath 'CHANGELOG.md') -Raw
        $changelog | Should -Match ([regex]::Escape("[$version]"))
    }

    It 'a função pública <Name> usa verbo aprovado e tem ajuda completa' -ForEach $script:PublicFiles {
        $verb = ($Name -split '-')[0]
        (Get-Verb).Verb | Should -Contain $verb
        $help = Get-Help -Name $Name -Full
        $help.Synopsis | Should -Not -BeNullOrEmpty
        $help.Synopsis | Should -Not -Match "^\s*$Name"
        ($help.description | Out-String).Trim() | Should -Not -BeNullOrEmpty
        @($help.examples.example).Count | Should -BeGreaterThan 0
    }
}

Describe 'Regras do código-fonte: <Name>' -ForEach $script:SourceFiles {
    BeforeAll {
        $script:Content = Get-Content -LiteralPath $Path -Raw
        $script:Tokens = $null
        $script:Errors = $null
        $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$script:Tokens, [ref]$script:Errors)
    }

    It 'não tem erro de sintaxe' {
        @($script:Errors).Count | Should -Be 0
    }

    It 'não lê variáveis de ambiente em massa' {
        $script:Content | Should -Not -Match '(?i)(Get-ChildItem|gci|dir|ls)\s+(-Path\s+)?env:'
        $script:Content | Should -Not -Match '(?i)GetEnvironmentVariables\s*\('
        $script:Content | Should -Not -Match '(?i)Get-Item\s+(-Path\s+)?env:\\?\*'
    }

    It 'só lê as variáveis de ambiente permitidas, pelo nome' {
        $allowed = @('USERNAME', 'COMPUTERNAME', 'USERPROFILE', 'LOCALAPPDATA', 'ProgramFiles', 'ProgramFiles(x86)', 'OS')
        $used = @($script:Ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.VariableExpressionAst] -and $node.VariablePath.DriveName -eq 'env'
                }, $true) | ForEach-Object { $_.VariablePath.UserPath -replace '^env:', '' } | Sort-Object -Unique)
        foreach ($name in $used) {
            $allowed | Should -Contain $name
        }
    }

    It 'não usa sintaxe que o Windows PowerShell 5.1 não entende' {
        $kinds = @($script:Tokens | ForEach-Object { $_.Kind.ToString() })
        $kinds | Should -Not -Contain 'QuestionQuestion'
        $kinds | Should -Not -Contain 'QuestionQuestionEquals'
        $kinds | Should -Not -Contain 'QuestionDot'
        $kinds | Should -Not -Contain 'AndAnd'
        $kinds | Should -Not -Contain 'OrOr'
        @($script:Ast.FindAll({ param($node) $node.GetType().Name -eq 'TernaryExpressionAst' }, $true)).Count | Should -Be 0
    }
}

Describe 'Lançadores de dois cliques' {
    It 'o <Name>.bat chama o script com a ação certa, sem acentos e com fim de linha do Windows' -ForEach @(
        @{ Name = 'Ativar' }, @{ Name = 'Desativar' }, @{ Name = 'Status' }, @{ Name = 'Diagnostico' }
    ) {
        $path = Join-Path -Path $script:Root -ChildPath "$Name.bat"
        $bytes = [System.IO.File]::ReadAllBytes($path)
        @($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
        $text = [System.Text.Encoding]::ASCII.GetString($bytes)
        $text | Should -Match ([regex]::Escape('"%~dp0scripts\VoltaGoLive.ps1" -Action ' + $Name))
        $text | Should -Match 'powershell\.exe -NoProfile'
        $text | Should -Match "`r`n"
    }

    It 'o VoltaGoLive.bat abre a janela, sem acentos e com fim de linha do Windows' {
        $bytes = [System.IO.File]::ReadAllBytes((Join-Path -Path $script:Root -ChildPath 'VoltaGoLive.bat'))
        @($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
        $text = [System.Text.Encoding]::ASCII.GetString($bytes)
        $text | Should -Match ([regex]::Escape('"%~dp0scripts\Janela.ps1"'))
        $text | Should -Match "`r`n"
    }
}
