"""Discord control bot for Mmacro.

The bot deliberately talks to AutoHotkey through small files in runtime/.
That keeps Discord/network code out of the game-control process and makes the
integration easy to diagnose when the bot is stopped.
"""

from __future__ import annotations

import asyncio
import configparser
import ctypes
import os
import sys
import time
import traceback
import urllib.parse
import uuid
from pathlib import Path
from ctypes import wintypes

BOOT_LOG_FILE = Path(__file__).resolve().parent / "runtime" / "bot.log"


def bootstrap_log(message: str) -> None:
    try:
        BOOT_LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
        with BOOT_LOG_FILE.open("a", encoding="utf-8") as log:
            log.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {message}\n")
    except OSError:
        pass


try:
    import discord
    from discord import app_commands
    from discord.ext import commands
except Exception as exc:
    bootstrap_log(f"bot import failed: {type(exc).__name__}: {exc}")
    raise

try:
    from PIL import Image, ImageGrab, ImageStat
except ImportError:
    Image = None
    ImageGrab = None
    ImageStat = None

try:
    import mss
except ImportError:
    mss = None


BOT_DIR = Path(__file__).resolve().parent
PROJECT_DIR = BOT_DIR.parent
SETTINGS_FILE = PROJECT_DIR / "macro" / "ahk" / "settings.ini"
MAPS_DIR = PROJECT_DIR / "macro" / "maps"
RUNTIME_DIR = BOT_DIR / "runtime"
COMMANDS_DIR = RUNTIME_DIR / "commands"
RESPONSES_DIR = RUNTIME_DIR / "responses"
SCREENSHOT_FILE = RUNTIME_DIR / "discord_screenshot.bmp"
SCREENSHOT_PNG = RUNTIME_DIR / "discord_screenshot.png"
BOT_LOG_FILE = RUNTIME_DIR / "bot.log"
STATE_FILE = RUNTIME_DIR / "state.ini"

USER32 = ctypes.windll.user32 if os.name == "nt" else None
KERNEL32 = ctypes.windll.kernel32 if os.name == "nt" else None


class RECT(ctypes.Structure):
    _fields_ = [("left", wintypes.LONG), ("top", wintypes.LONG),
                ("right", wintypes.LONG), ("bottom", wintypes.LONG)]


class POINT(ctypes.Structure):
    _fields_ = [("x", wintypes.LONG), ("y", wintypes.LONG)]


def ensure_runtime() -> None:
    COMMANDS_DIR.mkdir(parents=True, exist_ok=True)
    RESPONSES_DIR.mkdir(parents=True, exist_ok=True)


def bot_log(message: str) -> None:
    try:
        with BOT_LOG_FILE.open("a", encoding="utf-8") as log:
            log.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {message}\n")
    except OSError:
        pass


def read_settings() -> configparser.ConfigParser:
    parser = configparser.ConfigParser()
    parser.optionxform = str
    parser.read(SETTINGS_FILE, encoding="utf-8-sig")
    return parser


def setting(section: str, key: str, fallback: str = "") -> str:
    parser = read_settings()
    return parser.get(section, key, fallback=fallback).strip()


def parse_state() -> dict[str, str]:
    result: dict[str, str] = {}
    if not STATE_FILE.exists():
        return result
    try:
        for raw_line in STATE_FILE.read_text(encoding="utf-8-sig").splitlines():
            if "=" not in raw_line:
                continue
            key, value = raw_line.split("=", 1)
            result[key.strip().lstrip("\ufeff")] = urllib.parse.unquote(value.strip())
    except OSError:
        pass
    return result


def available_maps() -> list[str]:
    """Return real map snapshots, without stale state entries or duplicates."""

    if not MAPS_DIR.exists():
        return []
    names: list[str] = []
    seen: set[str] = set()
    for path in sorted(MAPS_DIR.glob("*.bmp"), key=lambda item: item.stem.casefold()):
        name = path.stem.strip()
        key = name.casefold()
        if not name or key in seen:
            continue
        seen.add(key)
        names.append(name)
    return names


