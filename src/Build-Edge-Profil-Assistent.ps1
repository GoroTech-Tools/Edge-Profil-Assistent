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
function Move-ExistingReleaseFilesToArchive {
  param(
    [Parameter(Mandatory=$true)][string]$ReleasePath,
    [Parameter(Mandatory=$true)][string]$ArchivePath
  )

  if (-not (Test-Path $ArchivePath)) {
    New-Item -Path $ArchivePath -ItemType Directory -Force | Out-Null
  }

  $archiveStamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
  $releaseFiles = @(Get-ChildItem -Path $ReleasePath -File -ErrorAction SilentlyContinue)
  foreach ($releaseFile in $releaseFiles) {
    $archiveTarget = Join-Path $ArchivePath $releaseFile.Name
    if (Test-Path $archiveTarget) {
      $archiveTarget = Join-Path $ArchivePath (
        '{0}_{1}{2}' -f $releaseFile.BaseName, $archiveStamp, $releaseFile.Extension
      )
      $collisionIndex = 2
      while (Test-Path $archiveTarget) {
        $archiveTarget = Join-Path $ArchivePath (
          '{0}_{1}_{2}{3}' -f $releaseFile.BaseName, $archiveStamp, $collisionIndex, $releaseFile.Extension
        )
        $collisionIndex++
      }
    }

    Move-Item -Path $releaseFile.FullName -Destination $archiveTarget -Force
    Write-Log ('Älteres Release archiviert: ' + $releaseFile.Name)
  }
}

$ScriptRoot = Get-AppRoot
$ProjectRoot = Split-Path -Parent $ScriptRoot
$OutDir = Join-Path $ProjectRoot 'build'
$ReleaseDir = Join-Path $ProjectRoot 'release'
$ReleaseArchiveDir = Join-Path $ReleaseDir '_Archiv'
$VersionFile = Join-Path $ScriptRoot 'version.txt'
$Template = Join-Path $ScriptRoot 'Setup-Edge-Profil-Assistent.ps1'
$Embedded = Join-Path $OutDir 'Setup-Edge-Profil-Assistent_Embedded.ps1'
$Target = Join-Path $OutDir 'Edge_Profil_Assistent.exe'
$Logo = Join-Path $ScriptRoot 'gorotech.png'
$Icon = Join-Path $ScriptRoot 'gorotech.ico'
$DocAnwender = Join-Path $ProjectRoot 'docs\DOKUMENTATION_ANWENDER.md'
$DocTechnik = Join-Path $ProjectRoot 'docs\DOKUMENTATION_TECHNIK.md'
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

if (-not (Test-Path $ReleaseArchiveDir)) {
  New-Item -Path $ReleaseArchiveDir -ItemType Directory -Force | Out-Null
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

Move-ExistingReleaseFilesToArchive -ReleasePath $ReleaseDir -ArchivePath $ReleaseArchiveDir

Copy-Item -Path $Target -Destination $ReleaseVersionTarget -Force
Write-Log ('Versionierte EXE nach release kopiert: ' + $ReleaseVersionTarget)

$releaseFile = Get-Item $ReleaseVersionTarget
$sha256Versioned = (Get-FileHash -Path $ReleaseVersionTarget -Algorithm SHA256).Hash
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
Write-Log ('SHA256 versioned: ' + $sha256Versioned)
$notes = @"
# RELEASE_NOTES

## Version

- $Version

## Zusammenfassung

- Build erfolgreich abgeschlossen und Release-Artefakte aktualisiert.
- Versionierte EXE und versionierte Release Notes wurden in release/ bereitgestellt.
- Ältere Release-Dateien werden in release/_Archiv/ aufbewahrt.
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

- release/Edge_Profil_Assistent_$Version.exe

## Artefakt-Details

- build/Setup-Edge-Profil-Assistent_Embedded.ps1
  - Größe: $($embeddedFile.Length) Bytes
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
- Versioniertes Release-Artefakt erfolgreich bereitgestellt
- Release-Notes-Generierung erfolgreich

## Hinweise

- Fachliche Änderungsinhalte (Features/Fixes) können bei Bedarf manuell ergänzt werden.
- Diese Datei wird bei jedem Build neu erzeugt bzw. aktualisiert.

"@

[IO.File]::WriteAllText($ReleaseNotesVersioned, $notes, [System.Text.Encoding]::UTF8)
Write-Log ('Release Notes geschrieben: ' + $ReleaseNotesVersioned)
