# install.ps1
# Installe Polarthographe sur un PC Windows :
#   - Java (Eclipse Temurin JRE) si absent
#   - AutoHotkey v2 si absent
#   - LanguageTool (serveur de correction local, port 8081)
#   - Demarrage automatique du serveur + du script a l'ouverture de session
#
# Utilisation : cloner le repo, ouvrir PowerShell dans le dossier, puis :
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
#   .\install.ps1

$ErrorActionPreference = "Stop"
$repoDir = $PSScriptRoot
$ltDir = "C:\LanguageTool"

Write-Host "=== Installation de Polarthographe ===" -ForegroundColor Cyan

# --- 1. Java ---
if (-not (Get-Command java -ErrorAction SilentlyContinue)) {
    Write-Host "Java non trouve : installation de Eclipse Temurin JRE 21 via winget..."
    winget install --id EclipseAdoptium.Temurin.21.JRE -e --accept-source-agreements --accept-package-agreements --silent
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
} else {
    Write-Host "Java deja installe."
}

# --- 2. AutoHotkey v2 ---
$ahkExe = "$env:LocalAppData\Programs\AutoHotkey\v2\AutoHotkey64.exe"
if (-not (Test-Path $ahkExe)) {
    Write-Host "AutoHotkey v2 non trouve : installation via winget..."
    winget install --id AutoHotkey.AutoHotkey -e --accept-source-agreements --accept-package-agreements --silent
} else {
    Write-Host "AutoHotkey v2 deja installe."
}
if (-not (Test-Path $ahkExe)) {
    throw "AutoHotkey v2 introuvable apres tentative d'installation. Installe-le manuellement depuis https://www.autohotkey.com/ (version 2) puis relance ce script."
}

# --- 3. LanguageTool ---
if (-not (Test-Path "$ltDir\languagetool-server.jar")) {
    Write-Host "Telechargement de LanguageTool (~250 Mo, patiente)..."
    New-Item -ItemType Directory -Force -Path $ltDir | Out-Null
    $zipPath = "$ltDir\LanguageTool-stable.zip"
    $ProgressPreference = "SilentlyContinue"
    Invoke-WebRequest -Uri "https://languagetool.org/download/LanguageTool-stable.zip" -OutFile $zipPath
    Write-Host "Extraction..."
    Expand-Archive -Path $zipPath -DestinationPath $ltDir -Force
    $extracted = Get-ChildItem $ltDir -Directory | Where-Object { $_.Name -like "LanguageTool-*" } | Select-Object -First 1
    if ($extracted) {
        Get-ChildItem $extracted.FullName | Move-Item -Destination $ltDir -Force
        Remove-Item $extracted.FullName -Recurse -Force
    }
    Remove-Item $zipPath -Force
} else {
    Write-Host "LanguageTool deja installe dans $ltDir."
}

# --- 4. Script de lancement du serveur LanguageTool ---
$javaExe = (Get-Command java -ErrorAction SilentlyContinue).Source
if (-not $javaExe) {
    $found = Get-ChildItem "C:\Program Files\Eclipse Adoptium" -Recurse -Filter "java.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    $javaExe = $found.FullName
}

$startServerTemplate = @'
$javaExe = "__JAVA_EXE__"
$jarPath = "__LT_DIR__\languagetool-server.jar"
$port    = 8081
$logOut  = "__LT_DIR__\server.log"
$logErr  = "__LT_DIR__\server.err.log"

$listening = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
if ($listening) { exit 0 }

Start-Process -FilePath $javaExe `
    -ArgumentList @("-cp", "`"$jarPath`"", "org.languagetool.server.HTTPServer", "--port", "$port") `
    -WorkingDirectory "__LT_DIR__" `
    -WindowStyle Hidden `
    -RedirectStandardOutput $logOut `
    -RedirectStandardError $logErr
'@
$startServerContent = $startServerTemplate.Replace("__JAVA_EXE__", $javaExe).Replace("__LT_DIR__", $ltDir)
Set-Content -Path "$ltDir\start-server.ps1" -Value $startServerContent -Encoding UTF8

$batContent = "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$ltDir\start-server.ps1`"`r`n"
Set-Content -Path "$ltDir\start-server.bat" -Value $batContent -Encoding ASCII

# --- 5. Tache planifiee : lancer le serveur a l'ouverture de session ---
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ltDir\start-server.ps1`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName "LanguageToolServer" -Action $action -Trigger $trigger -Settings $settings -Description "Demarre le serveur local LanguageTool pour Polarthographe." -Force | Out-Null
Write-Host "Tache planifiee 'LanguageToolServer' creee (demarrage a la connexion)."

# --- 6. Raccourci de demarrage pour le script AutoHotkey ---
$scriptPath = Join-Path $repoDir "Polarthographe.ahk"
$startupShortcut = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\Polarthographe.lnk"
$WshShell = New-Object -ComObject WScript.Shell
$shortcut = $WshShell.CreateShortcut($startupShortcut)
$shortcut.TargetPath = $ahkExe
$shortcut.Arguments = "`"$scriptPath`""
$shortcut.WorkingDirectory = $repoDir
$shortcut.Description = "Polarthographe - correcteur automatique de francais"
$shortcut.Save()
Write-Host "Raccourci de demarrage cree."

# --- 7. Lancer tout de suite (sans attendre le prochain redemarrage) ---
Write-Host "Demarrage du serveur LanguageTool..."
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ltDir\start-server.ps1"
Start-Sleep -Seconds 2

Write-Host "Demarrage de Polarthographe..."
Start-Process -FilePath $ahkExe -ArgumentList "`"$scriptPath`""

Write-Host ""
Write-Host "=== Installation terminee ===" -ForegroundColor Green
Write-Host "Ctrl+Shift+C : correction rapide"
Write-Host "Ctrl+Alt+C   : correction avec choix des suggestions"
Write-Host "Le serveur LanguageTool et Polarthographe demarreront desormais automatiquement a chaque ouverture de session."
