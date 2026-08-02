; ═══════════════════════════════════════════════════════════
;  settings_ui.ahk  —  Интерфейс настроек макроса
;  Отдельный AHK-файл для изменения задержек и параметров поиска.
;  Сохраняет значения в ahk\settings.ini (корень проекта).
; ═══════════════════════════════════════════════════════════

#SingleInstance Force
#NoEnv
#Utf8
SetWorkingDir, %A_ScriptDir%\..   ; <- корень проекта (родитель ahk)

; ---- пути ----
SettingsIni := A_ScriptDir "\..\ahk\settings.ini"

; ---- значения по умолчанию (будут перезаписаны из settings.ini) ----
ClickDelay          := 80
SlotClickDelay      := 250
UpgradeClickDelay   := 150
AutoClickDelay      := 120
UnitSleepDelay      := 200
StartGameDelay      := 500
ImgVariation        := 30
StartGameColor      := "0x4ECD0C"
StartGameColorVar   := 30
StartGameCenterX    := 640
StartGameCenterY    := 500
StartGameRadius     := 200

; =================================================================
   LoadSettings()
   BuildGui()
return

; =================================================================
   BtnExit:
   GuiClose:
      ExitApp

; =================================================================
   BuildGui() {
      global
      Gui, +HwndMainGuiHwnd +AlwaysOnTop
      Gui, Color, 0x1E1E1E, 0x252526
      Gui, Font, s10 cE0E0E0, Segoe UI

      Gui, Add, Text, x14 y14 w420 h24 c00CCFF Bold, Настройки макроса TD

      ; ---- секция задержек ----
      Gui, Add, GroupBox, x14 y44 w460 h150, Задержки (мс)
      y := 62
      AddLabeledEdit("КД после номера юнита:",        y, "SetClickDelay")
      y := 90
      AddLabeledEdit("КД после клика по слоту:",       y, "SetSlotClickDelay")
      y := 118
      AddLabeledEdit("КД после клика Upgrade:",        y, "SetUpgradeClickDelay")
      y := 146
      AddLabeledEdit("КД между кликами AutoUpgrade:",  y, "SetAutoClickDelay")

      ; ---- доп. задержки ----
      Gui, Add, GroupBox, x14 y200 w460 h100, Дополнительно
      y := 218
      AddLabeledEdit("КД между юнитами:",              y, "SetUnitSleepDelay")
      y := 246
      AddLabeledEdit("КД после Start Game:",          y, "SetStartGameDelay")

      ; ---- поиск изображений ----
      Gui, Add, GroupBox, x14 y306 w460 h120, Поиск (ImageSearch)
      y := 324
      AddLabeledEdit("Допуск по цвету (0-255):",       y, "SetImgVariation")

      ; ---- поиск пикселя ----
      Gui, Add, GroupBox, x14 y432 w460 h200, Поиск Start Game по пикселю
      y := 450
      AddLabeledEdit("Цвет Start Game (0xRRGGBB):",    y, "SetStartGameColor")
      y := 478
      AddLabeledEdit("Допуск цвета (0-255):",          y, "SetStartGameColorVar")
      y := 506
      AddLabeledEdit("Центр X (0-1280):",              y, "SetStartGameCenterX")
      y := 534
      AddLabeledEdit("Центр Y (0-720):",               y, "SetStartGameCenterY")
      y := 562
      AddLabeledEdit("Радиус поиска (пиксели):",       y, "SetStartGameRadius")

   ; ---- кнопки ----
   Gui, Add, Button, x264 y580 w100 h28 gBtnSave, Сохранить
   Gui, Add, Button, x374 y580 w100 h28 gBtnReset, Сбросить
   Gui, Add, Button, x154 y580 w100 h28 gBtnExit, Закрыть
   Gui, Add, Button, x264 y610 w100 h28 gBtnLoadPreset, Загрузить пресет
   Gui, Add, Button, x374 y610 w100 h28 gBtnSavePreset, Сохранить пресет

   ; ---- статус лог ----
   Gui, Add, Text, x14 y644 w460 h20 vStatusLog, Готово

   Gui, Show, w490 h670, Настройки макроса
   }

   AddLabeledEdit(labelText, yPos, varName) {
      ; читаем из нужной секции в зависимости от имени переменной
      if (varName = "SetImgVariation") {
         IniRead, current, %SettingsIni%, ImageSearch, Variation
      } else if (SubStr(varName, 1, 3) = "Set") {
         ; SetStartGame...  ->  PixelSearch
         key := SubStr(varName, 4)   ; убираем "Set"
         IniRead, current, %SettingsIni%, PixelSearch, %key%
      } else {
         IniRead, current, %SettingsIni%, Delays, %varName%
      }

      Gui, Add, Text, x34 y%yPos% w260, %labelText%
      Gui, Add, Edit, x300 y%yPos% w80 v%varName%, %current%
   }