def command(action: str, argument: str = "", timeout: float = 8.0) -> dict[str, str]:
    """Send one command to AHK and wait for its response."""

    ensure_runtime()
    request_id = uuid.uuid4().hex
    request = COMMANDS_DIR / f"{request_id}.cmd"
    response = RESPONSES_DIR / f"{request_id}.result"
    payload = "\n".join(
        [
            f"id={request_id}",
            f"action={action}",
            f"arg={urllib.parse.quote(argument, safe='')}",
            "",
        ]
    )
    temporary = COMMANDS_DIR / f".{request_id}.tmp"
    temporary.write_text(payload, encoding="utf-8")
    os.replace(temporary, request)

    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if response.exists():
            result: dict[str, str] = {}
            raw_response = response.read_text(encoding="utf-8-sig")
            # AHK writes responses atomically, but keep this guard for older
            # macro processes that may still write them directly.
            if "ok=" not in raw_response:
                time.sleep(0.03)
                continue
            for raw_line in raw_response.splitlines():
                if "=" not in raw_line:
                    continue
                key, value = raw_line.split("=", 1)
                result[key.strip().lstrip("\ufeff")] = urllib.parse.unquote(value.strip())
            response.unlink(missing_ok=True)
            return result
        time.sleep(0.1)

    return {"ok": "0", "message": "Макрос не ответил. Проверьте, что AHK запущен."}


def state_message(state: dict[str, str]) -> str:
    running = "запущен" if state.get("running") == "1" else "остановлен"
    selected = state.get("selected_map") or "не выбрана"
    pending = state.get("pending_map") or "нет"
    runs = state.get("runs", "0")
    recording = state.get("map_record_map") if state.get("map_recording") == "1" else "нет"
    return f"Фарм: **{running}**\nКарта: **{selected}**\nОжидает смены: **{pending}**\nРанов: **{runs}**\nЗапись входа: **{recording}**"


def is_mostly_black(path: Path) -> bool:
    if Image is None or ImageStat is None or not path.exists():
        return True
    try:
        with Image.open(path) as image:
            sample = image.convert("L")
            # AHK считает кадр чёрным уже при среднем канале около 10.
            # Берём небольшой запас, чтобы не отправлять почти пустой BMP.
            return ImageStat.Stat(sample).mean[0] < 18
    except OSError:
        return True


