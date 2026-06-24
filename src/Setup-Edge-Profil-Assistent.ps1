<#
.SYNOPSIS
    Edge Profil-Assistent - Single-EXE Runtime mit optionalen Screenshots
.DESCRIPTION
  Single-EXE-fähige WPF-GUI. Ressourcen werden zur Laufzeit nach %LOCALAPPDATA%\Temp\EdgeSetupAssistent extrahiert.
#>

#requires -version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:FixedFavoriteUrl = 'https://gorotech489.sharepoint.com'
$script:FixedFavoriteName = 'Intranet-Portal'

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

function Write-ResourceFromBase64 {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Base64,
        [Parameter(Mandatory=$true)][string]$TargetPath
    )
    $cleanBase64 = [string]$Base64
    $cleanBase64 = $cleanBase64 -replace '^data:.*?;base64,', ''
    $cleanBase64 = $cleanBase64 -replace '\s', ''
    if ([string]::IsNullOrWhiteSpace($cleanBase64)) { return $false }
    $bytes = [Convert]::FromBase64String($cleanBase64)
    [IO.File]::WriteAllBytes($TargetPath, $bytes)
    return $true
}

function Expand-EmbeddedResources {
    $runtimeBase = Join-Path $env:LOCALAPPDATA 'Temp\EdgeSetupAssistent'
    if (-not (Test-Path $runtimeBase)) { New-Item -Path $runtimeBase -ItemType Directory -Force | Out-Null }

    $processId = [System.Diagnostics.Process]::GetCurrentProcess().Id
    $runtimeRoot = Join-Path $runtimeBase ('run-' + $processId)
    if (Test-Path $runtimeRoot) {
        Remove-Item -Path $runtimeRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -Path $runtimeRoot -ItemType Directory -Force | Out-Null

    $resources = @(
        [pscustomobject]@{ Name = 'gorotech.png'; Base64 = @'
__LOGO_BASE64__
'@ },
        [pscustomobject]@{ Name = 'gorotech.ico'; Base64 = @'
__ICON_BASE64__
'@ },
        [pscustomobject]@{ Name = 'docs\DOKUMENTATION_ANWENDER.md'; Base64 = @'
__DOC_ANWENDER_BASE64__
'@ },
        [pscustomobject]@{ Name = 'docs\DOKUMENTATION_TECHNIK.md'; Base64 = @'
__DOC_TECHNIK_BASE64__
'@ },
        [pscustomobject]@{ Name = 'screenshot_profil.png'; Base64 = @'
__SCREENSHOT_PROFIL_BASE64__
'@ },
        [pscustomobject]@{ Name = 'screenshot_webseite.png'; Base64 = @'
__SCREENSHOT_WEBSEITE_BASE64__
'@ },
        [pscustomobject]@{ Name = 'screenshot_favorit.png'; Base64 = @'
__SCREENSHOT_FAVORIT_BASE64__
'@ }
    )

    foreach ($resource in $resources) {
        try {
            $target = Join-Path $runtimeRoot $resource.Name
            $targetDir = Split-Path -Parent $target
            if ($targetDir -and (-not (Test-Path $targetDir))) {
                New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
            }
            [void](Write-ResourceFromBase64 -Base64 $resource.Base64 -TargetPath $target)
        } catch {
            throw ('Eingebettete Ressource konnte nicht extrahiert werden: ' + $resource.Name + ' - ' + $_.Exception.Message)
        }
    }

    $configJson = @'
{
  "AppTitle": "Edge Profil-Assistent",
  "CompanyName": "GoroTech",
  "FavoriteUrl": "https://gorotech489.sharepoint.com",
        "FavoriteName": "Intranet-Portal",
  "ProfileNameTip": "GoroTech",
  "ThemeColor": "#0078D4",
  "LogoPath": "gorotech.png"
}
'@
    [IO.File]::WriteAllText((Join-Path $runtimeRoot 'Edge_Assistent.config.json'), $configJson, [System.Text.Encoding]::UTF8)
    return $runtimeRoot
}

$ScriptRoot = Expand-EmbeddedResources
$ConfigPath = Join-Path $ScriptRoot 'Edge_Assistent.config.json'
$DocAnwenderPath = Join-Path $ScriptRoot 'docs\DOKUMENTATION_ANWENDER.md'
$DocTechnikPath = Join-Path $ScriptRoot 'docs\DOKUMENTATION_TECHNIK.md'

$config = [ordered]@{
    AppTitle       = 'Edge Profil-Assistent'
    CompanyName    = 'GoroTech'
    FavoriteUrl    = $script:FixedFavoriteUrl
    FavoriteName   = $script:FixedFavoriteName
    ProfileNameTip = 'GoroTech'
    ThemeColor     = '#0078D4'
    LogoPath       = 'gorotech.png'
}

function Show-Warning {
    param([string]$Message)
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
        [System.Windows.MessageBox]::Show($Message, $config.AppTitle, 'OK', 'Warning') | Out-Null
    } catch { Write-Warning $Message }
}

function Open-DocumentationFile {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path $Path)) {
        Show-Warning ('Dokumentation nicht gefunden:' + [Environment]::NewLine + $Path)
        return
    }

    try {
        Start-Process -FilePath $Path | Out-Null
    } catch {
        Show-Warning ('Dokumentation konnte nicht geöffnet werden:' + [Environment]::NewLine + $_.Exception.Message)
    }
}

if (Test-Path $ConfigPath) {
    try {
        $json = Get-Content -Path $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($prop in $json.PSObject.Properties) {
            if ($config.Contains($prop.Name)) { $config[$prop.Name] = [string]$prop.Value }
        }
    } catch { Show-Warning ('Die Konfigurationsdatei konnte nicht gelesen werden:' + [Environment]::NewLine + $_.Exception.Message) }
}

# Für den Assistenten immer fest vorgeben
$config.FavoriteUrl = $script:FixedFavoriteUrl
$config.FavoriteName = $script:FixedFavoriteName

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
    foreach ($p in $candidates) { if ($p -and (Test-Path $p)) { return $p } }
    return 'msedge.exe'
}

Add-Type -AssemblyName System.Windows.Forms
if (-not ('EdgeSetupWinAPI' -as [type])) {
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class EdgeSetupWinAPI {
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
}

function Get-SplitLayout {
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $leftW = [int][Math]::Floor($screen.Width / 2)
    return [pscustomobject]@{
        LeftX      = [int]$screen.Left
        RightX     = [int]($screen.Left + $leftW)
        TopY       = [int]$screen.Top
        LeftWidth  = $leftW
        RightWidth = [int]($screen.Width - $leftW)
        Height     = [int]$screen.Height
    }
}

function Get-EdgeWindowHandle {
    param([System.Diagnostics.Process]$StartedProcess)
    for ($i = 0; $i -lt 40; $i++) {
        try {
            if ($StartedProcess) {
                $StartedProcess.Refresh()
                if ($StartedProcess.MainWindowHandle -and $StartedProcess.MainWindowHandle -ne [IntPtr]::Zero) { return $StartedProcess.MainWindowHandle }
            }
            $edgeWindow = Get-Process msedge -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -and $_.MainWindowHandle -ne [IntPtr]::Zero } | Sort-Object StartTime -Descending | Select-Object -First 1
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
        [EdgeSetupWinAPI]::ShowWindow($handle, 9) | Out-Null
        [EdgeSetupWinAPI]::MoveWindow($handle, $layout.RightX, $layout.TopY, $layout.RightWidth, $layout.Height, $true) | Out-Null
        [EdgeSetupWinAPI]::SetForegroundWindow($handle) | Out-Null
    }
}

function Start-Edge {
    param([string]$Argument)
    $edge = Get-EdgePath
    if ([string]::IsNullOrWhiteSpace($Argument)) { $proc = Start-Process -FilePath $edge -ArgumentList '--new-window' -PassThru }
    else { $proc = Start-Process -FilePath $edge -ArgumentList @('--new-window', $Argument) -PassThru }
    Start-Sleep -Milliseconds 800
    Move-EdgeToRightHalf -StartedProcess $proc
}

Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName WindowsBase

function Set-FormattedText {
    param([Parameter(Mandatory=$true)]$TextBlock, [AllowNull()][string]$Text)
    $TextBlock.Inlines.Clear()
    if ($null -eq $Text) { return }
    $parts = $Text -split '"'
    for ($i = 0; $i -lt $parts.Count; $i++) {
        $run = New-Object System.Windows.Documents.Run
        $run.Text = $parts[$i]
        if (($i % 2) -eq 1) { $run.FontWeight = [System.Windows.FontWeights]::Bold }
        $TextBlock.Inlines.Add($run)
    }
}

function Set-StepImage {
    param([AllowNull()][string]$ImageName)
    $StepImage.Visibility = 'Collapsed'
    $StepImage.Source = $null
    if ([string]::IsNullOrWhiteSpace($ImageName)) { return }
    $imagePath = Resolve-LocalPath $ImageName
    if (-not (Test-Path $imagePath)) { return }
    try {
        $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
        $bitmap.BeginInit()
        $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bitmap.UriSource = New-Object System.Uri((Resolve-Path $imagePath).Path, [System.UriKind]::Absolute)
        $bitmap.EndInit()
        $StepImage.Source = $bitmap
        $StepImage.Visibility = 'Visible'
    } catch { $StepImage.Visibility = 'Collapsed' }
}

$script:StepIndex = 0
$script:UserLoginName = ''
$script:UserPassword = ''
$script:Steps = @(
    [pscustomobject]@{ Title='Willkommen'; Image=$null; Button='Weiter'; Action={}; Body=@'
Dieser Assistent begleitet Sie Schritt für Schritt beim Einrichten eines neuen Microsoft-Edge-Profils und eines Favoriten.

Klicken Sie auf "Weiter", um zu beginnen.
'@ },
    [pscustomobject]@{ Title='Microsoft Edge öffnen'; Image=$null; Button='Edge öffnen'; Action={ Start-Edge }; Body=@'
Microsoft Edge wird jetzt geöffnet.

Falls Edge bereits geöffnet ist, können Sie direkt mit dem nächsten Schritt fortfahren.
'@ },
    [pscustomobject]@{ Title='Profil einrichten'; Image='screenshot_profil.png'; Button='Weiter'; Action={}; Body=@'
"[1]" Klicken Sie in Edge oben rechts auf das Profil-Symbol.

"[2]" Wählen Sie "Einrichten eines neuen Profils" und klicken Sie auf "Arbeit oder Schule".

"[3a]" Wählen Sie nach "Konto auswählen" den Eintrag "Neues Konto hinzufügen" aus.

oder

"[3b]" Wird Ihnen "Konto auswählen" nicht angegezeigt, wählen Sie erneut oben rechts das Profil-Symbol und wählen den Befehl "Für Synchronisierung anmelden".

"[4]" Tragen Sie links im Assistenten Ihren "Anmeldenamen" und Ihr "Kennwort" ein.

"[5]" Melden Sie sich mit diesen Daten in Edge für die Synchronisation an.
'@ },
    [pscustomobject]@{ Title='Profil benennen'; Image=$null; Button='Weiter'; Action={}; Body = @'
"[1]" Vervollständigen Sie die Anpassung des Edge-Designs für Ihr neues Profil.
		
"[2]" Klicken Sie erneut in Edge oben rechts auf das Profil-Symbol.

"[3]" Im Anschluss klicken Sie auf "Profileinstellungen".
		
"[4]" Ändern Sie die Bezeichnung Ihres neuen Profils über das Stiftsymbol ✏️. Vergeben Sie z. B. die Bezeichnung "Intranet-Portal"; wählen Sie auf Wunsch eines der angebotenen Bilder als Profilbild.
'@ },
    [pscustomobject]@{ Title='Favoriten-Webseite öffnen'; Image='screenshot_webseite.png'; Button='Webseite öffnen'; Action={ Start-Edge -Argument $config.FavoriteUrl }; Body='Jetzt wird die gewünschte Webseite geöffnet:' + [Environment]::NewLine + [Environment]::NewLine + '"' + $config.FavoriteUrl + '"' + [Environment]::NewLine + [Environment]::NewLine + 'Bitte achten Sie darauf, dass die Seite im neu erstellten Profil geöffnet ist.' + [Environment]::NewLine + [Environment]::NewLine + 'Wenn Sie gefragt werden, ob Sie automatisch an der Website angemeldet werden sollen, klicken Sie auf "Ja".' },
    [pscustomobject]@{ Title='Favorit speichern'; Image='screenshot_favorit.png'; Button='Weiter'; Action={}; Body='Klicken Sie in Edge rechts in der Adressleiste auf das Stern-Symbol ☆.' + [Environment]::NewLine + [Environment]::NewLine + 'Name-Vorschlag: "' + $config.FavoriteName + '"' + [Environment]::NewLine + 'Ordner-Vorschlag: "Favoritenleiste"' + [Environment]::NewLine + [Environment]::NewLine + 'Bestätigen Sie anschließend mit "Fertig" oder "Speichern".' },
    [pscustomobject]@{ Title='Favoritenleiste prüfen'; Image=$null; Button='Weiter'; Action={}; Body=@'
Falls Sie den Favoriten nicht direkt sehen:

[1] Öffnen Sie in Edge das Menü "...".

[2] Wählen Sie "Favoriten".

[3] Aktivieren Sie bei Bedarf die Favoritenleiste.

Tastenkombination: "Strg + Umschalt + B"
'@ },
    [pscustomobject]@{ Title='Fertig'; Image=$null; Button='Schließen'; Action={}; Body='Geschafft! Das neue Edge-Profil und der Favorit sollten nun eingerichtet sein.' + [Environment]::NewLine + [Environment]::NewLine + 'Wenn etwas nicht geklappt hat, können Sie über "Zurück" einzelne Schritte erneut anzeigen.' }
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
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="130"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="92"/>
        </Grid.RowDefinitions>
        <Border Grid.Row="0" Background="#F7F7F7" BorderBrush="#E1E1E1" BorderThickness="0,0,0,1">
            <Grid Margin="8,0,8,0">
                <Menu x:Name="TopMenu" HorizontalAlignment="Right" Background="Transparent" BorderThickness="0">
                    <MenuItem x:Name="HelpMenuRoot" Header="Hilfe">
                        <MenuItem x:Name="HelpMenuDocsAnwender" Header="Anwenderdokumentation öffnen"/>
                        <MenuItem x:Name="HelpMenuDocsTechnik" Header="Technische Dokumentation öffnen"/>
                    </MenuItem>
                </Menu>
            </Grid>
        </Border>
        <Border x:Name="HeaderBorder" Grid.Row="1">
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
        <Grid Grid.Row="2" Margin="34,24,34,24">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <TextBlock x:Name="StepTitle" Grid.Row="0" Text="" FontSize="26" FontWeight="SemiBold" Foreground="#202020" Margin="0,0,0,16"/>
            <Grid Grid.Row="1">
                <Grid.RowDefinitions>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <ScrollViewer Grid.Row="0" VerticalScrollBarVisibility="Auto">
                    <TextBlock x:Name="StepBody" FontSize="15" Foreground="#333333" TextWrapping="Wrap" LineHeight="24"/>
                </ScrollViewer>

                <Border Grid.Row="1" x:Name="CredentialsPanel" BorderBrush="#E1E1E1" BorderThickness="1" CornerRadius="6" Margin="0,10,0,0" Padding="8" Background="#FAFAFA" Visibility="Collapsed">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="150"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>

                        <TextBlock Grid.Row="0" Grid.ColumnSpan="3" Text="Benötigte Variablen" FontWeight="SemiBold" Foreground="#1F1F1F" Margin="0,0,0,6"/>

                        <TextBlock Grid.Row="1" Grid.Column="0" Text="Anmeldename:" VerticalAlignment="Center" Margin="0,0,8,4"/>
                        <TextBox x:Name="UsernameTextBox" Grid.Row="1" Grid.Column="1" Height="24" Margin="0,0,8,4" ToolTip="z. B. vorname.nachname@k-team.gorotech.de"/>
                        <Button x:Name="CopyUserButton" Grid.Row="1" Grid.Column="2" Content="Kopieren" Height="24" MinWidth="82" Margin="0,0,0,4"/>

                        <TextBlock Grid.Row="2" Grid.Column="0" Text="Kennwort:" VerticalAlignment="Center" Margin="0,0,8,4"/>
                        <PasswordBox x:Name="PasswordInputBox" Grid.Row="2" Grid.Column="1" Height="24" Margin="0,0,8,4"/>
                        <Button x:Name="CopyPasswordButton" Grid.Row="2" Grid.Column="2" Content="Kopieren" Height="24" MinWidth="82" Margin="0,0,0,4"/>

                        <TextBlock Grid.Row="3" Grid.Column="0" Text="URL / Favorit (fix):" VerticalAlignment="Center" Margin="0,0,8,0"/>
                        <StackPanel Grid.Row="3" Grid.Column="1" Orientation="Horizontal" Margin="0,0,8,0">
                            <TextBox x:Name="FavoriteUrlTextBox" Height="24" Width="270" IsReadOnly="True" Margin="0,0,6,0"/>
                            <TextBox x:Name="FavoriteTitleTextBox" Height="24" Width="170" IsReadOnly="True"/>
                        </StackPanel>
                        <StackPanel Grid.Row="3" Grid.Column="2" Orientation="Horizontal">
                            <Button x:Name="CopyUrlButton" Content="URL" Height="24" MinWidth="54" Margin="0,0,4,0"/>
                            <Button x:Name="CopyFavoriteButton" Content="Titel" Height="24" MinWidth="54"/>
                        </StackPanel>
                    </Grid>
                </Border>

                <Border Grid.Row="2" x:Name="StepImageBorder" BorderBrush="#E1E1E1" BorderThickness="1" CornerRadius="6" Margin="0,10,0,0" Padding="6" Background="#FAFAFA">
                    <Image x:Name="StepImage" Height="170" Stretch="Uniform" Visibility="Collapsed"/>
                </Border>
            </Grid>
            <Grid Grid.Row="2" Margin="0,2,0,0">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                    <TextBlock x:Name="StatusText" Text="" FontSize="12" Foreground="#707070" VerticalAlignment="Center"/>
                    <Button x:Name="ToggleVariablesButton" Content="▼ Variablen ausblenden" Height="24" Margin="14,0,0,0" Padding="10,0,10,0" Visibility="Collapsed"/>
                </StackPanel>
                <StackPanel x:Name="StepDotsPanel" Grid.Column="2" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center"/>
            </Grid>
        </Grid>
        <Border Grid.Row="3" Background="#F7F7F7" BorderBrush="#E1E1E1" BorderThickness="0,1,0,0">
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
$xaml = $xaml -replace '\\"', '"'
$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

$iconPath = Join-Path $ScriptRoot 'gorotech.ico'
if (Test-Path $iconPath) { try { $window.Icon = $iconPath } catch { } }

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
$StepImage      = $window.FindName('StepImage')
$StepImageBorder = $window.FindName('StepImageBorder')
$CredentialsPanel = $window.FindName('CredentialsPanel')
$UsernameTextBox = $window.FindName('UsernameTextBox')
$PasswordInputBox = $window.FindName('PasswordInputBox')
$FavoriteUrlTextBox = $window.FindName('FavoriteUrlTextBox')
$FavoriteTitleTextBox = $window.FindName('FavoriteTitleTextBox')
$CopyUserButton = $window.FindName('CopyUserButton')
$CopyPasswordButton = $window.FindName('CopyPasswordButton')
$CopyUrlButton = $window.FindName('CopyUrlButton')
$CopyFavoriteButton = $window.FindName('CopyFavoriteButton')
$ToggleVariablesButton = $window.FindName('ToggleVariablesButton')
$StatusText     = $window.FindName('StatusText')
$StepDotsPanel  = $window.FindName('StepDotsPanel')
$HelpMenuDocsAnwender = $window.FindName('HelpMenuDocsAnwender')
$HelpMenuDocsTechnik = $window.FindName('HelpMenuDocsTechnik')
$BackButton     = $window.FindName('BackButton')
$NextButton     = $window.FindName('NextButton')
$CancelButton   = $window.FindName('CancelButton')
$LogoBox        = $window.FindName('LogoBox')
$LogoImage      = $window.FindName('LogoImage')

$script:StepDotActiveBrush = $null
$script:StepDotCompletedBrush = $null
$script:StepDotInactiveBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(224, 224, 224))
$script:StepDotActiveForeground = [System.Windows.Media.Brushes]::White
$script:StepDotCompletedForeground = [System.Windows.Media.Brushes]::White
$script:StepDotInactiveForeground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(95, 95, 95))
$script:VariablesPanelCollapsed = $false

try {
    $brush = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($config.ThemeColor)
    $HeaderBorder.Background = $brush
    $NextButton.Background = $brush
    $script:StepDotActiveBrush = $brush
    $script:StepDotCompletedBrush = $brush.Clone()
    $script:StepDotCompletedBrush.Opacity = 0.55
} catch {
    $fallbackBrush = (New-Object System.Windows.Media.BrushConverter).ConvertFromString('#0078D4')
    $HeaderBorder.Background = $fallbackBrush
    $NextButton.Background = $fallbackBrush
    $script:StepDotActiveBrush = $fallbackBrush
    $script:StepDotCompletedBrush = $fallbackBrush.Clone()
    $script:StepDotCompletedBrush.Opacity = 0.55
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
        $bitmap.UriSource = New-Object System.Uri((Resolve-Path $LogoPath).Path, [System.UriKind]::Absolute)
        $bitmap.EndInit()
        $LogoImage.Source = $bitmap
        $LogoBox.Visibility = 'Visible'
    } catch { $LogoBox.Visibility = 'Collapsed' }
}

function Update-StepDots {
    if ($null -eq $StepDotsPanel) { return }
    $StepDotsPanel.Children.Clear()

    for ($i = 0; $i -lt $script:Steps.Count; $i++) {
        $isCompleted = ($i -lt $script:StepIndex)
        $isCurrent = ($i -eq $script:StepIndex)

        $dot = New-Object System.Windows.Controls.Border
        $dot.Width = 24
        $dot.Height = 24
        $dot.CornerRadius = New-Object System.Windows.CornerRadius 12
        $dot.Margin = New-Object System.Windows.Thickness 0,0,6,0
        $dot.Background = if ($isCurrent) { $script:StepDotActiveBrush } elseif ($isCompleted) { $script:StepDotCompletedBrush } else { $script:StepDotInactiveBrush }

        $label = New-Object System.Windows.Controls.TextBlock
        $label.Text = [string]($i + 1)
        $label.FontSize = 11
        $label.FontWeight = [System.Windows.FontWeights]::SemiBold
        $label.Foreground = if ($isCurrent) { $script:StepDotActiveForeground } elseif ($isCompleted) { $script:StepDotCompletedForeground } else { $script:StepDotInactiveForeground }
        $label.HorizontalAlignment = 'Center'
        $label.VerticalAlignment = 'Center'
        $label.TextAlignment = 'Center'

        $dot.Child = $label
        [void]$StepDotsPanel.Children.Add($dot)
    }
}

function Set-ClipboardText {
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return }
    try { [System.Windows.Clipboard]::SetText($Text) } catch { }
}

function Update-VariablesPanel {
    if ($null -ne $FavoriteUrlTextBox) { $FavoriteUrlTextBox.Text = [string]$config.FavoriteUrl }
    if ($null -ne $FavoriteTitleTextBox) { $FavoriteTitleTextBox.Text = [string]$config.FavoriteName }
    if ($null -ne $UsernameTextBox -and [string]::IsNullOrWhiteSpace($UsernameTextBox.Text) -and -not [string]::IsNullOrWhiteSpace($script:UserLoginName)) {
        $UsernameTextBox.Text = $script:UserLoginName
    }
    if ($null -ne $PasswordInputBox -and [string]::IsNullOrWhiteSpace($PasswordInputBox.Password) -and -not [string]::IsNullOrWhiteSpace($script:UserPassword)) {
        $PasswordInputBox.Password = $script:UserPassword
    }
}

function Update-Ui {
    $step = $script:Steps[$script:StepIndex]
    $StepTitle.Text = $step.Title
    Set-FormattedText -TextBlock $StepBody -Text $step.Body
    Update-VariablesPanel

    # Eingaben nur in den relevanten Schritten anzeigen:
    # 2=Profil einrichten, 4=Favoriten-Webseite öffnen, 5=Favorit speichern
    $showVariablesBase = ($script:StepIndex -in @(2,4,5))
    $showVariables = ($showVariablesBase -and (-not $script:VariablesPanelCollapsed))

    if ($null -ne $ToggleVariablesButton) {
        if ($showVariablesBase) {
            $ToggleVariablesButton.Visibility = 'Visible'
            $ToggleVariablesButton.Content = if ($script:VariablesPanelCollapsed) { '▲ Variablen einblenden' } else { '▼ Variablen ausblenden' }
        } else {
            $ToggleVariablesButton.Visibility = 'Collapsed'
            $script:VariablesPanelCollapsed = $false
        }
    }

    if ($null -ne $CredentialsPanel) {
        $CredentialsPanel.Visibility = if ($showVariables) { 'Visible' } else { 'Collapsed' }
    }

    Set-StepImage -ImageName $step.Image
    if ($StepImage.Visibility -eq 'Visible') { $StepImageBorder.Visibility = 'Visible' } else { $StepImageBorder.Visibility = 'Collapsed' }
    $StatusText.Text = 'Schritt ' + ($script:StepIndex + 1) + ' von ' + $script:Steps.Count
    Update-StepDots
    $BackButton.IsEnabled = ($script:StepIndex -gt 0)
    $NextButton.Content = $step.Button
}

$NextButton.Add_Click({
    if ($null -ne $UsernameTextBox) { $script:UserLoginName = [string]$UsernameTextBox.Text }
    if ($null -ne $PasswordInputBox) { $script:UserPassword = [string]$PasswordInputBox.Password }

    if ($script:StepIndex -eq 2) {
        if ([string]::IsNullOrWhiteSpace($script:UserLoginName) -or [string]::IsNullOrWhiteSpace($script:UserPassword)) {
            [System.Windows.MessageBox]::Show('Bitte geben Sie Anmeldename und Kennwort ein, bevor Sie fortfahren.', $config.AppTitle, 'OK', 'Warning') | Out-Null
            return
        }
    }

    try { & $script:Steps[$script:StepIndex].Action }
    catch { [System.Windows.MessageBox]::Show(('Die Aktion konnte nicht ausgeführt werden:' + [Environment]::NewLine + $_.Exception.Message), $config.AppTitle, 'OK', 'Warning') | Out-Null }
    if ($script:StepIndex -ge ($script:Steps.Count - 1)) { $window.Close() }
    else { $script:StepIndex++; Update-Ui }
})
$BackButton.Add_Click({ if ($script:StepIndex -gt 0) { $script:StepIndex--; Update-Ui } })
$CancelButton.Add_Click({ $window.Close() })
$HelpMenuDocsAnwender.Add_Click({ Open-DocumentationFile -Path $DocAnwenderPath })
$HelpMenuDocsTechnik.Add_Click({ Open-DocumentationFile -Path $DocTechnikPath })

if ($null -ne $CopyUserButton) {
    $CopyUserButton.Add_Click({
        if ($null -ne $UsernameTextBox) {
            $script:UserLoginName = [string]$UsernameTextBox.Text
            Set-ClipboardText -Text $script:UserLoginName
        }
    })
}

if ($null -ne $CopyPasswordButton) {
    $CopyPasswordButton.Add_Click({
        if ($null -ne $PasswordInputBox) {
            $script:UserPassword = [string]$PasswordInputBox.Password
            Set-ClipboardText -Text $script:UserPassword
        }
    })
}

if ($null -ne $CopyUrlButton) {
    $CopyUrlButton.Add_Click({ Set-ClipboardText -Text ([string]$config.FavoriteUrl) })
}

if ($null -ne $CopyFavoriteButton) {
    $CopyFavoriteButton.Add_Click({ Set-ClipboardText -Text ([string]$config.FavoriteName) })
}

if ($null -ne $ToggleVariablesButton) {
    $ToggleVariablesButton.Add_Click({
        $script:VariablesPanelCollapsed = -not $script:VariablesPanelCollapsed
        Update-Ui
    })
}

Update-Ui
[void]$window.ShowDialog()
