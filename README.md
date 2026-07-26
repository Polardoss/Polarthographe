# Polarthographe

Correcteur automatique de français, activable par un raccourci clavier global, utilisable dans **n'importe quelle application Windows** (Discord, navigateur, éditeur de texte, etc.).

- Sélectionne du texte n'importe où
- Appuie sur un raccourci
- Le texte sélectionné est remplacé par sa version corrigée (orthographe + grammaire)

**100% local et gratuit** : la correction est faite par un serveur [LanguageTool](https://languagetool.org/) qui tourne sur ta propre machine (`localhost:8081`). Aucun texte n'est envoyé à un service externe.

## Fonctionnement

```
Sélection de texte --[Ctrl+C]--> AutoHotkey --[HTTP local]--> LanguageTool (localhost:8081)
                                                                     |
Presse-papiers <--[Ctrl+V]-- Texte corrigé <--[JSON]----------------+
```

Deux raccourcis, deux modes :

| Raccourci | Mode | Comportement |
|---|---|---|
| **Ctrl+Alt+V** | Rapide | Corrige tout automatiquement, prend toujours la meilleure suggestion, aucune interruption |
| **Ctrl+Alt+C** | Avec choix | Pour chaque faute ayant plusieurs suggestions possibles (souvent les fautes d'orthographe pure), un petit menu te laisse choisir la bonne |

> `Ctrl+Shift+C` n'est volontairement pas utilisé : c'est le raccourci natif "Inspecter l'élément" dans la quasi-totalité des navigateurs (Chrome, Edge, Opera, Firefox), qui l'intercepte avant qu'AutoHotkey ne le voie.

## Prérequis

- Windows 10 (1809+) ou Windows 11, avec [winget](https://learn.microsoft.com/fr-fr/windows/package-manager/winget/) (déjà présent sur les installations à jour ; sinon installable via le Microsoft Store en cherchant "App Installer")
- Une connexion internet le temps de l'installation (téléchargement de Java, AutoHotkey et LanguageTool — environ 300 Mo au total)

## Installation

### Option automatique (recommandée)

```powershell
git clone https://github.com/Polardoss/Polarthographe.git
cd Polarthographe
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
.\install.ps1
```

Le script `install.ps1` :
1. Installe Java (Eclipse Temurin JRE 21) si absent, via `winget`
2. Installe AutoHotkey v2 si absent, via `winget`
3. Télécharge et installe LanguageTool dans `C:\LanguageTool`
4. Crée une tâche planifiée pour démarrer le serveur LanguageTool à l'ouverture de session
5. Crée un raccourci dans le dossier Démarrage pour lancer le script de correction automatiquement
6. Lance immédiatement le serveur et le script (pas besoin de redémarrer pour tester)

### Option manuelle

1. Installe [Java](https://adoptium.net/) (JRE 8 ou plus récent).
2. Télécharge [LanguageTool (version standalone)](https://languagetool.org/download/), dézippe-le, par exemple dans `C:\LanguageTool`.
3. Lance le serveur : `java -cp C:\LanguageTool\languagetool-server.jar org.languagetool.server.HTTPServer --port 8081`
4. Installe [AutoHotkey v2](https://www.autohotkey.com/).
5. Lance `Polarthographe.ahk` (double-clic).
6. (Optionnel) Ajoute un raccourci vers `Polarthographe.ahk` dans le dossier `shell:startup` pour qu'il démarre avec Windows.

## Utilisation

1. Sélectionne du texte dans n'importe quelle application.
2. Appuie sur **Ctrl+Alt+V** (rapide) ou **Ctrl+Alt+C** (avec choix).
3. Une bulle indique la progression puis le résultat ("3 correction(s) appliquée(s)").
4. Le texte sélectionné est remplacé par sa version corrigée. `Ctrl+Z` annule si besoin.

## Personnalisation

Tout se configure en tête du fichier [`Polarthographe.ahk`](Polarthographe.ahk) :

```ahk
LT_URL := "http://localhost:8081/v2/check"   ; adresse du serveur LanguageTool
LT_LANG := "fr"                              ; langue
LT_TIMEOUT_MS := 8000                        ; delai max d'attente de l'API

^!v::CorrigerSelection(false)   ; Ctrl+Alt+V = mode rapide
^!c::CorrigerSelection(true)    ; Ctrl+Alt+C = mode avec choix
```

Pour changer un raccourci, modifie le préfixe avant `c::` :
`^` = Ctrl, `!` = Alt, `+` = Shift, `#` = Win (voir la [doc AutoHotkey](https://www.autohotkey.com/docs/v2/Hotkeys.htm)).

Après modification, recharge le script (clic droit sur l'icône verte "H" dans la zone de notification → **Reload**).

## Dépannage

- **"Aucun texte sélectionné" alors que j'ai bien sélectionné**  
  Vérifie que le serveur LanguageTool tourne (`C:\LanguageTool\start-server.bat`). Regarde aussi `polarthographe.log` (créé à côté du script) pour voir la fenêtre ciblée par le raccourci.
- **Ça ne fonctionne pas dans le nouveau Bloc-notes de Windows 11**  
  Le Bloc-notes moderne (WinUI) ignore parfois les touches injectées par les scripts d'automatisation. Fonctionne normalement dans Discord, les navigateurs, et la plupart des applications classiques.
- **Erreur "serveur LanguageTool injoignable"**  
  Le serveur n'est pas démarré. Lance `C:\LanguageTool\start-server.bat`, ou vérifie que la tâche planifiée `LanguageToolServer` est active (Planificateur de tâches Windows).
- **Journal détaillé** : `polarthographe.log`, créé à côté de `Polarthographe.ahk`, log chaque déclenchement du raccourci et ses éventuelles erreurs.

## Désinstallation

```powershell
.\uninstall.ps1
```

Supprime la tâche planifiée, le raccourci de démarrage et `C:\LanguageTool`. Java et AutoHotkey ne sont pas désinstallés automatiquement (utilisés potentiellement par d'autres programmes) — utilise `winget uninstall EclipseAdoptium.Temurin.21.JRE` / `winget uninstall AutoHotkey.AutoHotkey` si tu veux les retirer aussi.

## Vie privée

Le texte sélectionné est envoyé uniquement à `localhost:8081`, un serveur qui tourne sur ta propre machine. Rien ne quitte ton PC.

## Licence

[MIT](LICENSE)
