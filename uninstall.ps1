# uninstall.ps1
# Retire Polarthographe : arrete les processus, supprime la tache planifiee,
# le raccourci de demarrage et le dossier LanguageTool.
# N'installe/ne desinstalle PAS Java ni AutoHotkey (utilises potentiellement
# par d'autres programmes).

$ErrorActionPreference = "SilentlyContinue"

Write-Host "=== Desinstallation de Polarthographe ===" -ForegroundColor Cyan

Stop-Process -Name "java" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "AutoHotkey64" -Force -ErrorAction SilentlyContinue
Write-Host "Processus arretes."

Unregister-ScheduledTask -TaskName "LanguageToolServer" -Confirm:$false -ErrorAction SilentlyContinue
Write-Host "Tache planifiee supprimee."

Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\Polarthographe.lnk" -Force -ErrorAction SilentlyContinue
Write-Host "Raccourci de demarrage supprime."

Remove-Item "C:\LanguageTool" -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Dossier C:\LanguageTool supprime."

Write-Host ""
Write-Host "=== Desinstallation terminee ===" -ForegroundColor Green
Write-Host "Le dossier du repo (Polarthographe.ahk, install.ps1...) n'a pas ete touche : supprime-le manuellement si besoin."
Write-Host "Java et AutoHotkey v2 restent installes (utilise 'winget uninstall' si tu veux aussi les retirer)."
