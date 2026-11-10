<#
.SYNOPSIS
Janela do VoltaGoLive: os mesmos botões dos arquivos .bat, numa tela só.

.DESCRIPTION
Abre uma janela simples do Windows (Windows Forms, que já vem no sistema) com o estado
do túnel e os botões Ativar, Desativar e Diagnóstico. Também permite escolher o arquivo
.conf sem precisar copiar para a pasta "config" à mão.

A janela não faz nada por conta própria: cada botão executa o scripts/VoltaGoLive.ps1,
o mesmo que os arquivos .bat usam, e mostra na tela o que ele escreveu.

.PARAMETER NoShow
Monta a janela e devolve o objeto, sem exibir. Usado nos testes automáticos.
#>
[CmdletBinding()]
param(
    [switch]$NoShow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:Root = Split-Path -Path $PSScriptRoot -Parent
$script:ConfigDir = Join-Path -Path $script:Root -ChildPath 'config'
$script:Runner = Join-Path -Path $PSScriptRoot -ChildPath 'VoltaGoLive.ps1'
$script:Process = $null
$script:OutputFile = $null
$script:CurrentAction = ''

Import-Module -Name (Join-Path -Path $script:Root -ChildPath 'src\VoltaGoLive\VoltaGoLive.psd1') -Force

function Get-ConfLabel {
    # Texto que descreve o arquivo .conf em uso (só o nome, nunca o conteúdo).
    $found = @()
    if (Test-Path -LiteralPath $script:ConfigDir -PathType Container) {
        $found = @(Get-ChildItem -LiteralPath $script:ConfigDir -Filter '*.conf' -File)
    }
    if ($found.Count -eq 0) {
        return 'Nenhum arquivo .conf escolhido ainda.'
    }
    if ($found.Count -gt 1) {
        return ('Há {0} arquivos .conf na pasta config. Escolha um.' -f $found.Count)
    }
    return ('Configuração: ' + $found[0].Name)
}

function Format-StatusText {
    # Transforma o objeto de status em duas linhas de texto para a tela.
    param([pscustomobject]$Status)

    $details = New-Object -TypeName 'System.Collections.Generic.List[string]'
    if ($Status.Active) {
        $title = 'Túnel ATIVO'
        if ($null -ne $Status.Uptime) {
            $details.Add(('Ativo há {0}h {1:00}min' -f [int][math]::Floor($Status.Uptime.TotalHours), $Status.Uptime.Minutes))
        }
        if ($Status.HandshakeConfirmed -and $null -ne $Status.LastHandshake) {
            $details.Add('Último handshake: ' + $Status.LastHandshake.ToString('dd/MM/yyyy HH:mm:ss'))
        }
        elseif ($Status.HandshakeConfirmed) {
            $details.Add('Handshake confirmado')
        }
        else {
            $details.Add('Handshake ainda não confirmado')
        }
    }
    else {
        $title = 'Túnel DESATIVADO'
    }
    if ($Status.DiscordRunning) {
        $details.Add('Discord aberto')
    }
    else {
        $details.Add('Discord fechado')
    }

    return [pscustomobject]@{
        Title   = $title
        Details = ($details.ToArray() -join '   |   ')
        Active  = [bool]$Status.Active
    }
}

function Update-StatusView {
    # Lê o estado do túnel e atualiza os textos da janela. Nunca interrompe a janela.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Só atualiza textos na tela.')]
    param()

    try {
        $view = Format-StatusText -Status (Get-VoltaGoLiveStatus)
        $script:StatusLabel.Text = $view.Title
        $script:DetailLabel.Text = $view.Details
        if ($view.Active) {
            $script:StatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(0, 128, 60)
        }
        else {
            $script:StatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(110, 110, 110)
        }
    }
    catch {
        $script:StatusLabel.Text = 'Estado desconhecido'
        $script:DetailLabel.Text = $_.Exception.Message
    }
    $script:ConfLabel.Text = Get-ConfLabel
}

function Set-Busy {
    # Liga ou desliga os botões enquanto uma ação está em andamento.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Só habilita ou desabilita botões.')]
    param([bool]$Busy)

    foreach ($button in @($script:EnableButton, $script:DisableButton, $script:DiagnosticButton, $script:ChooseButton)) {
        $button.Enabled = -not $Busy
    }
    if ($Busy) {
        $script:Form.Cursor = [System.Windows.Forms.Cursors]::AppStarting
    }
    else {
        $script:Form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
}

function Start-Action {
    # Executa uma ação do scripts/VoltaGoLive.ps1 num processo oculto e passa a acompanhar a saída.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'A confirmação é o clique no botão.')]
    param(
        [string]$Action,
        [switch]$InstallWireSock
    )

    if ($null -ne $script:Process) {
        return
    }
    $script:CurrentAction = $Action
    $script:OutputFile = [System.IO.Path]::GetTempFileName()
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Action {1} -NonInteractive -Utf8Output' -f $script:Runner, $Action
    if ($InstallWireSock) {
        $arguments += ' -InstallWireSock'
    }
    $shell = (Get-Process -Id $PID).Path
    $script:OutputBox.Text = ''
    Set-Busy -Busy $true
    $script:Process = Start-Process -FilePath $shell -ArgumentList $arguments -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $script:OutputFile
    $script:ActionTimer.Start()
}

function Read-ActionOutput {
    # Lê o que a ação escreveu até agora, sem travar o arquivo.
    if ([string]::IsNullOrEmpty($script:OutputFile) -or -not (Test-Path -LiteralPath $script:OutputFile)) {
        return ''
    }
    try {
        $stream = New-Object -TypeName System.IO.FileStream -ArgumentList @(
            $script:OutputFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $reader = New-Object -TypeName System.IO.StreamReader -ArgumentList @($stream, [System.Text.Encoding]::UTF8)
            return $reader.ReadToEnd()
        }
        finally {
            $stream.Dispose()
        }
    }
    catch {
        return ''
    }
}

function Complete-Action {
    # Chamado quando a ação termina: mostra a saída final, limpa e trata o caso do WireSock ausente.
    $text = Read-ActionOutput
    $script:OutputBox.Text = $text
    $script:OutputBox.SelectionStart = $script:OutputBox.TextLength
    $script:OutputBox.ScrollToCaret()

    $action = $script:CurrentAction
    $script:Process = $null
    Remove-Item -LiteralPath $script:OutputFile -Force -ErrorAction SilentlyContinue
    $script:OutputFile = $null
    Set-Busy -Busy $false
    Update-StatusView

    if ($action -eq 'Ativar' -and $text -match 'O WireSock não está instalado') {
        $question = "O WireSock (programa que cria o túnel) ainda não está instalado.`n`n" +
            "Quer instalar agora pela fonte oficial (winget)?`n`n" +
            'O Windows vai pedir permissão de administrador, porque o WireSock instala um driver de rede.'
        $answer = [System.Windows.Forms.MessageBox]::Show($script:Form, $question, 'VoltaGoLive',
            [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
            Start-Action -Action 'Ativar' -InstallWireSock
        }
    }
}

function Select-ConfFile {
    # Deixa a pessoa escolher o .conf e coloca uma cópia, sozinha, na pasta config.
    $dialog = New-Object -TypeName System.Windows.Forms.OpenFileDialog
    $dialog.Title = 'Escolha o arquivo .conf que você baixou na Proton'
    $dialog.Filter = 'Configuração WireGuard (*.conf)|*.conf'
    if ($dialog.ShowDialog($script:Form) -ne [System.Windows.Forms.DialogResult]::OK) {
        return
    }
    $chosen = $dialog.FileName

    if (-not (Test-Path -LiteralPath $script:ConfigDir)) {
        $null = New-Item -Path $script:ConfigDir -ItemType Directory -Force
    }
    $target = Join-Path -Path $script:ConfigDir -ChildPath (Split-Path -Path $chosen -Leaf)
    $existing = @(Get-ChildItem -LiteralPath $script:ConfigDir -Filter '*.conf' -File | Where-Object { $_.FullName -ne $chosen })
    if ($existing.Count -gt 0) {
        $answer = [System.Windows.Forms.MessageBox]::Show($script:Form,
            'Já existe uma configuração na pasta config. Quer trocar pela que você escolheu?', 'VoltaGoLive',
            [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
            return
        }
        $existing | Remove-Item -Force
    }
    if ($chosen -ne $target) {
        Copy-Item -LiteralPath $chosen -Destination $target -Force
    }
    $script:OutputBox.Text = 'Configuração escolhida. O arquivo original não foi alterado. Agora clique em Ativar.'
    Update-StatusView
}

function New-Button {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Só cria um controle de tela.')]
    param([string]$Text, [int]$Left, [int]$Top, [int]$Width = 150)

    $button = New-Object -TypeName System.Windows.Forms.Button
    $button.Text = $Text
    $button.Left = $Left
    $button.Top = $Top
    $button.Width = $Width
    $button.Height = 38
    return $button
}

# ----------------------------------------------------------------------------- janela
$script:Form = New-Object -TypeName System.Windows.Forms.Form
$script:Form.Text = 'VoltaGoLive'
$script:Form.ClientSize = New-Object -TypeName System.Drawing.Size -ArgumentList 520, 470
$script:Form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$script:Form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$script:Form.MaximizeBox = $false
$script:Form.Font = New-Object -TypeName System.Drawing.Font -ArgumentList 'Segoe UI', 10

$script:StatusLabel = New-Object -TypeName System.Windows.Forms.Label
$script:StatusLabel.Name = 'StatusLabel'
$script:StatusLabel.Left = 20
$script:StatusLabel.Top = 16
$script:StatusLabel.Width = 480
$script:StatusLabel.Height = 40
$script:StatusLabel.Font = New-Object -TypeName System.Drawing.Font -ArgumentList 'Segoe UI', 18, ([System.Drawing.FontStyle]::Bold)
$script:StatusLabel.Text = 'Verificando...'

$script:DetailLabel = New-Object -TypeName System.Windows.Forms.Label
$script:DetailLabel.Name = 'DetailLabel'
$script:DetailLabel.Left = 22
$script:DetailLabel.Top = 58
$script:DetailLabel.Width = 480
$script:DetailLabel.Height = 24

$script:EnableButton = New-Button -Text 'Ativar' -Left 20 -Top 96
$script:EnableButton.Name = 'EnableButton'
$script:DisableButton = New-Button -Text 'Desativar' -Left 185 -Top 96
$script:DisableButton.Name = 'DisableButton'
$script:DiagnosticButton = New-Button -Text 'Diagnóstico' -Left 350 -Top 96
$script:DiagnosticButton.Name = 'DiagnosticButton'

$script:ConfLabel = New-Object -TypeName System.Windows.Forms.Label
$script:ConfLabel.Name = 'ConfLabel'
$script:ConfLabel.Left = 22
$script:ConfLabel.Top = 154
$script:ConfLabel.Width = 300
$script:ConfLabel.Height = 24
$script:ConfLabel.AutoEllipsis = $true

$script:ChooseButton = New-Button -Text 'Escolher arquivo .conf...' -Left 320 -Top 146 -Width 180
$script:ChooseButton.Name = 'ChooseButton'
$script:ChooseButton.Height = 32

$script:OutputBox = New-Object -TypeName System.Windows.Forms.TextBox
$script:OutputBox.Name = 'OutputBox'
$script:OutputBox.Left = 20
$script:OutputBox.Top = 192
$script:OutputBox.Width = 480
$script:OutputBox.Height = 228
$script:OutputBox.Multiline = $true
$script:OutputBox.ReadOnly = $true
$script:OutputBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$script:OutputBox.BackColor = [System.Drawing.Color]::White
$script:OutputBox.Font = New-Object -TypeName System.Drawing.Font -ArgumentList 'Consolas', 9
$script:OutputBox.Text = 'Escolha o arquivo .conf (se ainda não escolheu) e clique em Ativar.'

$script:FootLabel = New-Object -TypeName System.Windows.Forms.Label
$script:FootLabel.Left = 20
$script:FootLabel.Top = 430
$script:FootLabel.Width = 480
$script:FootLabel.Height = 30
$script:FootLabel.ForeColor = [System.Drawing.Color]::FromArgb(110, 110, 110)
$script:FootLabel.Font = New-Object -TypeName System.Drawing.Font -ArgumentList 'Segoe UI', 8
$script:FootLabel.Text = 'Só o Discord passa pelo túnel. Fechar esta janela não desativa o túnel: use Desativar.'

$script:Form.Controls.AddRange(@(
        $script:StatusLabel, $script:DetailLabel, $script:EnableButton, $script:DisableButton,
        $script:DiagnosticButton, $script:ConfLabel, $script:ChooseButton, $script:OutputBox, $script:FootLabel))

# Acompanha a ação em andamento, duas vezes por segundo.
$script:ActionTimer = New-Object -TypeName System.Windows.Forms.Timer
$script:ActionTimer.Interval = 500
$script:ActionTimer.Add_Tick({
        if ($null -eq $script:Process) {
            $script:ActionTimer.Stop()
            return
        }
        if ($script:Process.HasExited) {
            $script:ActionTimer.Stop()
            Complete-Action
            return
        }
        $text = Read-ActionOutput
        if ($text.Length -ne $script:OutputBox.TextLength) {
            $script:OutputBox.Text = $text
            $script:OutputBox.SelectionStart = $script:OutputBox.TextLength
            $script:OutputBox.ScrollToCaret()
        }
    })

# Atualiza o estado sozinho a cada 10 segundos, quando não há ação em andamento.
$script:StatusTimer = New-Object -TypeName System.Windows.Forms.Timer
$script:StatusTimer.Interval = 10000
$script:StatusTimer.Add_Tick({
        if ($null -eq $script:Process) {
            Update-StatusView
        }
    })

$script:EnableButton.Add_Click({ Start-Action -Action 'Ativar' })
$script:DisableButton.Add_Click({ Start-Action -Action 'Desativar' })
$script:DiagnosticButton.Add_Click({ Start-Action -Action 'Diagnostico' })
$script:ChooseButton.Add_Click({ Select-ConfFile })
$script:Form.Add_Shown({
        Update-StatusView
        $script:StatusTimer.Start()
    })
$script:Form.Add_FormClosing({
        $script:StatusTimer.Stop()
        $script:ActionTimer.Stop()
    })

if ($NoShow) {
    Update-StatusView
    return $script:Form
}

[System.Windows.Forms.Application]::EnableVisualStyles()
$null = $script:Form.ShowDialog()
$script:Form.Dispose()
