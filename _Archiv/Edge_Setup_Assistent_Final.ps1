<#
.SYNOPSIS
    Edge Profil-Assistent - Single-EXE Runtime
.DESCRIPTION
  Enthält eingebettete Ressourcen und extrahiert sie zur Laufzeit nach %LOCALAPPDATA%\Temp\EdgeSetupAssistent.
  Der Assistent wird links auf dem Hauptbildschirm platziert, Microsoft Edge rechts.
#>

#requires -version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

function Get-AppRoot {
    try {
        $processPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        $processName = [System.IO.Path]::GetFileNameWithoutExtension($processPath)

        if (
            $processPath -and
            $processName -and
            $processName -notin @('powershell', 'pwsh', 'powershell_ise')
        ) {
            return Split-Path -Parent $processPath
        }
    } catch { }

    try {
        $psScriptRootValue = Get-Variable -Name PSScriptRoot -ValueOnly -ErrorAction SilentlyContinue
        if ($psScriptRootValue) { return $psScriptRootValue }
    } catch { }

    try {
        $psCommandPathValue = Get-Variable -Name PSCommandPath -ValueOnly -ErrorAction SilentlyContinue
        if ($psCommandPathValue) { return Split-Path -Parent $psCommandPathValue }
    } catch { }

    try {
        $cmd = $MyInvocation.MyCommand
        if ($cmd) {
            $pathProperty = $cmd.PSObject.Properties['Path']
            if ($pathProperty -and $pathProperty.Value) {
                return Split-Path -Parent $pathProperty.Value
            }
        }
    } catch { }

    return (Get-Location).Path
}

function Write-ResourceFromBase64 {
    param(
        [Parameter(Mandatory=$true)][string]$Base64,
        [Parameter(Mandatory=$true)][string]$TargetPath
    )

    $cleanBase64 = [string]$Base64
    $cleanBase64 = $cleanBase64 -replace '^data:.*?;base64,', ''
    $cleanBase64 = $cleanBase64 -replace '\s', ''

    if ([string]::IsNullOrWhiteSpace($cleanBase64)) {
        throw ('Base64-Inhalt ist leer: ' + $TargetPath)
    }

    $bytes = [Convert]::FromBase64String($cleanBase64)
    [IO.File]::WriteAllBytes($TargetPath, $bytes)
}

function Expand-EmbeddedResources {
    $runtimeRoot = Join-Path $env:LOCALAPPDATA 'Temp\EdgeSetupAssistent'

    if (-not (Test-Path $runtimeRoot)) {
        New-Item -Path $runtimeRoot -ItemType Directory -Force | Out-Null
    }

    $logoBase64 = @'
__LOGO_BASE64__
'@

    $iconBase64 = @'
__LOGO_BASE64__
'@

    $configJson = @'
{
  "AppTitle": "Edge Profil-Assistent",
  "CompanyName": "GoroTech",
  "FavoriteUrl": "https://gorotech489.sharepoint.com",
  "FavoriteName": "Intranet-Portal der Kaufleute",
  "ProfileNameTip": "GoroTech",
  "ThemeColor": "#0078D4",
  "LogoPath": "gorotech.png"
}
'@

    try {
        Write-ResourceFromBase64 -Base64 $logoBase64 -TargetPath (Join-Path $runtimeRoot 'gorotech.png')
        Write-ResourceFromBase64 -Base64 $iconBase64 -TargetPath (Join-Path $runtimeRoot 'gorotech.ico')
        [IO.File]::WriteAllText((Join-Path $runtimeRoot 'Edge_Assistent.config.json'), $configJson, [System.Text.Encoding]::UTF8)
    } catch {
        throw ('Eingebettete Ressourcen konnten nicht vorbereitet werden: ' + $_.Exception.Message)
    }

    return $runtimeRoot
}


$ScriptRoot = Expand-EmbeddedResources
$ConfigPath = Join-Path -Path $ScriptRoot -ChildPath 'Edge_Assistent.config.json'

