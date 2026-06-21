<#
.SYNOPSIS
    Erstellt eine Single-EXE des Edge Profil-Assistenten.
.DESCRIPTION
    Liest gorotech.png und gorotech.ico, bettet beide als Base64 in die Runtime ein,
    schreibt Edge_Setup_Assistent_Final_Embedded.ps1 und kompiliert daraus Edge_Profil_Assistent.exe.
.NOTES
  Voraussetzungen im gleichen Ordner:
  - Edge_Setup_Assistent_Final.ps1
  - gorotech.png
  - gorotech.ico
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp][$Level] $Message"
}

function Get-AppRoot {
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
            if ($pathProperty -and $pathProperty.Value) { return Split-Path -Parent $pathProperty.Value }
        }
    } catch { }

    return (Get-Location).Path
}

function Convert-FileToBase64 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path $Path)) { throw ('Datei nicht gefunden: ' + $Path) }
    return [Convert]::ToBase64String([IO.File]::ReadAllBytes($Path))
}

$ScriptRoot = Get-AppRoot
$OutDir     = Join-Path $ScriptRoot 'build'
$Template   = Join-Path $ScriptRoot 'Edge_Setup_Assistent_Final.ps1'
$Embedded   = Join-Path $OutDir 'Edge_Setup_Assistent_Final_Embedded.ps1'
$Target     = Join-Path $OutDir 'Edge_Profil_Assistent.exe'
$Logo       = Join-Path $ScriptRoot 'gorotech.png'
$Icon       = Join-Path $ScriptRoot 'gorotech.ico'

Write-Log "Build-Verzeichnis: $ScriptRoot"

if (-not (Test-Path $OutDir)) {
    New-Item -Path $OutDir -ItemType Directory -Force | Out-Null
    Write-Log ('Build-Ausgabeordner erstellt: ' + $OutDir)
}

foreach ($required in @($Template, $Logo, $Icon)) {
    if (-not (Test-Path $required)) { throw ('Benötigte Datei fehlt: ' + $required) }
    Write-Log ('Datei gefunden: ' + $required)
}

Write-Log 'Ressourcen werden in Base64 umgewandelt...'
$logoBase64 = Convert-FileToBase64 -Path $Logo
$iconBase64 = Convert-FileToBase64 -Path $Icon

$templateText = Get-Content -Path $Template -Raw -Encoding UTF8
$templateText = $templateText.Replace('__LOGO_BASE64__', $logoBase64)
$templateText = $templateText.Replace('__ICON_BASE64__', $iconBase64)

[IO.File]::WriteAllText($Embedded, $templateText, [System.Text.Encoding]::UTF8)
Write-Log ('Eingebettete Runtime geschrieben: ' + $Embedded)

if (-not (Get-Command Invoke-ps2exe -ErrorAction SilentlyContinue)) {
    Write-Log 'PS2EXE nicht gefunden. Installation wird versucht...' 'WARN'
    Install-Module ps2exe -Scope CurrentUser -Force -ErrorAction Stop
}

Import-Module ps2exe -ErrorAction Stop
Write-Log 'PS2EXE geladen'

if (Test-Path $Target) {
    Write-Log 'Alte EXE wird gelöscht'
    Remove-Item $Target -Force
}

$params = @{
    inputFile  = $Embedded
    outputFile = $Target
    noConsole  = $true
    title      = 'Edge Profil-Assistent'
    product    = 'Edge Profil-Assistent'
    company    = 'K-Team Gorotech'
    copyright  = 'Gorotech'
}

if (Test-Path $Icon) {
    $params.iconFile = $Icon
}

Write-Log 'EXE-Build wird gestartet...'
Invoke-ps2exe @params

if (-not (Test-Path $Target)) {
    throw 'EXE wurde nicht erstellt.'
}

$file = Get-Item $Target
Write-Log ('EXE erfolgreich erstellt: ' + $Target)
Write-Log ('Größe: {0:N2} KB' -f ($file.Length / 1KB))
Write-Log 'Fertig. Die EXE enthält Logo, Icon und Konfiguration eingebettet.'
