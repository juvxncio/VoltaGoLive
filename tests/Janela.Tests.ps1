# Testes da janela e da saída em UTF-8. Só fazem sentido no Windows (Windows Forms),
# então são pulados em outros sistemas e rodam de verdade no CI (windows-latest).
BeforeDiscovery {
    $script:OnWindows = ($env:OS -eq 'Windows_NT')
}

Describe 'Janela do VoltaGoLive' -Skip:(-not $script:OnWindows) {
    BeforeAll {
        $script:Root = Split-Path -Path $PSScriptRoot -Parent
        $script:Form = & (Join-Path -Path $script:Root -ChildPath 'scripts/Janela.ps1') -NoShow
    }

    AfterAll {
        if ($null -ne $script:Form) {
            $script:Form.Dispose()
        }
    }

    It 'monta a janela sem exibir' {
        $script:Form | Should -BeOfType ([System.Windows.Forms.Form])
        $script:Form.Text | Should -Be 'VoltaGoLive'
    }

    It 'tem o controle <Name>' -ForEach @(
        @{ Name = 'StatusLabel' }, @{ Name = 'DetailLabel' }, @{ Name = 'EnableButton' }, @{ Name = 'DisableButton' },
        @{ Name = 'DiagnosticButton' }, @{ Name = 'ChooseButton' }, @{ Name = 'ConfLabel' }, @{ Name = 'OutputBox' }
    ) {
        @($script:Form.Controls.Find($Name, $true)).Count | Should -Be 1
    }

    It 'mostra o túnel desativado quando não há túnel' {
        $script:Form.Controls.Find('StatusLabel', $true)[0].Text | Should -Be 'Túnel DESATIVADO'
    }

    It 'os botões têm os textos em português' {
        $script:Form.Controls.Find('EnableButton', $true)[0].Text | Should -Be 'Ativar'
        $script:Form.Controls.Find('DisableButton', $true)[0].Text | Should -Be 'Desativar'
        $script:Form.Controls.Find('DiagnosticButton', $true)[0].Text | Should -Be 'Diagnóstico'
    }

    It 'a caixa de mensagens é somente leitura' {
        $script:Form.Controls.Find('OutputBox', $true)[0].ReadOnly | Should -BeTrue
    }
}

Describe 'Saída do script para a janela' -Skip:(-not $script:OnWindows) {
    It 'escreve os acentos em UTF-8 e não faz perguntas' {
        $root = Split-Path -Path $PSScriptRoot -Parent
        $runner = Join-Path -Path $root -ChildPath 'scripts/VoltaGoLive.ps1'
        $output = Join-Path -Path $TestDrive -ChildPath 'saida.txt'
        $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Action Status -NonInteractive -Utf8Output' -f $runner
        $shell = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $process = Start-Process -FilePath $shell -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $output
        $process.WaitForExit(60000) | Should -BeTrue
        $text = [System.IO.File]::ReadAllText($output, [System.Text.Encoding]::UTF8)
        $text | Should -Match 'Túnel: DESATIVADO'
    }
}