def find_roblox_window() -> tuple[int, str] | tuple[None, None]:
    """Find the visible Roblox window and its client-area region."""

    if USER32 is None:
        return None, None
    try:
        USER32.SetProcessDPIAware()
    except AttributeError:
        pass

    candidates: list[tuple[int, int, str]] = []
    enum_proc = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)

    @enum_proc
    def visit(hwnd: int, _: int) -> bool:
        if not USER32.IsWindowVisible(hwnd):
            return True
        title_buffer = ctypes.create_unicode_buffer(512)
        USER32.GetWindowTextW(hwnd, title_buffer, len(title_buffer))
        title = title_buffer.value.casefold()

        pid = wintypes.DWORD()
        USER32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        process_name = ""
        if KERNEL32 is not None:
            process = KERNEL32.OpenProcess(0x1000 | 0x0400, False, pid.value)
            if process:
                path_buffer = ctypes.create_unicode_buffer(1024)
                path_size = wintypes.DWORD(len(path_buffer))
                if KERNEL32.QueryFullProcessImageNameW(process, 0, path_buffer, ctypes.byref(path_size)):
                    process_name = os.path.basename(path_buffer.value).casefold()
                KERNEL32.CloseHandle(process)

        if process_name != "robloxplayerbeta.exe" and "roblox" not in title:
            return True
        rect = RECT()
        point = POINT()
        if not USER32.GetClientRect(hwnd, ctypes.byref(rect)):
            return True
        if not USER32.ClientToScreen(hwnd, ctypes.byref(point)):
            return True
        width = rect.right - rect.left
        height = rect.bottom - rect.top
        if width >= 100 and height >= 100:
            candidates.append((width * height, hwnd, f"{point.x},{point.y},{width},{height}"))
        return True

    USER32.IsWindowVisible.argtypes = [wintypes.HWND]
    USER32.IsWindowVisible.restype = wintypes.BOOL
    USER32.GetWindowTextW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
    USER32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
    USER32.GetClientRect.argtypes = [wintypes.HWND, ctypes.POINTER(RECT)]
    USER32.ClientToScreen.argtypes = [wintypes.HWND, ctypes.POINTER(POINT)]
    USER32.EnumWindows.argtypes = [enum_proc, wintypes.LPARAM]
    USER32.EnumWindows.restype = wintypes.BOOL
    USER32.EnumChildWindows.argtypes = [wintypes.HWND, enum_proc, wintypes.LPARAM]
    USER32.EnumChildWindows.restype = wintypes.BOOL
    if KERNEL32 is not None:
        KERNEL32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
        KERNEL32.OpenProcess.restype = wintypes.HANDLE
        KERNEL32.QueryFullProcessImageNameW.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.LPWSTR, ctypes.POINTER(wintypes.DWORD)]
        KERNEL32.QueryFullProcessImageNameW.restype = wintypes.BOOL
        KERNEL32.CloseHandle.argtypes = [wintypes.HANDLE]
        KERNEL32.CloseHandle.restype = wintypes.BOOL
    # В режиме dock макроса Roblox становится дочерним окном AHK и больше
    # не попадает в обычный EnumWindows. Сначала собираем верхний уровень,
    # затем просматриваем его дочерние окна.
    top_level: list[int] = []

    @enum_proc
    def collect_top(hwnd: int, _: int) -> bool:
        top_level.append(hwnd)
        return True

    USER32.EnumWindows(collect_top, 0)
    for top_hwnd in top_level:
        visit(top_hwnd, 0)
        USER32.EnumChildWindows(top_hwnd, visit, 0)
    if not candidates:
        return None, None
    _, hwnd, region = max(candidates, key=lambda item: item[0])
    return hwnd, region


def activate_roblox_window(hwnd: int | None) -> None:
    if USER32 is None or not hwnd:
        return
    try:
        USER32.GetForegroundWindow.restype = wintypes.HWND
        USER32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
        USER32.AttachThreadInput.argtypes = [wintypes.DWORD, wintypes.DWORD, wintypes.BOOL]
        USER32.SetForegroundWindow.argtypes = [wintypes.HWND]
        USER32.SetActiveWindow.argtypes = [wintypes.HWND]
        USER32.BringWindowToTop.argtypes = [wintypes.HWND]
        USER32.ShowWindow.argtypes = [wintypes.HWND, ctypes.c_int]
        USER32.GetParent.argtypes = [wintypes.HWND]
        USER32.GetParent.restype = wintypes.HWND
        USER32.SetWindowPos.argtypes = [wintypes.HWND, wintypes.HWND, ctypes.c_int, ctypes.c_int,
                                        ctypes.c_int, ctypes.c_int, wintypes.UINT]
        USER32.SetWindowPos.restype = wintypes.BOOL
        USER32.SwitchToThisWindow.argtypes = [wintypes.HWND, wintypes.BOOL]
    except AttributeError:
        pass

    foreground = USER32.GetForegroundWindow()
    foreground_pid = wintypes.DWORD()
    foreground_thread = USER32.GetWindowThreadProcessId(foreground, ctypes.byref(foreground_pid)) if foreground else 0
    current_thread = KERNEL32.GetCurrentThreadId() if KERNEL32 is not None else 0
    attached = bool(foreground_thread and current_thread and foreground_thread != current_thread)
    if attached:
        USER32.AttachThreadInput(current_thread, foreground_thread, True)
    parent = USER32.GetParent(hwnd)
    target = parent or hwnd
    # Если Roblox встроен в AHK, поднимаем родительское окно и сам дочерний
    # HWND. Это помогает, когда Discord забрал foreground и обычный
    # SetForegroundWindow не меняет фактический Z-порядок.
    swp_flags = 0x0001 | 0x0002 | 0x0040  # SWP_NOSIZE | SWP_NOMOVE | SWP_SHOWWINDOW
    USER32.SetWindowPos(target, 0, 0, 0, 0, 0, swp_flags)
    if parent:
        USER32.SetWindowPos(hwnd, 0, 0, 0, 0, 0, swp_flags)
    USER32.ShowWindow(hwnd, 9)  # SW_RESTORE
    USER32.BringWindowToTop(hwnd)
    USER32.SetActiveWindow(hwnd)
    USER32.SetForegroundWindow(hwnd)
    try:
        USER32.SwitchToThisWindow(hwnd, True)
    except AttributeError:
        pass
    if attached:
        USER32.AttachThreadInput(current_thread, foreground_thread, False)
    time.sleep(0.6)
    try:
        active = USER32.GetForegroundWindow()
        bot_log(f"Roblox activation: requested={hwnd} parent={parent} foreground={active}")
    except AttributeError:
        pass


