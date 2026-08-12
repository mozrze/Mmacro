; ============================================================
; Проверка версии приложения
; Подключается из main.ahk после завершения auto-execute секции.
; ============================================================

; ---- Проверка обновлений через GitHub API ----
CheckForUpdate:
    global GH_API_URL, GH_TOKEN, GH_TOKEN_FILE, CURRENT_VERSION, WB
    AddLog("Update: проверяю обновления...")

    ; Проверяем наличие токена
    if (GH_TOKEN = "") {
        AddLog("Update: токен не найден в " . GH_TOKEN_FILE . " — запрос без аутентификации", "warn")
    }

    ; Формируем HTTP-запрос
    try {
        whr := ComObjCreate("WinHttp.WinHttpRequest.5.1")
        whr.Option(9) := 2688  ; TLS 1.2
        whr.Open("GET", GH_API_URL, False)
        whr.SetRequestHeader("User-Agent", "TD-Macro-Updater")
        whr.SetRequestHeader("Accept", "application/vnd.github+json")
        if (GH_TOKEN != "")
            whr.SetRequestHeader("Authorization", "Bearer " . GH_TOKEN)
        whr.Send()
        status := whr.Status
        body := whr.ResponseText

        if (status = 401) {
            AddLog("Update: ошибка 401 — пробую без API (публичный режим)...", "warn")
            GoSub, CheckUpdateNoAuth
            return
        }
        if (status = 404) {
            AddLog("Update: релизы не найдены — создай Release на GitHub (тег v1.0.1+)", "error")
            WBH_CallJS("ahkUpdateVersion('NO REL', false)")
            return
        }
        if (status = 403) {
            AddLog("Update: ошибка 403 — пробую без API (публичный режим)...", "warn")
            GoSub, CheckUpdateNoAuth
            return
        }
        if (status != 200) {
            AddLog("Update: GitHub API вернул статус " status, "error")
            WBH_CallJS("ahkUpdateVersion('ERR " status "', false)")
            return
        }
    } catch e {
        AddLog("Update: ошибка HTTP-запроса — " e.Message, "error")
        WBH_CallJS("ahkUpdateVersion('ERR', false)")
        return
    }

    ; Парсим JSON — ищем "tag_name"
    tagPos := InStr(body, """tag_name""")
    if (!tagPos) {
        AddLog("Update: не удалось найти tag_name в ответе", "error")
        WBH_CallJS("ahkUpdateVersion('v?', false)")
        return
    }
    tagStart := tagPos + 12  ; длина "tag_name":" = 11 + кавычка = 12
    tagRest := SubStr(body, tagStart)
    StringSplit, tparts, tagRest, "
    latestTag := tparts1

    AddLog("Update: текущая = " CURRENT_VERSION ", последняя = " latestTag)

    ; Сравниваем версии (простое строковое сравнение; предполагаем формат vX.Y.Z)
    if (latestTag = CURRENT_VERSION || latestTag = "v" . CURRENT_VERSION) {
        AddLog("Update: у вас последняя версия!")
        WBH_CallJS("ahkUpdateVersion('" CURRENT_VERSION "', false)")
    } else {
        AddLog("Update: доступна новая версия: " latestTag "!", "warn")
        WBH_CallJS("ahkUpdateVersion('" latestTag "', true)")
        ; Сохраняем URL для скачивания: сначала пробуем прикреплённый ассет,
        ; если релиз без ассетов (только тег) — берём автосгенерированный zip GitHub'а
        dlPos := InStr(body, """browser_download_url""")
        if (dlPos) {
            dlStart := dlPos + 25
            dlRest := SubStr(body, dlStart)
            StringSplit, dparts, dlRest, "
            downloadURL := dparts1
        } else {
            downloadURL := "https://github.com/" . GH_REPO . "/archive/refs/tags/" . latestTag . ".zip"
        }
        global PendingUpdateURL, PendingUpdateOldVer, PendingUpdateNewVer
        PendingUpdateURL := downloadURL
        PendingUpdateOldVer := CURRENT_VERSION
        PendingUpdateNewVer := latestTag
        OpenModalWindow("update-confirm", "Update available", 340, 300)
    }
return

; ---- Проверка обновлений БЕЗ GitHub API (через редирект releases/latest) ----
; Работает для публичных репозиториев, токен не нужен.
CheckUpdateNoAuth:
    global GH_REPO, CURRENT_VERSION, WB
    releasesURL := "https://github.com/" . GH_REPO . "/releases/latest"
    AddLog("Update (no-auth): проверяю " releasesURL "...")

    try {
        whr := ComObjCreate("WinHttp.WinHttpRequest.5.1")
        whr.Option(6) := False   ; не следовать редиректу
        whr.Option(9) := 2688
        whr.Open("GET", releasesURL, False)
        whr.SetRequestHeader("User-Agent", "TD-Macro-Updater")
        whr.Send()
        status := whr.Status
        if (status != 302 && status != 301) {
            AddLog("Update (no-auth): статус " status " — репо приватный или нет релизов", "error")
            WBH_CallJS("ahkUpdateVersion('ERR', false)")
            return
        }
        location := whr.GetResponseHeader("Location")
        if (location = "") {
            AddLog("Update (no-auth): нет Location-заголовка", "error")
            WBH_CallJS("ahkUpdateVersion('ERR', false)")
            return
        }
        ; Извлекаем тег из URL: .../releases/tag/v1.0.2
        ; Если нет тега — значит нет релизов
        tagPos := InStr(location, "/tag/")
        if (!tagPos) {
            AddLog("Update (no-auth): релизы не найдены (нет /tag/ в " location ")", "warn")
            AddLog("Update: создайте Release на GitHub: git tag v" CURRENT_VERSION " && git push origin v" CURRENT_VERSION)
            WBH_CallJS("ahkUpdateVersion('NO REL', false)")
            return
        }
        latestTag := SubStr(location, tagPos + 5)
        ; Берём только до первого / или конца строки (убираем trailing path)
        slashPos := InStr(latestTag, "/")
        if (slashPos)
            latestTag := SubStr(latestTag, 1, slashPos - 1)

        AddLog("Update (no-auth): текущая = " CURRENT_VERSION ", последняя = " latestTag)

        if (latestTag = CURRENT_VERSION || latestTag = "v" . CURRENT_VERSION) {
            AddLog("Update: у вас последняя версия!")
            WBH_CallJS("ahkUpdateVersion('" CURRENT_VERSION "', false)")
        } else {
            AddLog("Update: доступна новая версия: " latestTag "!", "warn")
            WBH_CallJS("ahkUpdateVersion('" latestTag "', true)")
            zipURL := "https://github.com/" . GH_REPO . "/archive/refs/tags/" . latestTag . ".zip"
            global PendingUpdateURL, PendingUpdateOldVer, PendingUpdateNewVer
            PendingUpdateURL := zipURL
            PendingUpdateOldVer := CURRENT_VERSION
            PendingUpdateNewVer := latestTag
            OpenModalWindow("update-confirm", "Update available", 340, 300)
        }
    } catch e {
        AddLog("Update (no-auth): ошибка сети — " e.Message, "error")
        WBH_CallJS("ahkUpdateVersion('ERR', false)")
    }
return