; =================================================================
   ;  ── загрузка настроек из settings.ini ──
   LoadSettings() {
      global SettingsIni, ClickDelay, SlotClickDelay, UpgradeClickDelay
      global AutoClickDelay, UnitSleepDelay, StartGameDelay, ImgVariation
      global StartGameColor, StartGameColorVar, StartGameCenterX, StartGameCenterY, StartGameRadius
      if (!FileExist(SettingsIni))
         return
      IniRead, v, %SettingsIni%, Delays, ClickDelay,        %ClickDelay%
      ClickDelay := v
      IniRead, v, %SettingsIni%, Delays, SlotClickDelay,   %SlotClickDelay%
      SlotClickDelay := v
      IniRead, v, %SettingsIni%, Delays, UpgradeClickDelay, %UpgradeClickDelay%
      UpgradeClickDelay := v
      IniRead, v, %SettingsIni%, Delays, AutoClickDelay,    %AutoClickDelay%
      AutoClickDelay := v
      IniRead, v, %SettingsIni%, Delays, UnitSleepDelay,   %UnitSleepDelay%
      UnitSleepDelay := v
      IniRead, v, %SettingsIni%, Delays, StartGameDelay,   %StartGameDelay%
      StartGameDelay := v
      IniRead, v, %SettingsIni%, ImageSearch, Variation,   %ImgVariation%
      ImgVariation := v
      IniRead, v, %SettingsIni%, PixelSearch, StartGameColor,     %StartGameColor%
      StartGameColor := v
      IniRead, v, %SettingsIni%, PixelSearch, StartGameColorVar,  %StartGameColorVar%
      StartGameColorVar := v
      IniRead, v, %SettingsIni%, PixelSearch, StartGameCenterX,   %StartGameCenterX%
      StartGameCenterX := v
      IniRead, v, %SettingsIni%, PixelSearch, StartGameCenterY,   %StartGameCenterY%
      StartGameCenterY := v
      IniRead, v, %SettingsIni%, PixelSearch, StartGameRadius,    %StartGameRadius%
      StartGameRadius := v

      ; ---- обновляем поля ввода в GUI ----
      GuiControl,, SetClickDelay,        %ClickDelay%
      GuiControl,, SetSlotClickDelay,    %SlotClickDelay%
      GuiControl,, SetUpgradeClickDelay, %UpgradeClickDelay%
      GuiControl,, SetAutoClickDelay,    %AutoClickDelay%
      GuiControl,, SetUnitSleepDelay,    %UnitSleepDelay%
      GuiControl,, SetStartGameDelay,    %StartGameDelay%
      GuiControl,, SetImgVariation,      %ImgVariation%
      GuiControl,, SetStartGameColor,    %StartGameColor%
      GuiControl,, SetStartGameColorVar, %StartGameColorVar%
      GuiControl,, SetStartGameCenterX,  %StartGameCenterX%
      GuiControl,, SetStartGameCenterY,  %StartGameCenterY%
      GuiControl,, SetStartGameRadius,   %StartGameRadius%
   }