def recapture_screen(region: str) -> bool:
    """Capture the visible screen region when Roblox's GDI frame is black."""

    if Image is None:
        return False
    try:
        x, y, width, height = (int(value) for value in region.split(","))
    except (AttributeError, TypeError, ValueError):
        return False
    if width <= 0 or height <= 0:
        return False

    try:
        if mss is not None:
            with mss.mss() as screen:
                shot = screen.grab({"left": x, "top": y, "width": width, "height": height})
                Image.frombytes("RGB", shot.size, shot.rgb).save(SCREENSHOT_FILE, format="BMP")
        elif ImageGrab is not None:
            image = ImageGrab.grab(bbox=(x, y, x + width, y + height), all_screens=True)
            image.convert("RGB").save(SCREENSHOT_FILE, format="BMP")
        else:
            return False
    except (AttributeError, OSError, RuntimeError, ValueError):
        return False
    return SCREENSHOT_FILE.exists() and not is_mostly_black(SCREENSHOT_FILE)


def recapture_desktop() -> bool:
    """Capture the current desktop as a last-resort diagnostic screenshot."""

    if Image is None:
        return False
    try:
        if mss is not None:
            with mss.mss() as screen:
                monitor = screen.monitors[0]
                shot = screen.grab(monitor)
                Image.frombytes("RGB", shot.size, shot.rgb).save(SCREENSHOT_FILE, format="BMP")
        elif ImageGrab is not None:
            image = ImageGrab.grab(all_screens=True)
            image.convert("RGB").save(SCREENSHOT_FILE, format="BMP")
        else:
            return False
    except (AttributeError, OSError, RuntimeError, ValueError):
        return False
    return SCREENSHOT_FILE.exists()


