/* ============================================================
   TD Macro — UI controller (ES5 / IE11 совместимый)
   ============================================================ */
(function () {
    "use strict";

    /* ---------- Состояние ---------- */
    var state = {
        maps: [],
        selectedMap: null,
        running: false,
        autoUpgrade: false
    };

    /* ---------- Shortcut helpers ---------- */
    function $(sel) { return document.querySelector(sel); }
    function $$(sel) { return document.querySelectorAll(sel); }

    /* ============================================================
       ЛОГ
       ============================================================ */
    var logBox = $("#logBox");

    function addLog(msg, type) {
        var time = new Date().toLocaleTimeString("ru-RU", { hour12: false });
        var line = document.createElement("div");
        line.className = "log__line" + (type ? " log__line--" + type : "");
        line.innerHTML =
            '<span class="log__time">' + escHtml(time) + "</span>" +
            escHtml(msg);
        logBox.appendChild(line);
        logBox.scrollTop = logBox.scrollHeight;
    }

    function escHtml(s) {
        return String(s)
            .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;").replace(/'/g, "&#39;");
    }

    /* ============================================================
       DROPDOWN выбора карты
       ============================================================ */
    var mapSelect   = $("#mapSelect");
    var mapTrigger  = $("#mapSelectTrigger");
    var mapValue    = $("#mapSelectValue");
    var mapList     = $("#mapSelectList");

    function openSelect() {
        mapSelect.dataset.open = "true";
        mapList.hidden = false;
    }
    function closeSelect() {
        mapSelect.dataset.open = "false";
        mapList.hidden = true;
    }

    mapTrigger.addEventListener("click", function (e) {
        e.stopPropagation();
        if (mapSelect.dataset.open === "true") closeSelect();
        else openSelect();
    });

    document.addEventListener("click", function (e) {
        if (!mapSelect.contains(e.target)) closeSelect();
    });
    document.addEventListener("keydown", function (e) {
        // IE11 отдаёт "Esc", а не "Escape" (у e.key нестандартные значения) —
        // без проверки обоих вариантов Esc не закрывал меню в этом браузере.
        if (e.key === "Escape" || e.key === "Esc" || e.keyCode === 27) closeSelect();
    });

    function renderMapList() {
        mapList.innerHTML = "";
        if (state.maps.length === 0) {
            var li = document.createElement("li");
            li.className = "select__empty";
            li.textContent = "Нет сохранённых снимков";
            mapList.appendChild(li);
            mapValue.textContent = "Карта не выбрана";
            mapValue.classList.add("is-placeholder");
            return;
        }
        mapValue.classList.remove("is-placeholder");
        state.maps.forEach(function (name) {
            var li = document.createElement("li");
            li.textContent = name;
            li.dataset.value = name;
            if (name === state.selectedMap) li.classList.add("is-selected");
            li.addEventListener("click", function () {
                selectMap(name);
                closeSelect();
            });
            mapList.appendChild(li);
        });
    }

    function selectMap(name) {
        state.selectedMap = name;
        mapValue.textContent = name;
        mapValue.classList.remove("is-placeholder");
        var items = $$(".select__list li");
        for (var i = 0; i < items.length; i++) {
            // classList.toggle(token, force) — второй аргумент (force) НЕ
            // поддерживается в IE11: он просто переключает класс туда-обратно
            // при каждом вызове, игнорируя условие. Из-за этого при добавлении
            // карт по одной (addMap -> selectMap) класс "is-selected" рано или
            // поздно навешивался на ВСЕ пункты одновременно. Явный add/remove
            // работает в IE11 корректно.
            if (items[i].dataset.value === name) {
                items[i].classList.add("is-selected");
            } else {
                items[i].classList.remove("is-selected");
            }
        }
        onMapChanged(name);
    }

    function setMaps(list, autoSelect) {
        state.maps = Array.isArray(list) ? list.slice() : [];
        renderMapList();
        if (autoSelect && state.maps.length > 0) {
            selectMap(autoSelect === true ? state.maps[0] : autoSelect);
        } else if (state.selectedMap && state.maps.indexOf(state.selectedMap) === -1) {
            state.selectedMap = null;
            mapValue.textContent = "Карта не выбрана";
            mapValue.classList.add("is-placeholder");
        }
    }

    function onMapChanged(name) {
        addLog('Карта "' + name + '": выбрана', "info");
    }

    /* ============================================================
       КНОПКИ (с заглушками для bridge к AHK)
       ============================================================ */
    function bindBtn(id, handler) {
        var el = document.getElementById(id);
        if (el) el.addEventListener("click", handler);
    }

    bindBtn("btnEmbed", function () {
        setWindowStatus("Встраивание...", "wait");
        addLog("Запрос встраивания Roblox");
        bridge("embed");
    });

    bindBtn("btnCapture", function () {
        addLog("Запрос снимка карты");
        bridge("captureMap");
    });

    bindBtn("btnMark", function () {
        if (!state.selectedMap) { addLog("Сначала выбери карту", "error"); return; }
        addLog("Открытие разметки для: " + state.selectedMap);
        bridge("markSlots", { map: state.selectedMap });
    });

    bindBtn("btnClear", function () {
        if (!state.selectedMap) { addLog("Сначала выбери карту", "error"); return; }
        if (!confirm('Очистить разметку карты "' + state.selectedMap + '"?')) return;
        addLog("Очистка разметки: " + state.selectedMap);
        bridge("clearMap", { map: state.selectedMap });
    });

    bindBtn("btnStartStop", function () { toggleRun(); });

    function toggleRun() {
        state.running = !state.running;
        var btn = $("#btnStartStop");
        var label = $("#startStopLabel");
        var icon = btn.querySelector(".btn__icon use");
        btn.dataset.running = state.running ? "true" : "false";
        if (state.running) {
            icon.setAttribute("href", "assets/icons.svg#icon-stop");
            label.textContent = "Стоп (F9)";
            addLog("Фарм запущен", "ok");
            $("#farmStatus").textContent = "Статус: выполняется";
            bridge("start");
        } else {
            icon.setAttribute("href", "assets/icons.svg#icon-play");
            label.textContent = "Старт (F9)";
            addLog("Фарм остановлен");
            $("#farmStatus").textContent = "Статус: остановлен";
            bridge("stop");
        }
    }

    bindBtn("btnAutoUpgradeSettings", function () {
        addLog("Открытие настроек автопрокачки");
        bridge("openAutoUpgradeSettings");
    });

    bindBtn("btnSettings", function () { addLog("Открытие настроек"); bridge("openSettings"); });
    bindBtn("btnPresets",  function () { addLog("Открытие пресетов");  bridge("openPresets"); });
    bindBtn("btnCalibration", function () { addLog("Открытие калибровки"); bridge("openCalibration"); });

    /* ---------- Toggle автопрокачки ---------- */
    $("#autoUpgradeEnabled").addEventListener("change", function (e) {
        state.autoUpgrade = e.target.checked;
        addLog("Автопрокачка: " + (state.autoUpgrade ? "вкл" : "выкл"), state.autoUpgrade ? "ok" : null);
        bridge("autoUpgradeToggle", { enabled: state.autoUpgrade });
    });

    /* ---------- Горячая клавиша F9 ---------- */
    document.addEventListener("keydown", function (e) {
        if (e.key === "F9") {
            e.preventDefault();
            toggleRun();
        }
    });

    /* ============================================================
       Bridge к AHK: меняем location.href, AHK перехватывает в BeforeNavigate2
       ============================================================ */
    function bridge(action, payload) {
        try {
            window.location.href = 'ahk://' + action + '/' + encodeURIComponent(JSON.stringify(payload || {}));
        } catch (e) {}
    }

    // Точка входа для AHK: window.uiBridge("...", {...})
    window.uiBridge = function (action, data) {
        data = data || {};
        switch (action) {
            case "setMaps":
                setMaps(data.maps || [], data.select);
                break;
            case "addMap":
                if (state.maps.indexOf(data.name) === -1) {
                    state.maps.push(data.name);
                    renderMapList();
                    selectMap(data.name);
                    addLog('Карта "' + data.name + '" добавлена', "ok");
                }
                break;
            case "selectMap":
                selectMap(data.name);
                break;
            case "log":
                addLog(data.msg, data.type);
                break;
            case "setRunning":
                if (!!data.running !== state.running) toggleRun();
                break;
            case "setWindowStatus":
                setWindowStatus(data.text, data.state);
                break;
            case "setOffsetStatus":
                $("#offsetStatus").textContent = data.text || "";
                break;
            case "setUi":
                if (data.key === "farmStatus") $("#farmStatus").textContent = data.value;
                else if (data.key === "windowStatus") setWindowStatus(data.value, data.state);
                else if (data.key === "offsetStatus") $("#offsetStatus").textContent = data.value;
                break;
            default:
                addLog("uiBridge: неизвестное действие " + action, "error");
        }
    };

    function setWindowStatus(text, st) {
        $("#windowStatus").textContent = "Статус: " + text;
        $("#winStatusDot").dataset.state = st || "unknown";
    }

    /* ============================================================
       Демо-данные (превью в браузере)
       ============================================================ */
    setMaps([
        "FlowerForest_Start",
        "FairyKingForest_Start",
        "King'sTomb_Start",
        "RoseKingdom_Start",
        "SchoolGrounds_Start",
        "Test"
    ], true);
    addLog("TD Macro UI загружен (превью-режим)", "info");

})();