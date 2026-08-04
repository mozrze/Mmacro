## План исправлений

### Диагностика

Все 4 HTML-модалки (Settings, Presets, Calibration, Auto Upgrade) — визуальные заглушки. Кнопки Save/Apply/Delete просто закрывают окно (`data-close`), никакой связи с AHK нет. Реальная логика живёт в нативных AHK-окнах (`OpenSettingsGui`, `OpenPresetsGui`, `OpenCalibrationGui`, `OpenAutoUpgradeSettingsGui`), которые недоступны из HTML-сайдбара.

### Что нужно сделать

**1. Настроить AHK↔JS мост для всех 4 модальных окон**

Добавить в `PollModalClose` (AHK) обработку новых команд из JS, и добавить JS-функции для приёма данных из AHK через `execScript`. Паттерн уже существует — `showModalOnly` подключает close/minimize/drag, я расширю его.

**2. Settings — загружать/сохранять значения**
- AHK после загрузки страницы пушит текущие 15 параметров через `ahkLoadSettings(...)` 
- При Save JS собирает все поля и шлёт `settings-save/val1/val2/...`
- AHK парсит, применяет к глобальным переменным, пишет `settings.ini`
- Размер окна: 480×530 (достаточно для 3 fieldset-ов без скролла)
- Кастомный скроллбар уже есть в CSS (`body.modal-only .modal-body::-webkit-scrollbar`)

**3. Presets — загружать список, сохранять/загружать/удалять**
- AHK пушит список пресетов через `ahkLoadPresets("Preset1|Preset2|...")`
- JS отображает список, клик по элементу копирует имя в поле ввода
- Save/Load/Delete шлют `preset-save/name`, `preset-load/name`, `preset-delete/name`
- AHK вызывает существующие `BtnPresetSave`/`BtnPresetLoad`/`BtnPresetDelete`
- Размер окна: 440×370

**4. Calibration — запускать калибровку по клику**
- JS-клик по карточке шлёт `calibrate-upgrade` / `calibrate-startgame` / `calibrate-repeatstage` / `calibrate-autoupgrade`
- AHK закрывает модалку и вызывает `Gosub, BtnCalibrateUpgrade` (и т.д.)
- Добавить `ahkUpdateCalibCoords(up, st, rp, au)` для обновления координат на карточках
- Размер окна: 440×420

**5. Auto Upgrade — загружать/сохранять приоритеты**
- AHK пушит `ahkLoadUpgradeCfg("3,3,3,3,3,3", "20")` (приоритеты 6 слотов + Y-offset)
- JS заполняет поля, Save шлёт `upgrade-save/3,3,3,3,3,3/20`
- AHK парсит и сохраняет
- Размер окна: 360×320

### Файлы которые меняются
- `AEmacro/main.ahk` — `ProcessJSCmd` (размеры + presets), `PollModalClose` (новые команды), `OpenModalWindow` (пуш данных после загрузки)
- `UI/index.html` — JS: `showModalOnly` (расширить), новые bridge-функции; HTML: id на поля ввода, data-action на кнопки
- `UI/style.css` — кастомный скроллбар (уже есть, возможно докрутить)
- `UI/script.js` — синхронизировать с `index.html`