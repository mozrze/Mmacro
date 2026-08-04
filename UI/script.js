/* ============================================================
   TD Macro — Full Layout + Modals + AHK Bridge (ES5)
   ============================================================ */
(function () {
    'use strict';

    /* ---- Helpers ---- */
    function $(s) { return document.querySelector(s); }
    function $$(s) { return document.querySelectorAll(s); }
    function pad(n) { return (n < 10 ? '0' : '') + n; }
    function now() {
        var d = new Date();
        return pad(d.getHours()) + ':' + pad(d.getMinutes()) + ':' + pad(d.getSeconds());
    }
    function on(el, evt, fn) {
        if (el.addEventListener) el.addEventListener(evt, fn, false);
        else if (el.attachEvent) el.attachEvent('on' + evt, fn);
    }
    function esc(s) {
        var d = document.createElement('div');
        d.appendChild(document.createTextNode(s));
        return d.innerHTML;
    }

    /* ---- State ---- */
    var state = {
        embedded: false,
        farming: false,
        map: null,
        activeModal: null
    };

    /* ---- Detect: running in AHK or standalone browser? ---- */
    var inAHK = false;
    window.ahkSetMode = function () { inAHK = true; };

    /* ---- AHK Bridge ---- */
    function sendCmd(cmd) {
        window.ahkCmd = cmd;
    }

    /* ---- Log ---- */
    var logBox = $('#logBox');
    function log(text, cls) {
        if (!logBox) return;
        var entry = document.createElement('div');
        entry.className = 'log-entry' + (cls ? ' ' + cls : '');
        entry.innerHTML = '<span class="log-time">' + now() + '</span> ' + esc(text);
        logBox.appendChild(entry);
        logBox.scrollTop = logBox.scrollHeight;
    }

    /* ---- Modal System ---- */
    var overlay = $('#overlay');
    function openModal(id) {
        if (state.activeModal) closeModal(state.activeModal);
        var modal = document.getElementById('modal-' + id);
        if (!modal) return;
        overlay.className = 'overlay show';
        modal.className = 'modal show';
        state.activeModal = id;
    }
    function closeModal(id) {
        var modal = document.getElementById('modal-' + id);
        if (!modal) return;
        overlay.className = 'overlay';
        modal.className = 'modal';
        state.activeModal = null;
    }
    function closeAllModals() {
        if (state.activeModal) closeModal(state.activeModal);
    }

    /* ======== WIRING ======== */

    // Embed
    var embedBadge = $('#embedBadge');
    on($('#btnEmbed'), 'click', function () {
        state.embedded = !state.embedded;
        sendCmd('embed');
        if (state.embedded) {
            embedBadge.textContent = 'Connected';
            embedBadge.className = 'badge connected';
            this.querySelector('span').textContent = 'Unembed';
        } else {
            embedBadge.textContent = 'Disconnected';
            embedBadge.className = 'badge';
            this.querySelector('span').textContent = 'Embed';
        }
    });

    // Map
    var mapSelect = $('#mapSelect');
    var mapBadge  = $('#mapBadge');
    on(mapSelect, 'change', function () {
        var val = mapSelect.value;
        state.map = val || null;
        mapBadge.textContent = val ? mapSelect.options[mapSelect.selectedIndex].text : 'None';
        mapBadge.className = val ? 'badge active' : 'badge';
        sendCmd('select-map/' + (val || '__none__'));
    });
    on($('#btnSnapshot'), 'click', function () {
        if (!state.map) return log('Select a map first!', 'warn');
        sendCmd('snapshot');
    });
    on($('#btnMark'), 'click', function () {
        if (!state.map) return log('Select a map first!', 'warn');
        sendCmd('mark-slots');
    });
    on($('#btnClear'), 'click', function () {
        mapSelect.value = ''; state.map = null;
        mapBadge.textContent = 'None'; mapBadge.className = 'badge';
        sendCmd('clear-map');
    });

    // Farm
    var btnFarm   = $('#btnFarm');
    var statusDot = $('#statusDot');
    var statusText = $('#statusText');
    function setFarmUI(running) {
        if (running) {
            btnFarm.className = 'btn btn-start running';
            btnFarm.querySelector('span').textContent = 'Stop Farm';
            btnFarm.querySelector('svg').innerHTML = '<rect x="4" y="3.5" width="3.5" height="9" rx="1" fill="currentColor"/><rect x="8.5" y="3.5" width="3.5" height="9" rx="1" fill="currentColor"/>';
        } else {
            btnFarm.className = 'btn btn-start';
            btnFarm.querySelector('span').textContent = 'Start Farm';
            btnFarm.querySelector('svg').innerHTML = '<path d="M5 3.5 13 8l-8 4.5v-9Z"/>';
        }
    }
    on(btnFarm, 'click', function () {
        state.farming = !state.farming;
        sendCmd('start-farm');
        setFarmUI(state.farming);
    });
    on($('#chkAutoUpgrade'), 'change', function () { sendCmd('toggle-autoupgrade'); });
    on($('#btnUpgradeCfg'), 'click', function () {
        if (inAHK) sendCmd('upgrade-cfg');
        else openModal('upgrade');
    });

    // Bottom buttons — direct ID binding, no conditions
    var btnS = document.getElementById('btnSettings');
    var btnP = document.getElementById('btnPresets');
    var btnC = document.getElementById('btnCalibrate');
    if (btnS) on(btnS, 'click', function () { window.ahkCmd = 'settings'; });
    if (btnP) on(btnP, 'click', function () { window.ahkCmd = 'presets'; });
    if (btnC) on(btnC, 'click', function () { window.ahkCmd = 'calibrate'; });

    // Clear log
    on($('#btnClearLog'), 'click', function () { logBox.innerHTML = ''; sendCmd('clear-log'); });

    // Modal close: overlay + data-close buttons
    on(overlay, 'click', function () { closeAllModals(); });
    var closeBtns = $$('[data-close]');
    for (var i = 0; i < closeBtns.length; i++) {
        on(closeBtns[i], 'click', function () { closeAllModals(); });
    }

    // Escape key
    on(document, 'keydown', function (e) {
        e = e || window.event;
        if (e.keyCode === 27) closeAllModals();
        if (e.keyCode === 120) {  // F9
            if (e.preventDefault) e.preventDefault();
            btnFarm.click();
        }
    });

    /* ============================================================
       AHK → JS: global functions called via execScript
       ============================================================ */
    window.ahkLog = function (msg, cls) { log(msg, cls); };

    window.ahkUpdateStatus = function (text, cls) {
        statusText.textContent = text || 'Idle';
        statusDot.className = 'status-dot' + (cls ? ' ' + cls : '');
    };

    window.ahkUpdateEmbed = function (connected) {
        state.embedded = connected;
        if (connected) {
            embedBadge.textContent = 'Connected';
            embedBadge.className = 'badge connected';
            $('#btnEmbed').querySelector('span').textContent = 'Unembed';
        } else {
            embedBadge.textContent = 'Disconnected';
            embedBadge.className = 'badge';
            $('#btnEmbed').querySelector('span').textContent = 'Embed';
        }
    };

    window.ahkUpdateFarm = function (running) {
        state.farming = running;
        setFarmUI(running);
    };

    window.ahkUpdateCoords = function (up, st, rp, au) {
        var items = $$('.coord-val');
        var vals = [up, st, rp, au];
        var allSet = true;
        for (var i = 0; i < 4; i++) {
            if (vals[i]) {
                items[i].textContent = vals[i];
                items[i].className = 'coord-val set';
            } else {
                items[i].textContent = '\u2014';
                items[i].className = 'coord-val';
                allSet = false;
            }
        }
        var cb = $('#coordBadge');
        cb.textContent = allSet ? 'All set' : 'Not set';
        cb.className = allSet ? 'badge connected' : 'badge';
    };

    window.ahkUpdateMap = function (mapName) {
        if (mapName) {
            mapSelect.value = mapName;
            state.map = mapName;
            mapBadge.textContent = mapName;
            mapBadge.className = 'badge active';
        } else {
            mapSelect.value = '';
            state.map = null;
            mapBadge.textContent = 'None';
            mapBadge.className = 'badge';
        }
    };

    window.ahkSetMapOptions = function (optStr) {
        var names = optStr.split('|');
        mapSelect.innerHTML = '<option value="">-- Select Map --</option>';
        for (var i = 0; i < names.length; i++) {
            if (!names[i]) continue;
            var opt = document.createElement('option');
            opt.value = names[i];
            opt.textContent = names[i];
            mapSelect.appendChild(opt);
        }
    };

    window.ahkClearLog = function () { if (logBox) logBox.innerHTML = ''; };

    /* ---- Modal-only mode: AHK opens a separate window for one modal ---- */
    window.showModalOnly = function (name) {
        document.body.className = 'modal-only';

        // Hide layout elements directly (inline styles as safety)
        var layout = document.getElementsByClassName('layout')[0];
        if (layout) layout.style.display = 'none';
        var ovl = document.getElementById('overlay');
        if (ovl) ovl.style.display = 'none';

        // Hide ALL modals first
        var allModals = document.querySelectorAll('.modal');
        for (var i = 0; i < allModals.length; i++) {
            allModals[i].style.display = 'none';
        }

        // Show the target modal
        var m = document.getElementById('modal-' + name);
        if (!m) return;
        m.style.display = 'block';
        m.style.position = 'static';
        m.style.height = '100%';
        m.style.width = '100%';

        // Make panel fill the window
        var panel = m.getElementsByClassName('modal-panel')[0];
        if (panel) {
            panel.style.marginLeft = '0';
            panel.style.width = '100%';
            panel.style.maxWidth = '100%';
            panel.style.height = '100%';
            panel.style.maxHeight = '100%';
            panel.style.borderRadius = '0';
            panel.style.border = '2px solid #252525';
            panel.style.boxShadow = 'none';
        }

        // Wire ALL buttons inside modal
        var all = m.getElementsByTagName('BUTTON');
        for (var i = 0; i < all.length; i++) {
            var b = all[i];
            var c = b.className || '';
            if (c.indexOf('modal-cls') !== -1 || (b.getAttribute('data-close') !== null && !b.id)) {
                on(b, 'mousedown', function () { window.ahkCmd = 'close-modal'; });
            } else if (c.indexOf('modal-min') !== -1 || b.getAttribute('data-min') !== null) {
                on(b, 'mousedown', function () { window.ahkCmd = 'minimize-modal'; });
            }
        }

        // Drag via header
        var head = m.getElementsByClassName('modal-head')[0];
        if (head) {
            head.style.cursor = 'default';
            on(document, 'mousedown', function (e) {
                e = e || window.event;
                var el = e.target || e.srcElement;
                while (el && el !== head) {
                    if (el.tagName === 'BUTTON') return;
                    el = el.parentNode;
                }
                if (!el) return;
                window.ahkCmd = 'drag-start-modal/' + e.screenX + '/' + e.screenY;
            });
        }

        // Modal-specific init
        switch (name) {
            case 'settings': initSettingsModal(m); break;
            case 'presets':  initPresetsModal(m);  break;
            case 'calibrate': initCalibrateModal(m); break;
            case 'upgrade':  initUpgradeModal(m);  break;
        }
    };

    /* ---- Settings Modal Init ---- */
    function initSettingsModal(m) {
        var btnSave = document.getElementById('btnSettingsSave');
        if (btnSave) on(btnSave, 'click', function () {
            var vals = [
                $('#setClickDelay').value,
                $('#setSlotClickDelay').value,
                $('#setUpgradeClickDelay').value,
                $('#setAutoClickDelay').value,
                $('#setUnitSleepDelay').value,
                $('#setStartGameDelay').value,
                $('#setHoverDelay').value,
                $('#setMouseSpeed').value,
                $('#setImgVariation').value,
                $('#setStartGameColor').value,
                $('#setStartGameColorVar').value,
                $('#setStartGameCenterX').value,
                $('#setStartGameCenterY').value,
                $('#setStartGameRadius').value
            ];
            window.ahkCmd = 'settings-save/' + vals.join('/');
        });
        // Sync color picker <-> text
        var picker = document.getElementById('setStartGameColorPicker');
        var text = $('#setStartGameColor');
        if (picker && text) {
            on(picker, 'input', function () {
                text.value = picker.value.replace('#', '');
            });
            on(text, 'input', function () {
                if (/^[0-9A-Fa-f]{6}$/.test(text.value))
                    picker.value = '#' + text.value;
            });
        }
    }
    window.ahkLoadSettings = function(cd, scd, ucd, acd, usd, sgd, hd, ms, iv, sgc, sgcv, sgcx, sgcy, sgr) {
        var set = function(id, v) { var el = $(id); if (el) el.value = v; };
        set('#setClickDelay', cd); set('#setSlotClickDelay', scd);
        set('#setUpgradeClickDelay', ucd); set('#setAutoClickDelay', acd);
        set('#setUnitSleepDelay', usd); set('#setStartGameDelay', sgd);
        set('#setHoverDelay', hd); set('#setMouseSpeed', ms);
        set('#setImgVariation', iv);
        var colorHex = (sgc || '').replace('0x', '');
        set('#setStartGameColor', colorHex);
        var picker = document.getElementById('setStartGameColorPicker');
        if (picker && colorHex) picker.value = '#' + colorHex;
        set('#setStartGameColorVar', sgcv);
        set('#setStartGameCenterX', sgcx); set('#setStartGameCenterY', sgcy);
        set('#setStartGameRadius', sgr);
    };

    /* ---- Presets Modal Init ---- */
    function initPresetsModal(m) {
        var list = $('#presetList');
        if (list) on(list, 'click', function (e) {
            var tgt = e.target || e.srcElement;
            if (tgt.className && tgt.className.indexOf('preset-item') !== -1) {
                var nameInput = $('#presetName');
                if (nameInput) nameInput.value = tgt.textContent || tgt.innerText;
            }
        });
        var btnSave = $('#btnPresetSave');
        var btnLoad = $('#btnPresetLoad');
        var btnDel  = $('#btnPresetDelete');
        var nameInput = $('#presetName');
        if (btnSave) on(btnSave, 'click', function () {
            var n = nameInput ? nameInput.value.trim() : '';
            if (!n) { alert('Enter a preset name.'); return; }
            window.ahkCmd = 'preset-save/' + n;
        });
        if (btnLoad) on(btnLoad, 'click', function () {
            var n = nameInput ? nameInput.value.trim() : '';
            if (!n) { alert('Select or enter a preset name.'); return; }
            window.ahkCmd = 'preset-load/' + n;
        });
        if (btnDel) on(btnDel, 'click', function () {
            var n = nameInput ? nameInput.value.trim() : '';
            if (!n) { alert('Select or enter a preset name.'); return; }
            if (confirm('Delete preset "' + n + '"?'))
                window.ahkCmd = 'preset-delete/' + n;
        });
    }
    window.ahkLoadPresets = function(listStr) {
        var list = $('#presetList');
        if (!list) return;
        if (!listStr || listStr === '') {
            list.innerHTML = '';
            var div = document.createElement('div');
            div.className = 'preset-empty';
            div.textContent = 'No saved presets';
            list.appendChild(div);
            return;
        }
        list.innerHTML = '';
        var names = listStr.split('|');
        for (var i = 0; i < names.length; i++) {
            if (!names[i]) continue;
            var div = document.createElement('div');
            div.className = 'preset-item';
            div.textContent = names[i];
            div.style.cssText = 'padding: 6px 10px; cursor: pointer; font-size: 12px; color: #ccc; border-bottom: 1px solid #1a1a1a;';
            div.onmouseover = function () { this.style.background = '#1a1a1a'; };
            div.onmouseout  = function () { this.style.background = ''; };
            list.appendChild(div);
        }
    };

    /* ---- Calibration Modal Init ---- */
    function initCalibrateModal(m) {
        var cards = m.getElementsByClassName('calib-card');
        for (var i = 0; i < cards.length; i++) {
            on(cards[i], 'click', function () {
                var action = this.getAttribute('data-action');
                if (action) window.ahkCmd = action;
            });
        }
    }
    window.ahkUpdateCalibCoords = function(upX, upY, stX, stY, rpX, rpY, auX, auY) {
        var set = function(id, x, y) {
            var el = $(id);
            if (el) el.textContent = (x && y) ? x + ', ' + y : '\u2014';
        };
        set('#calibValUpgrade', upX, upY);
        set('#calibValStartGame', stX, stY);
        set('#calibValRepeatStage', rpX, rpY);
        set('#calibValAutoUpgrade', auX, auY);
    };

    /* ---- Auto Upgrade Modal Init ---- */
    function initUpgradeModal(m) {
        var btnSave = $('#btnUpgradeSave');
        if (btnSave) on(btnSave, 'click', function () {
            var prio = [
                $('#upgSlot1').value, $('#upgSlot2').value, $('#upgSlot3').value,
                $('#upgSlot4').value, $('#upgSlot5').value, $('#upgSlot6').value
            ];
            var offset = $('#upgYOffset').value;
            window.ahkCmd = 'upgrade-save/' + prio.join(',') + '/' + offset;
        });
    }
    window.ahkLoadUpgradeCfg = function(prioStr, offset) {
        var prio = prioStr.split(',');
        for (var i = 0; i < 6; i++) {
            var el = $('#upgSlot' + (i + 1));
            if (el) el.value = prio[i] || '3';
        }
        var offEl = $('#upgYOffset');
        if (offEl) offEl.value = offset || '20';
    };

    /* ---- Init ---- */
    log('TD Macro v1.0 ready.');

    /* ---- Auto-show modal if URL has hash ---- */
    (function () {
        var hash = window.location.hash;
        if (hash && hash.length > 1 && window.showModalOnly) {
            window.showModalOnly(hash.substring(1));
        }
    })();

    /* ---- Main window: drag via sidebar header + minimize/close ---- */
    (function () {
        var bar = document.getElementById('mainDragBar');
        if (!bar) return;
        bar.style.cursor = 'default';

        on(document, 'mousedown', function (e) {
            var tgt = e.target || e.srcElement;
            var el = tgt;
            // Check if click is inside the drag bar
            while (el) {
                if (el === bar) break;
                // Don't start drag on buttons
                if (el.tagName === 'BUTTON') return;
                el = el.parentNode;
            }
            if (!el) return; // not in drag bar
            window.ahkCmd = 'drag-start-main/' + e.screenX + '/' + e.screenY;
        });

        on(document.getElementById('btnMainMin'), 'click', function () {
            window.ahkCmd = 'minimize-main';
        });
        on(document.getElementById('btnMainClose'), 'click', function () {
            window.ahkCmd = 'close-main';
        });
    })();
})();