def screenshot_path(raw_path: str = "", region: str = "") -> tuple[Path | None, str]:
    """Return a Discord-friendly PNG and a diagnostic message on failure."""

    source = Path(raw_path) if raw_path else SCREENSHOT_FILE
    notice = ""
    captured_roblox = False
    for attempt in range(3):
        hwnd, roblox_region = find_roblox_window()
        bot_log(f"Roblox window search attempt={attempt + 1}: hwnd={hwnd} region={roblox_region}")
        if hwnd and roblox_region:
            activate_roblox_window(hwnd)
            bot_log(f"trying visible Roblox capture: {roblox_region}")
            if recapture_screen(roblox_region):
                source = SCREENSHOT_FILE
                captured_roblox = True
                break
        if attempt < 2:
            time.sleep(0.5)

    if not captured_roblox:
        bot_log("Roblox capture failed; trying full desktop diagnostic capture")
        if recapture_desktop():
            source = SCREENSHOT_FILE
            notice = "Roblox не удалось захватить; отправляю текущий экран рабочего стола."
        else:
            return None, "Не удалось получить изображение Roblox и текущего рабочего стола."
    if Image is None:
        return None, "Для отправки снимка нужен Pillow. Установите зависимости из bot/requirements.txt."
    try:
        SCREENSHOT_PNG.unlink(missing_ok=True)
        with Image.open(source) as image:
            image.convert("RGB").save(SCREENSHOT_PNG, format="PNG")
        if not SCREENSHOT_PNG.exists():
            return None, "PNG-файл снимка не был создан."
        bot_log(f"screenshot prepared: {SCREENSHOT_PNG} ({SCREENSHOT_PNG.stat().st_size} bytes)")
        return SCREENSHOT_PNG, notice
    except (OSError, ValueError) as exc:
        return None, f"Не удалось подготовить PNG-снимок: {exc}"


class MacroBot(commands.Bot):
    def __init__(self, guild_id: int | None):
        # Нужны только обычные (не privileged) intents. Guilds помогает Discord
        # корректно обработать slash-команды на разных компьютерах.
        super().__init__(command_prefix="!", intents=discord.Intents.default())
        self.guild_id = guild_id

    async def setup_hook(self) -> None:
        # Не ждём Discord API до подключения к Gateway: медленная сеть или
        # неверный GuildId не должны оставлять бота в состоянии offline.
        if self.guild_id:
            guild = discord.Object(id=self.guild_id)
            self.tree.copy_global_to(guild=guild)
        self._sync_task = asyncio.create_task(self._sync_commands())

    async def _sync_commands(self) -> None:
        """Synchronize commands without preventing the Gateway connection."""

        try:
            if self.guild_id:
                await asyncio.wait_for(
                    self.tree.sync(guild=discord.Object(id=self.guild_id)),
                    timeout=20,
                )
                bot_log(f"slash commands synced to guild {self.guild_id}")
            else:
                await asyncio.wait_for(self.tree.sync(), timeout=20)
                bot_log("global slash commands synced")
        except (discord.HTTPException, asyncio.TimeoutError) as exc:
            bot_log(f"slash command sync failed: {type(exc).__name__}: {exc}")
            if self.guild_id:
                try:
                    await asyncio.wait_for(self.tree.sync(), timeout=20)
                    bot_log("global slash command sync completed")
                except (discord.HTTPException, asyncio.TimeoutError) as global_exc:
                    bot_log(f"global command sync failed: {type(global_exc).__name__}: {global_exc}")
        except Exception as exc:
            bot_log(f"unexpected command sync failure: {type(exc).__name__}: {exc}")

    async def on_ready(self) -> None:
        message = f"Mmacro bot connected as {self.user} (id={self.user.id if self.user else 'unknown'})"
        print(message, flush=True)
        bot_log(message)


def allowed_users() -> set[int]:
    raw = setting("DiscordBot", "AllowedUserIds", "")
    result: set[int] = set()
    for value in raw.replace(";", ",").split(","):
        value = value.strip()
        if value.isdigit():
            result.add(int(value))
    return result


def authorized(interaction: discord.Interaction) -> bool:
    users = allowed_users()
    return not users or interaction.user.id in users


async def require_authorized(interaction: discord.Interaction) -> bool:
    if authorized(interaction):
        return True
    message = "У вас нет доступа к управлению этим макросом."
    if interaction.response.is_done():
        await interaction.followup.send(message, ephemeral=True)
    else:
        await interaction.response.send_message(message, ephemeral=True)
    return False


