<#
.SYNOPSIS
  Erstellt die Single-EXE mit optional eingebetteten Screenshots.
.DESCRIPTION
  Pflichtdateien: Setup-Edge-Profil-Assistent.ps1, gorotech.png, gorotech.ico
  Optionale Screenshot-Dateien: screenshot_profil.png, screenshot_webseite.png, screenshot_favorit.png
#>
param(
  [string]$Version,
  [switch]$BumpPatch,
  [switch]$BumpMinor,
  [switch]$BumpMajor
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Log { param([string]$Message,[string]$Level='INFO'); Write-Host ('[{0}][{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message) }
function Get-AppRoot {
    try { $v = Get-Variable -Name PSScriptRoot -ValueOnly -ErrorAction SilentlyContinue; if ($v) { return $v } } catch { }
    try { $v = Get-Variable -Name PSCommandPath -ValueOnly -ErrorAction SilentlyContinue; if ($v) { return Split-Path -Parent $v } } catch { }
    try { $cmd=$MyInvocation.MyCommand; if ($cmd) { $p=$cmd.PSObject.Properties['Path']; if ($p -and $p.Value) { return Split-Path -Parent $p.Value } } } catch { }
    return (Get-Location).Path
}
function Convert-FileToBase64 { param([string]$Path); if (-not (Test-Path $Path)) { return '' }; return [Convert]::ToBase64String([IO.File]::ReadAllBytes($Path)) }

$ScriptRoot = Get-AppRoot
$ProjectRoot = Split-Path -Parent $ScriptRoot
$OutDir = Join-Path $ProjectRoot 'build'
$ReleaseDir = Join-Path $ProjectRoot 'release'
$VersionFile = Join-Path $ScriptRoot 'version.txt'
$Template = Join-Path $ScriptRoot 'Setup-Edge-Profil-Assistent.ps1'
$Embedded = Join-Path $OutDir 'Setup-Edge-Profil-Assistent_Embedded.ps1'
$Target = Join-Path $OutDir 'Edge_Profil_Assistent.exe'
$ReleaseTarget = Join-Path $ReleaseDir 'Edge_Profil_Assistent.exe'
$Logo = Join-Path $ScriptRoot 'gorotech.png'
$Icon = Join-Path $ScriptRoot 'gorotech.ico'
$DocAnwender = Join-Path $ProjectRoot 'docs\DOKUMENTATION_ANWENDER.md'
$DocTechnik = Join-Path $ProjectRoot 'docs\DOKUMENTATION_TECHNIK.md'
$ReleaseNotesLatest = Join-Path $ReleaseDir 'RELEASE_NOTES.md'
$ReleaseNotesVersioned = $null
$BuildMode = 'standard'
$VersionSource = 'parameter'

if ([string]::IsNullOrWhiteSpace($Version)) {
  $VersionSource = 'version-file'
  if (-not (Test-Path $VersionFile)) {
    [IO.File]::WriteAllText($VersionFile, 'v1.0.0', [System.Text.Encoding]::UTF8)
    Write-Log ('Version-Datei erstellt: ' + $VersionFile)
  }
  $Version = (Get-Content -Path $VersionFile -Raw -Encoding UTF8).Trim()
}

if ($Version -notmatch '^v\d+\.\d+\.\d+$') {
  throw ('Ungültige Version: ' + $Version + ' (erwartet: vX.Y.Z)')
}

$bumpCount = @($BumpPatch, $BumpMinor, $BumpMajor | Where-Object { $_ }).Count
if ($bumpCount -gt 1) {
  throw 'Bitte nur einen Bump-Schalter gleichzeitig verwenden: -BumpPatch oder -BumpMinor oder -BumpMajor.'
}

if ($BumpPatch -or $BumpMinor -or $BumpMajor) {
  if ($Version -notmatch '^v(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$') {
    throw ('Version-Bump nicht möglich, ungültige Version: ' + $Version)
  }

  $major = [int]$Matches['major']
  $minor = [int]$Matches['minor']
  $patch = [int]$Matches['patch']

  if ($BumpMajor) {
    $major++
    $minor = 0
    $patch = 0
    $Version = ('v{0}.{1}.{2}' -f $major, $minor, $patch)
    [IO.File]::WriteAllText($VersionFile, ($Version + [Environment]::NewLine), [System.Text.Encoding]::UTF8)
    Write-Log ('Major-Version erhöht und gespeichert: ' + $Version)
    $BuildMode = 'bump-major'
  } elseif ($BumpMinor) {
    $minor++
    $patch = 0
    $Version = ('v{0}.{1}.{2}' -f $major, $minor, $patch)
    [IO.File]::WriteAllText($VersionFile, ($Version + [Environment]::NewLine), [System.Text.Encoding]::UTF8)
    Write-Log ('Minor-Version erhöht und gespeichert: ' + $Version)
    $BuildMode = 'bump-minor'
  } else {
    $Version = ('v{0}.{1}.{2}' -f $major, $minor, ($patch + 1))
    [IO.File]::WriteAllText($VersionFile, ($Version + [Environment]::NewLine), [System.Text.Encoding]::UTF8)
    Write-Log ('Patch-Version erhöht und gespeichert: ' + $Version)
    $BuildMode = 'bump-patch'
  }
}

$ReleaseVersionTarget = Join-Path $ReleaseDir ('Edge_Profil_Assistent_' + $Version + '.exe')
$ReleaseNotesVersioned = Join-Path $ReleaseDir ('RELEASE_NOTES_' + $Version + '.md')
Write-Log ('Verwendete Version: ' + $Version)

if (-not (Test-Path $OutDir)) {
  New-Item -Path $OutDir -ItemType Directory -Force | Out-Null
}

if (-not (Test-Path $ReleaseDir)) {
  New-Item -Path $ReleaseDir -ItemType Directory -Force | Out-Null
}

foreach ($required in @($Template,$Logo,$Icon,$DocAnwender,$DocTechnik)) {
    if (-not (Test-Path $required)) { throw ('Benötigte Datei fehlt: ' + $required) }
}

$templateText = Get-Content -Path $Template -Raw -Encoding UTF8
$templateText = $templateText.Replace('__LOGO_BASE64__', (Convert-FileToBase64 $Logo))
$templateText = $templateText.Replace('__ICON_BASE64__', (Convert-FileToBase64 $Icon))
$templateText = $templateText.Replace('__DOC_ANWENDER_BASE64__', (Convert-FileToBase64 $DocAnwender))
$templateText = $templateText.Replace('__DOC_TECHNIK_BASE64__', (Convert-FileToBase64 $DocTechnik))
$templateText = $templateText.Replace('__SCREENSHOT_PROFIL_BASE64__', (Convert-FileToBase64 (Join-Path $ScriptRoot 'screenshot_profil.png')))
$templateText = $templateText.Replace('__SCREENSHOT_WEBSEITE_BASE64__', (Convert-FileToBase64 (Join-Path $ScriptRoot 'screenshot_webseite.png')))
$templateText = $templateText.Replace('__SCREENSHOT_FAVORIT_BASE64__', (Convert-FileToBase64 (Join-Path $ScriptRoot 'screenshot_favorit.png')))

[IO.File]::WriteAllText($Embedded, $templateText, [System.Text.Encoding]::UTF8)
Write-Log ('Eingebettete Runtime geschrieben: ' + $Embedded)

try {
  Import-Module ps2exe -ErrorAction Stop
} catch {
  Write-Log 'PS2EXE-Modul konnte nicht importiert werden. Installation wird versucht...' 'WARN'
  Install-Module ps2exe -Scope CurrentUser -Force -ErrorAction Stop
  Import-Module ps2exe -ErrorAction Stop
}

if (-not (Get-Command Invoke-ps2exe -ErrorAction SilentlyContinue)) {
  throw 'Invoke-ps2exe ist nach dem Laden des Moduls nicht verfügbar.'
}
if (Test-Path $Target) { Remove-Item $Target -Force }

$params = @{
    inputFile = $Embedded
    outputFile = $Target
    noConsole = $true
    title = 'Edge Profil-Assistent'
    product = 'Edge Profil-Assistent'
    company = 'GoroTech'
    copyright = 'GoroTech'
}
$params.iconFile = $Icon
Invoke-ps2exe @params
if (-not (Test-Path $Target)) { throw 'EXE wurde nicht erstellt.' }
Write-Log ('EXE erfolgreich erstellt: ' + $Target)

Copy-Item -Path $Target -Destination $ReleaseTarget -Force
Write-Log ('EXE nach release kopiert: ' + $ReleaseTarget)
Copy-Item -Path $Target -Destination $ReleaseVersionTarget -Force
Write-Log ('Versionierte EXE nach release kopiert: ' + $ReleaseVersionTarget)

$releaseFile = Get-Item $ReleaseVersionTarget
$sha256Versioned = (Get-FileHash -Path $ReleaseVersionTarget -Algorithm SHA256).Hash
$sha256Latest = (Get-FileHash -Path $ReleaseTarget -Algorithm SHA256).Hash
$latestFile = Get-Item $ReleaseTarget
$embeddedFile = Get-Item $Embedded
$generatedAt = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$generatedAtIso = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
$psEditionValue = $PSVersionTable.PSEdition
$psVersionValue = $PSVersionTable.PSVersion.ToString()
$osCaption = 'Windows'
try {
  $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
  if ($osInfo -and $osInfo.Caption) { $osCaption = $osInfo.Caption }
} catch { }
Write-Log ('SHA256 latest: ' + $sha256Latest)
Write-Log ('SHA256 versioned: ' + $sha256Versioned)
$notes = @"
# RELEASE_NOTES

## Version

- $Version

## Zusammenfassung

- Build erfolgreich abgeschlossen und Release-Artefakte aktualisiert.
- Versionierte EXE sowie aktuelle "latest"-EXE wurden in release/ bereitgestellt.
- Release Notes wurden automatisch im Build erzeugt.

## Build-Metadaten

- Build-Modus: $BuildMode
- Erstellt am: $generatedAt
- Erstellt am (ISO): $generatedAtIso
- Versionsquelle: $VersionSource
- Quelle Build-Skript: src/Build-Edge-Profil-Assistent.ps1
- PowerShell: $psEditionValue $psVersionValue
- Betriebssystem: $osCaption

## Artefakte

- release/Edge_Profil_Assistent.exe
- release/Edge_Profil_Assistent_$Version.exe

## Artefakt-Details

- build/Setup-Edge-Profil-Assistent_Embedded.ps1
  - Größe: $($embeddedFile.Length) Bytes
- release/Edge_Profil_Assistent.exe
  - Größe: $($latestFile.Length) Bytes
  - SHA256: $sha256Latest
- release/Edge_Profil_Assistent_$Version.exe
  - Größe: $($releaseFile.Length) Bytes
  - SHA256: $sha256Versioned

## Eingangsdateien (Build-Inputs)

- src/Setup-Edge-Profil-Assistent.ps1
- src/gorotech.png
- src/gorotech.ico
- src/screenshot_profil.png (optional)
- src/screenshot_webseite.png (optional)
- src/screenshot_favorit.png (optional)
- src/version.txt

## Qualitätssicherung (automatisch)

- Build-Skript erfolgreich ausgeführt
- PS2EXE-Kompilierung erfolgreich
- Release-Kopie (`latest` + versioniert) erfolgreich
- Release-Notes-Generierung erfolgreich

## Hinweise

- Fachliche Änderungsinhalte (Features/Fixes) können bei Bedarf manuell ergänzt werden.
- Diese Datei wird bei jedem Build neu erzeugt bzw. aktualisiert.

"@

[IO.File]::WriteAllText($ReleaseNotesVersioned, $notes, [System.Text.Encoding]::UTF8)
[IO.File]::WriteAllText($ReleaseNotesLatest, $notes, [System.Text.Encoding]::UTF8)
Write-Log ('Release Notes geschrieben: ' + $ReleaseNotesVersioned)
Write-Log ('Release Notes aktualisiert: ' + $ReleaseNotesLatest)