$config = [ordered]@{
    AppTitle       = 'Edge Profil-Assistent'
    CompanyName    = 'GoroTech'
    FavoriteUrl    = 'https://gorotech489.sharepoint.com'
    FavoriteName   = 'Intranet-Portal der Kaufleute'
    ProfileNameTip = 'GoroTech'
    ThemeColor     = '#0078D4'
    LogoPath       = 'gorotech.png'
}

function Show-Warning {
    param([string]$Message)
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
        [System.Windows.MessageBox]::Show($Message, $config.AppTitle, 'OK', 'Warning') | Out-Null
    } catch {
        Write-Warning $Message
    }
}

if (Test-Path $ConfigPath) {
    try {
        $json = Get-Content -Path $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($prop in $json.PSObject.Properties) {
            if ($config.Contains($prop.Name)) {
                $config[$prop.Name] = [string]$prop.Value
            }
        }
    } catch {
        Show-Warning ('Die Konfigurationsdatei konnte nicht gelesen werden:' + [Environment]::NewLine + $_.Exception.Message)
    }
}

function Resolve-LocalPath {
    param([string]$PathValue)
    if ([string]::IsNullOrWhiteSpace($PathValue)) { return $null }
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return Join-Path $ScriptRoot $PathValue
}

function Get-EdgePath {
    $candidates = New-Object System.Collections.Generic.List[string]
    if ($env:ProgramFiles) { $candidates.Add((Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe')) }
    if (${env:ProgramFiles(x86)}) { $candidates.Add((Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe')) }
    if ($env:LOCALAPPDATA) { $candidates.Add((Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\Application\msedge.exe')) }

    foreach ($p in $candidates) {
        if ($p -and (Test-Path $p)) { return $p }
    }
    return 'msedge.exe'
}

Add-Type -AssemblyName System.Windows.Forms

if (-not ('EdgeSetupWinAPI' -as [type])) {
Add-Type @"
using System;
using System.Runtime.InteropServices;

public class EdgeSetupWinAPI {
    [DllImport("user32.dll")]
    public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
}

function Get-PrimaryWorkingArea {
    return [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
}

function Get-SplitLayout {
    $screen = Get-PrimaryWorkingArea

    $leftX  = [int]$screen.Left
    $topY   = [int]$screen.Top
    $leftW  = [int][Math]::Floor($screen.Width / 2)
    $rightX = [int]($screen.Left + $leftW)
    $rightW = [int]($screen.Width - $leftW)
    $height = [int]$screen.Height

    return [pscustomobject]@{
        LeftX      = $leftX
        RightX     = $rightX
        TopY       = $topY
        LeftWidth  = $leftW
        RightWidth = $rightW
        Height     = $height
    }
}

function Get-EdgeWindowHandle {
    param([System.Diagnostics.Process]$StartedProcess)

    for ($i = 0; $i -lt 40; $i++) {
        try {
            if ($StartedProcess) {
                $StartedProcess.Refresh()
                if ($StartedProcess.MainWindowHandle -and $StartedProcess.MainWindowHandle -ne [IntPtr]::Zero) {
                    return $StartedProcess.MainWindowHandle
                }
            }

            $edgeWindow = Get-Process msedge -ErrorAction SilentlyContinue |
                Where-Object { $_.MainWindowHandle -and $_.MainWindowHandle -ne [IntPtr]::Zero } |
                Sort-Object StartTime -Descending |
                Select-Object -First 1

            if ($edgeWindow) { return $edgeWindow.MainWindowHandle }
        } catch { }

        Start-Sleep -Milliseconds 200
    }

    return [IntPtr]::Zero
}

function Move-EdgeToRightHalf {
    param([System.Diagnostics.Process]$StartedProcess)

    $layout = Get-SplitLayout
    $handle = Get-EdgeWindowHandle -StartedProcess $StartedProcess

    if ($handle -and $handle -ne [IntPtr]::Zero) {
        [EdgeSetupWinAPI]::ShowWindow($handle, 9) | Out-Null # SW_RESTORE
        [EdgeSetupWinAPI]::MoveWindow($handle, $layout.RightX, $layout.TopY, $layout.RightWidth, $layout.Height, $true) | Out-Null
        [EdgeSetupWinAPI]::SetForegroundWindow($handle) | Out-Null
    }
}

function Start-Edge {
    param([string]$Argument)

    $edge = Get-EdgePath

    if ([string]::IsNullOrWhiteSpace($Argument)) {
        $proc = Start-Process -FilePath $edge -ArgumentList '--new-window' -PassThru
    } else {
        $proc = Start-Process -FilePath $edge -ArgumentList @('--new-window', $Argument) -PassThru
    }

    Start-Sleep -Milliseconds 800
    Move-EdgeToRightHalf -StartedProcess $proc
}

Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName WindowsBase

function Set-FormattedText {
    param(
        [Parameter(Mandatory=$true)]$TextBlock,
        [AllowNull()][string]$Text
    )

    $TextBlock.Inlines.Clear()

    if ($null -eq $Text) { return }

    $parts = $Text -split '"'

    for ($i = 0; $i -lt $parts.Count; $i++) {
        $run = New-Object System.Windows.Documents.Run
        $run.Text = $parts[$i]

        if (($i % 2) -eq 1) {
            $run.FontWeight = [System.Windows.FontWeights]::Bold
        }

        $TextBlock.Inlines.Add($run)
    }
}

$script:StepIndex = 0
$script:Steps = @(
    [pscustomobject]@{
        Title = 'Willkommen'
        Body = @'
Dieser Assistent begleitet Sie Schritt für Schritt beim Einrichten eines neuen Microsoft-Edge-Profils und eines Favoriten.

Klicken Sie auf "Weiter", um zu beginnen.
'@
        Button = 'Weiter'
        Action = { }
    },
    [pscustomobject]@{
        Title = 'Microsoft Edge öffnen'
        Body = @'
Microsoft Edge wird jetzt geöffnet.

Falls Edge bereits geöffnet ist, können Sie direkt mit dem nächsten Schritt fortfahren.
'@
        Button = 'Edge öffnen'
        Action = { Start-Edge }
    },
    [pscustomobject]@{
        Title = 'Profil einrichten'
        Body = @'
"[1]" Klicken Sie in Edge oben rechts auf das Profil-Symbol.

"[2]" Wählen Sie "Einrichten eines neuen Profils" und klicken Sie auf "Arbeit oder Schule".

"[3]" Wählen Sie nach "Konto auswählen" den Eintrag "Neues Konto hinzufügen" aus.

"[4]" Melden Sie sich mit Ihrer E-Mail-Adresse in der Form "vorname.nachname@k-team.gorotech.de" und Ihrem Kennwort für die Synchronisation an.
'@
        Button = 'Weiter'
        Action = { }
    },
    [pscustomobject]@{
        Title = 'Profil benennen'
        Body = @'
"[1]" Vervollständigen Sie die Anpassung des Edge-Designs für Ihr neues Profil.
		
"[2]" Klicken Sie erneut in Edge oben rechts auf das Profil-Symbol.

"[3]" Im Anschluss klicken Sie auf "Profileinstellungen".
		
"[4]" Ändern Sie die Bezeichnung Ihres neuen Profils über das Stiftsymbol ✏️. Vergeben Sie z. B. die Bezeichnung "Intranet-Portal"; wählen Sie auf Wunsch eines der angebotenen Bilder als Profilbild.
'@
        Button = 'Weiter'
        Action = { }
    },
    [pscustomobject]@{
        Title = 'Favoriten-Webseite öffnen'
        Body = 'Jetzt wird die gewünschte Webseite geöffnet:' + [Environment]::NewLine + [Environment]::NewLine + '"' + $config.FavoriteUrl + '"' + [Environment]::NewLine + [Environment]::NewLine + 'Bitte achten Sie darauf, dass die Seite im neu erstellten Profil geöffnet ist.' + [Environment]::NewLine + [Environment]::NewLine + 'Wenn Sie gefragt werden, ob Sie automatisch an der Website angemeldet werden sollen, klicken Sie auf "Ja".'
        Button = 'Webseite öffnen'
        Action = { Start-Edge -Argument $config.FavoriteUrl }
    },
    [pscustomobject]@{
        Title = 'Favorit speichern'
        Body = 'Klicken Sie in Edge rechts in der Adressleiste auf das Stern-Symbol ☆.' + [Environment]::NewLine + [Environment]::NewLine + 'Name-Vorschlag: "' + $config.FavoriteName + '"' + [Environment]::NewLine + 'Ordner-Vorschlag: "Favoritenleiste"' + [Environment]::NewLine + [Environment]::NewLine + 'Bestätigen Sie anschließend mit "Fertig" oder "Speichern".'
        Button = 'Weiter'
        Action = { }
    },
    [pscustomobject]@{
        Title = 'Favoritenleiste prüfen'
        Body = @'
Falls Sie den Favoriten nicht direkt sehen:

[1] Öffnen Sie in Edge das Menü "...".

[2] Wählen Sie "Favoriten".

[3] Aktivieren Sie bei Bedarf die Favoritenleiste.

Tastenkombination: "Strg + Umschalt + B"
'@
        Button = 'Weiter'
        Action = { }
    },
    [pscustomobject]@{
        Title = 'Fertig'
        Body = 'Geschafft! Das neue Edge-Profil und der Favorit sollten nun eingerichtet sein.' + [Environment]::NewLine + [Environment]::NewLine + 'Wenn etwas nicht geklappt hat, können Sie über "Zurück" einzelne Schritte erneut anzeigen.'
        Button = 'Schließen'
        Action = { }
    }
)

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="760" Height="650"
        WindowStartupLocation="Manual"
        ResizeMode="NoResize"
        Background="White"
        FontFamily="Segoe UI">
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="130"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="92"/>
        </Grid.RowDefinitions>
        <Border x:Name="HeaderBorder" Grid.Row="0">
            <Grid Margin="24,14,24,14">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="120"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Border x:Name="LogoBox" Grid.Column="0" Width="100" Height="100" CornerRadius="10" Background="#22FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed">
                    <Image x:Name="LogoImage" Stretch="Uniform" Margin="4"/>
                </Border>
                <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="14,0,0,0">
                    <TextBlock x:Name="HeaderTitle" Text="" FontSize="22" FontWeight="SemiBold" Foreground="White"/>
                    <TextBlock x:Name="HeaderSubTitle" Text="" FontSize="12" Foreground="#EAF4FF" Margin="0,5,0,0"/>
                </StackPanel>
            </Grid>
        </Border>
        <Grid Grid.Row="1" Margin="34,30,34,30">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <TextBlock x:Name="StepTitle" Grid.Row="0" Text="" FontSize="26" FontWeight="SemiBold" Foreground="#202020" Margin="0,0,0,20"/>
            <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
                <TextBlock x:Name="StepBody" FontSize="15" Foreground="#333333" TextWrapping="Wrap" LineHeight="24"/>
            </ScrollViewer>
            <ProgressBar x:Name="Progress" Grid.Row="2" Height="18" Minimum="0" Maximum="7" Margin="0,16,0,8"/>
            <TextBlock x:Name="StatusText" Grid.Row="3" Text="" FontSize="12" Foreground="#707070"/>
        </Grid>
        <Border Grid.Row="2" Background="#F7F7F7" BorderBrush="#E1E1E1" BorderThickness="0,1,0,0">
            <Grid Margin="30,20,30,20">
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Left">
                    <Button x:Name="CancelButton" Content="Abbrechen" Width="110" Height="34"/>
                </StackPanel>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                    <Button x:Name="BackButton" Content="Zurück" Width="110" Height="34" Margin="0,0,10,0"/>
                    <Button x:Name="NextButton" Content="Weiter" Width="140" Height="34" Foreground="White" BorderThickness="0"/>
                </StackPanel>
            </Grid>
        </Border>
    </Grid>
</Window>
'@

# Raw-string/Template-Schutz: XAML muss echte Anführungszeichen enthalten.
$xaml = $xaml -replace '\\"', '"'

$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

$iconPath = Join-Path $ScriptRoot 'gorotech.ico'
if (Test-Path $iconPath) {
    try { $window.Icon = $iconPath } catch { }
}

$window.WindowStartupLocation = 'Manual'

$window.Add_SourceInitialized({
    $layout = Get-SplitLayout
    $helper = New-Object System.Windows.Interop.WindowInteropHelper($window)
    [EdgeSetupWinAPI]::MoveWindow($helper.Handle, $layout.LeftX, $layout.TopY, $layout.LeftWidth, $layout.Height, $true) | Out-Null
})

$layout = Get-SplitLayout
$window.Left = $layout.LeftX
$window.Top = $layout.TopY
$window.Width = $layout.LeftWidth
$window.Height = $layout.Height

$HeaderBorder   = $window.FindName('HeaderBorder')
$HeaderTitle    = $window.FindName('HeaderTitle')
$HeaderSubTitle = $window.FindName('HeaderSubTitle')
$StepTitle      = $window.FindName('StepTitle')
$StepBody       = $window.FindName('StepBody')
$Progress       = $window.FindName('Progress')
$StatusText     = $window.FindName('StatusText')
$BackButton     = $window.FindName('BackButton')
$NextButton     = $window.FindName('NextButton')
$CancelButton   = $window.FindName('CancelButton')
$LogoBox        = $window.FindName('LogoBox')
$LogoImage      = $window.FindName('LogoImage')

try {
    $brush = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($config.ThemeColor)
    $HeaderBorder.Background = $brush
    $NextButton.Background = $brush
} catch {
    $fallbackBrush = (New-Object System.Windows.Media.BrushConverter).ConvertFromString('#0078D4')
    $HeaderBorder.Background = $fallbackBrush
    $NextButton.Background = $fallbackBrush
}

$window.Title = $config.AppTitle
$HeaderTitle.Text = $config.AppTitle
$HeaderSubTitle.Text = $config.CompanyName

$LogoPath = Resolve-LocalPath $config.LogoPath
if ($LogoPath -and (Test-Path $LogoPath)) {
    try {
        $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
        $bitmap.BeginInit()
        $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bitmap.UriSource = New-Object System.Uri($LogoPath, [System.UriKind]::Absolute)
        $bitmap.EndInit()
        $LogoImage.Source = $bitmap
        $LogoBox.Visibility = 'Visible'
    } catch {
        $LogoBox.Visibility = 'Collapsed'
    }
}

function Update-Ui {
    $step = $script:Steps[$script:StepIndex]
    $StepTitle.Text = $step.Title
    Set-FormattedText -TextBlock $StepBody -Text $step.Body
    $Progress.Maximum = $script:Steps.Count - 1
    $Progress.Value = $script:StepIndex
    $StatusText.Text = 'Schritt ' + ($script:StepIndex + 1) + ' von ' + $script:Steps.Count
    $BackButton.IsEnabled = ($script:StepIndex -gt 0)
    $NextButton.Content = $step.Button
}

$NextButton.Add_Click({
    try {
        & $script:Steps[$script:StepIndex].Action
    } catch {
        [System.Windows.MessageBox]::Show(('Die Aktion konnte nicht ausgeführt werden:' + [Environment]::NewLine + $_.Exception.Message), $config.AppTitle, 'OK', 'Warning') | Out-Null
    }

    if ($script:StepIndex -ge ($script:Steps.Count - 1)) {
        $window.Close()
    } else {
        $script:StepIndex++
        Update-Ui
    }
})

$BackButton.Add_Click({
    if ($script:StepIndex -gt 0) {
        $script:StepIndex--
        Update-Ui
    }
})

$CancelButton.Add_Click({ $window.Close() })

Update-Ui
[void]$window.ShowDialog()
