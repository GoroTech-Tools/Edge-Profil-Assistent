# Edge Profil-Assistent (Single-EXE)

Diese README beschreibt die aktuelle Single-EXE-Variante des Edge Profil-Assistenten mit optionalen Screenshots je Schritt.

## Schnellstart

- [Anwenderdokumentation öffnen](docs/DOKUMENTATION_ANWENDER.md)
- [Technische Dokumentation öffnen](docs/DOKUMENTATION_TECHNIK.md)
- [Zum Build-Abschnitt springen](#build)
- [Zu automatischen GitHub-Releases springen](#github-releases-automatisch)
- [Aktuelle Releases auf GitHub ansehen](https://github.com/GoroTech-Tools/Edge-Profil-Assistent/releases)

## Dokumentation

- [Anwenderdokumentation](docs/DOKUMENTATION_ANWENDER.md)
- [Technische Dokumentation](docs/DOKUMENTATION_TECHNIK.md)

## Projektdateien

Pflicht im Quellordner `src/`:

- `src/Setup-Edge-Profil-Assistent.ps1`
- `src/Build-Edge-Profil-Assistent.ps1`
- `src/gorotech.png`
- `src/gorotech.ico`

Optional im Quellordner `src/`:

- `src/screenshot_profil.png` – wird im Schritt „Profil einrichten“ angezeigt
- `src/screenshot_webseite.png` – wird im Schritt „Favoriten-Webseite öffnen“ angezeigt
- `src/screenshot_favorit.png` – wird im Schritt „Favorit speichern“ angezeigt

Wenn optionale Screenshots fehlen, wird die EXE trotzdem gebaut; der jeweilige Bildbereich bleibt dann ausgeblendet.

Archivierte Altdateien:

- `_Archiv/Build-EXE.ps1`
- `_Archiv/Edge_Setup_Assistent_Final.ps1`
- `_Archiv/Edge_Setup_Assistent_starten.cmd`
- `_Archiv/Edge_Assistent.config.json`

Hinweis: Die Laufzeit-Konfiguration wird beim Start der Single-EXE automatisch im Temp-Verzeichnis erzeugt.

## Build

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\src\Build-Edge-Profil-Assistent.ps1
```

Versionierung:

- Standard ohne Parameter: Version wird aus `src/version.txt` gelesen (Format `vX.Y.Z`).
- Optional explizit: `-Version v1.0.0`
- Optional Patch erhöhen: `-BumpPatch` (z. B. `v1.0.0` → `v1.0.1`, wird in `src/version.txt` gespeichert)
- Optional Minor erhöhen: `-BumpMinor` (z. B. `v1.0.1` → `v1.1.0`, wird in `src/version.txt` gespeichert)
- Optional Major erhöhen: `-BumpMajor` (z. B. `v1.1.0` → `v2.0.0`, wird in `src/version.txt` gespeichert)
- Hinweis: Es kann immer nur **ein** Bump-Schalter pro Build verwendet werden.

Beispiel mit expliziter Version:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\src\Build-Edge-Profil-Assistent.ps1 -Version v1.0.0
```

Beispiel mit automatischem Patch-Bump:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\src\Build-Edge-Profil-Assistent.ps1 -BumpPatch
```

Beispiel mit automatischem Minor-Bump:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\src\Build-Edge-Profil-Assistent.ps1 -BumpMinor
```

Beispiel mit automatischem Major-Bump:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\src\Build-Edge-Profil-Assistent.ps1 -BumpMajor
```

Ergebnis:

```text
build\Edge_Profil_Assistent.exe
```

Zusätzlich in `release/`:

- `Edge_Profil_Assistent_vX.Y.Z.exe` (versioniert)
- `RELEASE_NOTES_vX.Y.Z.md` (versioniert, automatisch je Build erzeugt)
- `_Archiv/` (ältere Release-Artefakte)

Die EXE enthält Logo, Icon, JSON-Konfiguration und vorhandene Screenshots eingebettet.

## GitHub Releases (automatisch)

Es gibt einen GitHub-Workflow unter `.github/workflows/release.yml`, der bei jedem Tag im Format `vX.Y.Z` automatisch:

1. die EXE baut,
2. die Release-Notes aus `release/RELEASE_NOTES_vX.Y.Z.md` verwendet,
3. einen GitHub Release mit den Artefakten veröffentlicht.

Trigger:

- `push` auf Tag `v*.*.*` (empfohlen)
- manuell über `workflow_dispatch` mit Eingabe `version`

Typischer Ablauf für eine neue Version:

1. Lokal Version erhöhen (z. B. mit `-BumpPatch`), testen und committen.
2. Tag erstellen (`vX.Y.Z`) und pushen.
3. GitHub Actions erstellt den Release automatisch.
