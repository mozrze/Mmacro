; ============================================================
; Язык интерфейса настроек
; Хранит выбранный язык в ahk\settings.ini и не перегружает main.ahk.
; ============================================================

AppLanguage := "en"

LoadAppLanguage() {
    global AppLanguage, SettingsFile
    IniRead, value, %SettingsFile%, General, Language, en
    StringLower, value, value
    if (value != "ru" && value != "en")
        value := "en"
    AppLanguage := value
}

SetAppLanguage(value) {
    global AppLanguage, SettingsFile
    StringLower, value, value
    if (value != "ru" && value != "en")
        value := "en"
    AppLanguage := value
    IniWrite, %AppLanguage%, %SettingsFile%, General, Language
}

GetAppLanguage() {
    global AppLanguage
    return AppLanguage
}
