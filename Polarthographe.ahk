#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================
;  Polarthographe - correcteur automatique de francais (local, via LanguageTool)
;
;  Ctrl+Alt+V -> mode rapide : corrige tout automatiquement
;                (prend toujours la 1ere suggestion, pas d'interruption)
;  Ctrl+Alt+C -> mode avec choix : quand une faute a plusieurs
;                suggestions possibles, un petit menu te laisse choisir
;
;  (Ctrl+Shift+C n'est pas utilise : c'est le raccourci natif "Inspecter
;  l'element" dans la quasi-totalite des navigateurs, qui l'intercepte
;  avant ce script.)
;
;  Pour changer un raccourci : modifie "^!c::" ou "^!v::" ci-dessous.
;  Syntaxe AutoHotkey : ^ = Ctrl, ! = Alt, + = Shift, # = Win.
; ============================================================

LT_URL := "http://localhost:8081/v2/check"
LT_LANG := "fr"
LT_TIMEOUT_MS := 8000
LOG_FILE := A_ScriptDir . "\polarthographe.log"

OnError(LogFatalError)
LogFatalError(err, mode) {
    LogLine("ERREUR FATALE: " . err.Message . " | What=" . err.What . " | Line=" . err.Line)
    ToolTip("Erreur interne, voir polarthographe.log")
    SetTimer(() => ToolTip(), -3000)
    return true
}

LogLine(msg) {
    global LOG_FILE
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") . "  " . msg . "`n", LOG_FILE, "UTF-8")
}

LogLine("=== Polarthographe demarre (PID " . ProcessExist() . "). Ctrl+Alt+V = rapide, Ctrl+Alt+C = avec choix ===")
TrayTip("Polarthographe actif", "Ctrl+Alt+V : rapide`nCtrl+Alt+C : avec choix des suggestions", 1)

^!v::CorrigerSelection(false)
^!c::CorrigerSelection(true)

; ==================== Fonction principale ====================
; interactive = true  -> propose un menu de choix pour les fautes ambigues
; interactive = false -> prend toujours la 1ere suggestion automatiquement
CorrigerSelection(interactive) {
    global LT_URL, LT_LANG, LT_TIMEOUT_MS

    activeWin := "?"
    try activeWin := WinGetTitle("A") . " [" . WinGetProcessName("A") . "]"
    LogLine("Hotkey declenche. Fenetre active: " . activeWin)

    targetHwnd := 0
    try targetHwnd := WinGetID("A")

    clipBackup := ClipboardAll()
    A_Clipboard := ""

    ToolTip("Correction en cours...")

    ; Le raccourci Ctrl+Alt+C peut laisser Ctrl/Alt "enfonces" au moment ou
    ; on envoie Ctrl+C juste apres : l'appli recevrait alors Ctrl+Alt+C au
    ; lieu de Ctrl+C (souvent ignore comme commande de copie). On force le
    ; relachement des deux touches avant d'envoyer le vrai Ctrl+C.
    Send("{LCtrl up}{RCtrl up}{LAlt up}{RAlt up}")
    Sleep(100)
    ; SendEvent (au lieu de SendInput, le mode par defaut) : le Bloc-notes
    ; moderne de Windows 11 (WinUI) ignore parfois les raccourcis clavier
    ; injectes via SendInput. SendEvent est plus compatible avec ce type
    ; d'application.
    SendEvent("^c")
    if !ClipWait(1.5) {
        LogLine("ClipWait timeout : aucune donnee copiee (rien de selectionne, ou Ctrl+C n'a pas atteint la fenetre active).")
        ToolTip("Aucun texte selectionne.")
        SetTimer(() => ToolTip(), -2000)
        A_Clipboard := clipBackup
        return
    }

    originalText := A_Clipboard
    if (originalText = "") {
        ToolTip("Aucun texte selectionne.")
        SetTimer(() => ToolTip(), -2000)
        A_Clipboard := clipBackup
        return
    }

    LogLine("Texte copie (" . StrLen(originalText) . " caracteres). Appel de l'API...")

    try {
        responseText := LT_Check(originalText, LT_URL, LT_LANG, LT_TIMEOUT_MS)
    } catch as err {
        LogLine("Echec appel API: " . err.Message)
        ToolTip("Erreur : serveur LanguageTool injoignable sur localhost:8081.`nLancez C:\LanguageTool\start-server.bat`n(" . err.Message . ")")
        SetTimer(() => ToolTip(), -5000)
        A_Clipboard := clipBackup
        return
    }

    try {
        data := JSON_Parse(responseText)
    } catch as err {
        ToolTip("Erreur : reponse LanguageTool illisible.")
        SetTimer(() => ToolTip(), -3000)
        A_Clipboard := clipBackup
        return
    }

    matches := (data.Has("matches")) ? data["matches"] : []
    LogLine("Reponse recue. " . matches.Length . " faute(s) detectee(s).")

    if (matches.Length = 0) {
        ToolTip("Aucune faute trouvee.")
        SetTimer(() => ToolTip(), -2000)
        A_Clipboard := clipBackup
        return
    }

    ; Mode "avec choix" uniquement : les fautes ayant 2+ suggestions
    ; (typiquement des fautes d'orthographe pure, ou le classement des
    ; suggestions par LanguageTool n'est pas fiable) ouvrent un petit menu.
    ; En mode rapide, on prend toujours directement la 1ere suggestion.
    userChoices := Map()
    if (interactive) {
        ambiguousIdx := []
        for i, m in matches {
            reps := (m.Has("replacements")) ? m["replacements"] : []
            if (reps.Length > 1)
                ambiguousIdx.Push(i)
        }
        if (ambiguousIdx.Length > 0) {
            ToolTip()
            userChoices := ShowSuggestionPicker(matches, ambiguousIdx, originalText)
        }
    }

    ; Appliquer les corrections de la fin du texte vers le debut
    ; (les offsets restent valides tant qu'on ne touche pas au texte
    ; situe avant la position courante).
    correctedText := originalText
    appliedCount := 0
    count := matches.Length
    loop count {
        idx := count - A_Index + 1
        m := matches[idx]
        offset := m["offset"]
        len := m["length"]
        reps := (m.Has("replacements")) ? m["replacements"] : []
        if (reps.Length = 0)
            continue
        replacement := userChoices.Has(idx) ? userChoices[idx] : reps[1]["value"]
        if (replacement = "")
            continue
        correctedText := SubStr(correctedText, 1, offset) . replacement . SubStr(correctedText, offset + len + 1)
        appliedCount++
    }

    if (appliedCount = 0) {
        ToolTip(matches.Length . " faute(s) detectee(s), mais aucune correction retenue.")
        SetTimer(() => ToolTip(), -3000)
        A_Clipboard := clipBackup
        return
    }

    A_Clipboard := correctedText
    if !ClipWait(1) {
        ToolTip("Erreur : impossible de preparer le presse-papiers.")
        SetTimer(() => ToolTip(), -3000)
        A_Clipboard := clipBackup
        return
    }

    ; Le selecteur de suggestions (s'il s'est affiche) a pu deplacer le focus :
    ; on reactive explicitement la fenetre d'origine avant de coller.
    if (targetHwnd) {
        try {
            WinActivate("ahk_id " . targetHwnd)
            WinWaitActive("ahk_id " . targetHwnd, , 1)
        }
    }

    SendEvent("^v")
    Sleep(300)

    A_Clipboard := clipBackup

    LogLine(appliedCount . " correction(s) collee(s) avec succes.")
    ToolTip(appliedCount . " correction(s) appliquee(s). (Ctrl+Z pour annuler)")
    SetTimer(() => ToolTip(), -2500)
}

; ==================== Selecteur de suggestions (fautes ambigues) ====================
; matches: tableau complet des fautes ; ambiguousIdx: indices (dans matches)
; ayant 2+ suggestions. Affiche un menu contextuel (comme un clic-droit de
; correcteur orthographique classique) pour chaque faute, l'une apres l'autre.
; Retourne une Map indice -> texte de remplacement choisi ("" = ignorer).
ShowSuggestionPicker(matches, ambiguousIdx, originalText) {
    choices := Map()
    for idx in ambiguousIdx {
        m := matches[idx]
        offset := m["offset"]
        len := m["length"]
        originalWord := SubStr(originalText, offset + 1, len)
        reps := m["replacements"]
        choices[idx] := PickOneSuggestion(originalWord, reps)
    }
    return choices
}

PickOneSuggestion(originalWord, reps) {
    selected := ""
    suggestionMenu := Menu()
    header := originalWord . "  →"
    suggestionMenu.Add(header, (*) => "")
    suggestionMenu.Disable(header)
    suggestionMenu.Add()
    for r in reps {
        val := r["value"]
        suggestionMenu.Add(val, PickCallback)
    }
    suggestionMenu.Add()
    suggestionMenu.Add("Ignorer", (*) => selected := "")
    suggestionMenu.Show()
    return selected

    PickCallback(itemName, *) {
        selected := itemName
    }
}

; ==================== Appel API LanguageTool ====================
LT_Check(text, url, lang, timeoutMs) {
    body := "text=" . UrlEncodeUTF8(text) . "&language=" . lang

    whr := ComObject("WinHttp.WinHttpRequest.5.1")
    whr.Open("POST", url, false)
    whr.SetRequestHeader("Content-Type", "application/x-www-form-urlencoded")
    whr.SetTimeouts(timeoutMs, timeoutMs, timeoutMs, timeoutMs)
    whr.Send(body)

    if (whr.Status != 200)
        throw Error("HTTP " . whr.Status)

    ; WinHttpRequest.ResponseText ne detecte pas toujours correctement l'UTF-8
    ; (les caracteres accentues seraient mal decodes). On force le decodage
    ; UTF-8 explicitement via un flux ADODB binaire -> texte.
    ado := ComObject("ADODB.Stream")
    ado.Type := 1 ; adTypeBinary
    ado.Open()
    ado.Write(whr.ResponseBody)
    ado.Position := 0
    ado.Type := 2 ; adTypeText
    ado.Charset := "utf-8"
    text := ado.ReadText()
    ado.Close()
    return text
}

; ==================== Encodage URL en UTF-8 (pour les accents) ====================
UrlEncodeUTF8(str) {
    static Unreserved := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~"
    if (str = "")
        return ""
    byteLen := StrPut(str, "UTF-8") - 1
    buf := Buffer(byteLen)
    StrPut(str, buf, "UTF-8")
    result := ""
    loop byteLen {
        b := NumGet(buf, A_Index - 1, "UChar")
        c := Chr(b)
        if InStr(Unreserved, c)
            result .= c
        else
            result .= "%" . Format("{:02X}", b)
    }
    return result
}

; ==================== Parseur JSON minimal ====================
; (AutoHotkey v2 n'a pas de parseur JSON natif ; celui-ci gere
;  objets, tableaux, chaines avec echappements \uXXXX, nombres,
;  true/false/null.)

JSON_Parse(str) {
    pos := 1
    return JSON_ParseValue(str, &pos)
}

JSON_SkipWs(str, &pos) {
    len := StrLen(str)
    while (pos <= len) {
        c := SubStr(str, pos, 1)
        if (c = " " || c = "`t" || c = "`n" || c = "`r")
            pos++
        else
            break
    }
}

JSON_ParseValue(str, &pos) {
    JSON_SkipWs(str, &pos)
    c := SubStr(str, pos, 1)
    if (c = "{")
        return JSON_ParseObject(str, &pos)
    else if (c = "[")
        return JSON_ParseArray(str, &pos)
    else if (c = "`"")
        return JSON_ParseString(str, &pos)
    else if (SubStr(str, pos, 4) = "true") {
        pos += 4
        return true
    } else if (SubStr(str, pos, 5) = "false") {
        pos += 5
        return false
    } else if (SubStr(str, pos, 4) = "null") {
        pos += 4
        return ""
    } else {
        return JSON_ParseNumber(str, &pos)
    }
}

JSON_ParseObject(str, &pos) {
    obj := Map()
    pos++
    JSON_SkipWs(str, &pos)
    if (SubStr(str, pos, 1) = "}") {
        pos++
        return obj
    }
    loop {
        JSON_SkipWs(str, &pos)
        key := JSON_ParseString(str, &pos)
        JSON_SkipWs(str, &pos)
        pos++ ; ":"
        value := JSON_ParseValue(str, &pos)
        obj[key] := value
        JSON_SkipWs(str, &pos)
        c := SubStr(str, pos, 1)
        pos++
        if (c = "}")
            break
    }
    return obj
}

JSON_ParseArray(str, &pos) {
    arr := []
    pos++
    JSON_SkipWs(str, &pos)
    if (SubStr(str, pos, 1) = "]") {
        pos++
        return arr
    }
    loop {
        value := JSON_ParseValue(str, &pos)
        arr.Push(value)
        JSON_SkipWs(str, &pos)
        c := SubStr(str, pos, 1)
        pos++
        if (c = "]")
            break
    }
    return arr
}

JSON_ParseString(str, &pos) {
    pos++
    result := ""
    loop {
        c := SubStr(str, pos, 1)
        if (c = "`"") {
            pos++
            break
        }
        if (c = "\") {
            pos++
            esc := SubStr(str, pos, 1)
            switch esc {
                case "`"":
                    result .= "`""
                case "\":
                    result .= "\"
                case "/":
                    result .= "/"
                case "b":
                    result .= Chr(8)
                case "f":
                    result .= Chr(12)
                case "n":
                    result .= "`n"
                case "r":
                    result .= "`r"
                case "t":
                    result .= "`t"
                case "u":
                    hex := SubStr(str, pos + 1, 4)
                    result .= Chr("0x" . hex)
                    pos += 4
                default:
                    result .= esc
            }
            pos++
        } else {
            result .= c
            pos++
        }
    }
    return result
}

JSON_ParseNumber(str, &pos) {
    start := pos
    len := StrLen(str)
    while (pos <= len) {
        c := SubStr(str, pos, 1)
        if InStr("0123456789+-.eE", c)
            pos++
        else
            break
    }
    return SubStr(str, start, pos - start) + 0
}