; =================================================================
   BtnSave:
      Gui, Submit, NoHide
      ; ---- пишем все значения обратно ----
      IniWrite, %SetClickDelay%,        %SettingsIni%, Delays, ClickDelay
      IniWrite, %SetSlotClickDelay%,    %SettingsIni%, Delays, SlotClickDelay
      IniWrite, %SetUpgradeClickDelay%, %SettingsIni%, Delays, UpgradeClickDelay
      IniWrite, %SetAutoClickDelay%,    %SettingsIni%, Delays, AutoClickDelay
      IniWrite, %SetUnitSleepDelay%,    %SettingsIni%, Delays, UnitSleepDelay
      IniWrite, %SetStartGameDelay%,    %SettingsIni%, Delays, StartGameDelay
      IniWrite, %SetImgVariation%,      %SettingsIni%, ImageSearch, Variation
      IniWrite, %SetStartGameColor%,    %SettingsIni%, PixelSearch, StartGameColor
      IniWrite, %SetStartGameColorVar%, %SettingsIni%, PixelSearch, StartGameColorVar
      IniWrite, %SetStartGameCenterX%,  %SettingsIni%, PixelSearch, StartGameCenterX
      IniWrite, %SetStartGameCenterY%,  %SettingsIni%, PixelSearch, StartGameCenterY
      IniWrite, %SetStartGameRadius%,   %SettingsIni%, PixelSearch, StartGameRadius

      ; обновим глобальные переменные
      ClickDelay          := SetClickDelay
      SlotClickDelay      := SetSlotClickDelay
      UpgradeClickDelay   := SetUpgradeClickDelay
      AutoClickDelay      := SetAutoClickDelay
      UnitSleepDelay      := SetUnitSleepDelay
      StartGameDelay      := SetStartGameDelay
      ImgVariation        := SetImgVariation
      StartGameColor      := SetStartGameColor
      StartGameColorVar   := SetStartGameColorVar
      StartGameCenterX    := SetStartGameCenterX
      StartGameCenterY    := SetStartGameCenterY
      StartGameRadius     := SetStartGameRadius

      AddLogLocal("Настройки сохранены в ahk\settings.ini")
return

; =================================================================
   BtnReset:
      ClickDelay          := 80
      SlotClickDelay      := 250
      UpgradeClickDelay   := 150
      AutoClickDelay      := 120
      UnitSleepDelay      := 200
      StartGameDelay      := 500
      ImgVariation        := 30
      StartGameColor      := "0x4ECD0C"
      StartGameColorVar   := 30
      StartGameCenterX    := 640
      StartGameCenterY    := 500
      StartGameRadius     := 200

      ; ---- сбрасываем поля в GUI ----
      GuiControl,, SetClickDelay,        %ClickDelay%
      GuiControl,, SetSlotClickDelay,    %SlotClickDelay%
      GuiControl,, SetUpgradeClickDelay, %UpgradeClickDelay%
      GuiControl,, SetAutoClickDelay,    %AutoClickDelay%
      GuiControl,, SetUnitSleepDelay,    %UnitSleepDelay%
      GuiControl,, SetStartGameDelay,    %StartGameDelay%
      GuiControl,, SetImgVariation,      %ImgVariation%
      GuiControl,, SetStartGameColor,    %StartGameColor%
      GuiControl,, SetStartGameColorVar, %StartGameColorVar%
      GuiControl,, SetStartGameCenterX,  %StartGameCenterX%
      GuiControl,, SetStartGameCenterY,  %StartGameCenterY%
      GuiControl,, SetStartGameRadius,   %StartGameRadius%

      AddLogLocal("Значения сброшены к значениям по умолчанию")
return

; =================================================================
   AddLogLocal(msg) {
      FormatTime, ts,, HH:mm:ss
      Gui, 1:Default
      GuiControl,, StatusLog, % "[" ts "] " msg
   }