async def map_autocomplete(_: discord.Interaction, current: str) -> list[app_commands.Choice[str]]:
    maps = available_maps()
    current = current.casefold()
    return [
        app_commands.Choice(name=name[:100], value=name[:100])
        for name in maps
        if not current or current in name.casefold()
    ][:25]


def register_commands(bot: MacroBot) -> None:
    @bot.tree.command(name="screenshot", description="Сделать снимок игровой области")
    async def screenshot(interaction: discord.Interaction) -> None:
        if not await require_authorized(interaction):
            return
        await interaction.response.defer()
        result = await asyncio.to_thread(command, "screenshot")
        bot_log(f"screenshot command result: ok={result.get('ok')} path={result.get('path', '')} region={result.get('region', '')}")
        if result.get("ok") != "1":
            await interaction.followup.send(result.get("message", "Не удалось сделать снимок."))
            return
        path, error = screenshot_path(result.get("path", ""), result.get("region", ""))
        if not path:
            await interaction.followup.send(error or "Снимок не найден.")
            return
        try:
            with path.open("rb") as stream:
                upload = discord.File(stream, filename="td_macro_screenshot.png")
                await interaction.followup.send(
                    content=error or result.get("message", "Текущий экран:"),
                    files=[upload],
                )
            bot_log("screenshot uploaded to Discord")
        except (discord.HTTPException, OSError) as exc:
            bot_log(f"screenshot upload failed: {type(exc).__name__}: {exc}")
            await interaction.followup.send(
                "Снимок создан, но Discord не принял вложение. "
                "Проверьте право **Attach Files** у бота в этом канале. "
                f"Ошибка: `{type(exc).__name__}: {exc}`"
            )

    @bot.tree.command(name="runs", description="Показать состояние и количество ранов")
    async def runs(interaction: discord.Interaction) -> None:
        if not await require_authorized(interaction):
            return
        await interaction.response.send_message(state_message(parse_state()))

    @bot.tree.command(name="maps", description="Показать доступные карты")
    async def maps(interaction: discord.Interaction) -> None:
        if not await require_authorized(interaction):
            return
        values = available_maps()
        await interaction.response.send_message(
            "Доступные карты:\n" + ("\n".join(f"• {value}" for value in values) if values else "нет карт")
        )

    @bot.tree.command(name="map", description="Поставить карту в очередь на следующий раунд")
    @app_commands.describe(map_name="Имя карты из списка макроса")
    @app_commands.autocomplete(map_name=map_autocomplete)
    async def map_command(interaction: discord.Interaction, map_name: str) -> None:
        if not await require_authorized(interaction):
            return
        await interaction.response.defer(ephemeral=True)
        result = await asyncio.to_thread(command, "switch-map", map_name)
        await interaction.followup.send(result.get("message", "Команда отправлена."), ephemeral=True)

def main() -> int:
    ensure_runtime()
    bot_log(f"bot process starting; python={sys.executable}; settings={SETTINGS_FILE}")
    token = setting("DiscordBot", "Token", "")
    if not token:
        print("DiscordBot.Token is empty", file=sys.stderr, flush=True)
        bot_log("DiscordBot.Token is empty")
        return 2
    guild_raw = setting("DiscordBot", "GuildId", "")
    guild_id = int(guild_raw) if guild_raw.isdigit() else None
    bot_log(f"token loaded; guild_id={guild_id if guild_id else 'global'}")
    bot = MacroBot(guild_id)
    register_commands(bot)
    try:
        bot.run(token, log_handler=None)
    except discord.LoginFailure:
        print("Discord bot token is invalid", file=sys.stderr, flush=True)
        bot_log("Discord login failed: token is invalid or revoked")
        return 3
    except Exception as exc:
        print(f"Discord bot stopped: {exc}", file=sys.stderr, flush=True)
        bot_log(f"Discord bot stopped: {type(exc).__name__}: {exc}")
        bot_log(traceback.format_exc())
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
