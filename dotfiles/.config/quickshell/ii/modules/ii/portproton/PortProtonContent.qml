import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root
    focus: true

    implicitWidth: Appearance.sizes.wallpaperSelectorWidth - Appearance.sizes.hyprlandGapsOut * 2
    implicitHeight: Appearance.sizes.wallpaperSelectorHeight - Appearance.sizes.hyprlandGapsOut * 2

    readonly property string homePath: FileUtils.trimFileProtocol(Directories.home)
    readonly property string libraryPath: FileUtils.trimFileProtocol(`${Directories.shellConfig}/portproton-library.json`)
    readonly property string portProtonConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/PortProton.conf`)
    readonly property string userConfPath: root.portProtonRoot.length > 0
        ? FileUtils.trimFileProtocol(`${root.portProtonRoot}/data/user.conf`)
        : FileUtils.trimFileProtocol(`${root.homePath}/.Games/PortProton/data/user.conf`)

    property int viewIndex: 0
    property int settingsTabIndex: 0
    property var games: []
    property var settings: root.defaultSettings()
    property var prefixSettings: ({})
    property string settingsPrefix: ""
    property var prefixes: []
    property var wineVersions: []
    property var wineDetails: []
    property var wineCatalog: []
    property int wineTabIndex: 0
    property int wineCategoryIndex: 0
    property bool wineCatalogLoading: false
    property bool wineCatalogAttempted: false
    property string wineCatalogError: ""
    property bool wineManagerBusy: false
    property string wineManagerAction: ""
    property string wineManagerName: ""
    property string wineManagerStage: ""
    property string wineManagerMessage: ""
    property int wineManagerPercent: -1
    property string wineManagerLog: ""
    property bool wineResultReceived: false
    property bool wineCatalogReloadPending: false
    property var wineCommand: []
    readonly property var wineAvailableItems: {
        if (root.wineCatalog.length === 0) return [];
        const index = Math.max(0, Math.min(root.wineCategoryIndex, root.wineCatalog.length - 1));
        const category = root.wineCatalog[index];
        if (!category || !Array.isArray(category.items)) return [];
        return category.items.filter(item => !item.installed);
    }
    property string portProtonRoot: ""
    property string originalRoot: ""
    property string backendMode: "standalone"
    property bool originalAvailable: false
    property bool commandAvailable: false
    property bool portProtonReady: false
    property string statusText: ""
    property var userConf: ({})
    property var runningGames: []
    readonly property bool anyRunning: root.runningGames.length > 0
    readonly property bool standaloneMode: root.backendMode !== "native"

    property bool showGameDialog: false
    property int editIndex: -1
    property string draftName: ""
    property string draftExe: ""
    property string draftPrefix: "DEFAULT"
    property string draftWine: ""
    property string draftArgs: ""

    property bool showInstallDialog: false
    property string installStep: "idle"
    property string installInstaller: ""
    property string installName: ""
    property string installPrefixMode: "new"
    property string installPrefix: "DEFAULT"
    property string installPrefixName: ""
    property string installWine: ""
    property var installCommand: []
    property string installStage: ""
    property string installMessage: ""
    property int installPercent: -1
    property string installLog: ""
    property int installStartedAt: 0
    property int installElapsed: 0
    property bool installResultReceived: false
    property string helperAction: ""
    property var helperCommand: []
    property bool launchSucceeded: false
    readonly property string installHelperPath: decodeURIComponent(FileUtils.trimFileProtocol(String(Qt.resolvedUrl("portproton-install-helper.py"))))

    property bool showConfirm: false
    property string confirmTitle: ""
    property string confirmText: ""
    property var confirmAction: null

    property string pendingBackupPrefix: ""
    property string logText: ""
    property bool logLoading: false
    property bool libraryLoaded: false
    property bool infoLoaded: false

    readonly property var navItems: [
        { index: 0, icon: "library_books", label: "Библиотека" },
        { index: 6, icon: "install_desktop", label: "Установить" },
        { index: 5, icon: "download", label: "Импорт" },
        { index: 1, icon: "folder", label: "Префиксы" },
        { index: 2, icon: "wine_bar", label: "Wine / Proton" },
        { index: 3, icon: "terminal", label: "Логи" },
        { index: 4, icon: "settings", label: "Настройки" }
    ]

    readonly property var vulkanLabels: ["OpenGL", "Sarek", "Stable", "Newest"]
    readonly property var vulkanValues: ["0", "1", "2", "6"]

    property bool showDeveloperSettings: false

    readonly property var globalSettings: [
        { title: "Обновления и интерфейс", icon: "tune", items: [
            { key: "MIRROR", label: "Зеркало обновлений", hint: "Откуда скачивать обновления PortProton", type: "select", options: ["GITHUB", "CLOUD"], values: ["GITHUB", "CLOUD"] },
            { key: "BRANCH", label: "Ветка скриптов", hint: "master — стабильная, devel — свежие изменения", type: "select", options: ["Стабильная", "Разработка"], values: ["master", "devel"] },
            { key: "PW_GUI_START", label: "Стартовое меню", hint: "PANED — одна страница, NOTEBOOK — вкладки", type: "select", options: ["PANED", "NOTEBOOK"], values: ["PANED", "NOTEBOOK"] },
            { key: "GUI_THEME", label: "Тема PortProton", hint: "Оформление оригинального интерфейса", type: "select", options: ["default", "compact", "classic"], values: ["default", "compact", "classic"] },
            { key: "DESKTOP_WITH_TIME", label: "Показ времени", hint: "Время в ярлыках игр", type: "select", options: ["Выключено", "Часы и минуты", "Дни, часы, минуты"], values: ["disabled", "posnumber1", "posnumber2"] },
            { key: "SORT_WITH_TIME", label: "Сортировка ярлыков", hint: "Порядок ярлыков в оригинальном меню", type: "select", options: ["Выключено", "По последнему запуску", "По времени"], values: ["disabled", "lastlaunch", "bytime"] }
        ]},
        { title: "Запуск игр", icon: "memory", items: [
            { key: "DOWNLOAD_STEAM_GRID", label: "Скачивать обложки Steam", hint: "Загружать обложки для ярлыков", type: "bool" },
            { key: "PW_EMULS", label: "Вкладка эмуляторов", hint: "Показывать эмуляторы в оригинальном меню", type: "bool" },
            { key: "PW_GPU_USE", label: "Видеокарта", hint: "GPU для всех игр; пусто — авто", type: "text", placeholder: "авто" },
            { key: "PW_WINE_DPI_VALUE", label: "Форсированный DPI", hint: "recommended, disabled или число (80–240)", type: "select", options: ["recommended", "disabled", "80", "96", "120", "144", "168", "192", "216", "240"], values: ["recommended", "disabled", "80", "96", "120", "144", "168", "192", "216", "240"] },
            { key: "PW_VULKAN_UNLOCKED", label: "Разблокировать 3D API", hint: "Разрешить API без проверки видеокарты", type: "select", options: ["default", "unlocked"], values: ["default", "unlocked"] }
        ]}
    ]

    readonly property var prefixMainToggles: [
        { key: "mangohud", env: "PW_MANGOHUD", icon: "monitoring", label: "MangoHud", hint: "Оверлей FPS и нагрузки" },
        { key: "mangohudUserConf", env: "PW_MANGOHUD_USER_CONF", icon: "tune", label: "MangoHud User Conf", hint: "Системный конфиг MangoHud" },
        { key: "vkbasalt", env: "PW_VKBASALT", icon: "palette", label: "vkBasalt", hint: "Постобработка Vulkan" },
        { key: "vkbasaltUserConf", env: "PW_VKBASALT_USER_CONF", icon: "tune", label: "vkBasalt User Conf", hint: "Системный конфиг vkBasalt" },
        { key: "dgvoodoo2", env: "PW_DGVOODOO2", icon: "auto_awesome", label: "dgVoodoo2", hint: "Обёртка DirectDraw/Direct3D" },
        { key: "esync", env: "PW_USE_ESYNC", icon: "sync_alt", label: "Esync", hint: "Синхронизация eventfd" },
        { key: "fsync", env: "PW_USE_FSYNC", icon: "bolt", label: "Fsync", hint: "Синхронизация futex" },
        { key: "ntsync", env: "PW_USE_NTSYNC", icon: "sync", label: "NTSync", hint: "Синхронизация через ntsync" },
        { key: "rayTracing", env: "PW_USE_RAY_TRACING", icon: "flare", label: "Ray Tracing", hint: "VKD3D Ray Tracing" },
        { key: "dlss", env: "PW_USE_NVAPI_AND_DLSS", icon: "auto_awesome", label: "NVAPI и DLSS", hint: "DLSS на NVIDIA" },
        { key: "optiscaler", env: "PW_USE_OPTISCALER", icon: "zoom_out_map", label: "OptiScaler", hint: "Апскейлеры и frame gen" },
        { key: "lsFrameGen", env: "PW_USE_LS_FRAME_GEN", icon: "animation", label: "Lossless Scaling FG", hint: "Генерация кадров" },
        { key: "hideNvidia", env: "PW_HIDE_NVIDIA_GPU", icon: "visibility_off", label: "Скрыть NVIDIA GPU", hint: "Маскировать функции NVIDIA" },
        { key: "virtualDesktop", env: "PW_VIRTUAL_DESKTOP", icon: "desktop_windows", label: "Виртуальный рабочий стол", hint: "Запуск в виртуальном десктопе Wine" },
        { key: "terminal", env: "PW_USE_TERMINAL", icon: "terminal", label: "Терминал", hint: "Запускать игру в терминале" },
        { key: "guiDisabledCs", env: "PW_GUI_DISABLED_CS", icon: "visibility_off", label: "Скрыть меню запуска", hint: "Не показывать выбор режимов Wine" },
        { key: "gamemode", env: "PW_USE_GAMEMODE", icon: "speed", label: "GameMode", hint: "Оптимизация системы" },
        { key: "inhibitSleep", env: "PW_USE_INHIBIT_SLEEP", icon: "nightlight", label: "Не давать уснуть", hint: "Блокировать сон и скринсейвер" },
        { key: "d3dExtras", env: "PW_USE_D3D_EXTRAS", icon: "extension", label: "D3D Extras", hint: "Сторонние библиотеки DirectX" },
        { key: "fixVideo", env: "PW_FIX_VIDEO_IN_GAME", icon: "video_settings", label: "Фикс видео", hint: "Исправление цвета видео" },
        { key: "reducePulse", env: "PW_REDUCE_PULSE_LATENCY", icon: "volume_up", label: "Pulse низкая задержка", hint: "Уменьшить задержку звука" },
        { key: "gstreamer", env: "PW_USE_GSTREAMER", icon: "movie", label: "GStreamer", hint: "Видео через GStreamer" },
        { key: "shaderCache", env: "PW_USE_SHADER_CACHE", icon: "cached", label: "Кэш шейдеров", hint: "Кэширование шейдеров Wine" },
        { key: "systemVkLayers", env: "PW_USE_SYSTEM_VK_LAYERS", icon: "layers", label: "Системные Vulkan слои", hint: "MangoHud/vkBasalt из системы" },
        { key: "obsVkcapture", env: "PW_USE_OBS_VKCAPTURE", icon: "videocam", label: "OBS VkCapture", hint: "Захват через obs-vkcapture" },
        { key: "disableCompositing", env: "PW_DISABLE_COMPOSITING", icon: "block", label: "Отключить композитор", hint: "Отключить эффекты рабочего стола" },
        { key: "runtime", env: "PW_USE_RUNTIME", icon: "deployed_code", label: "Runtime", hint: "Контейнерный режим запуска" },
        { key: "dinput", env: "PW_DINPUT_PROTOCOL", icon: "gamepad", label: "DirectInput", hint: "DirectInput вместо XInput" },
        { key: "galliumZink", env: "PW_USE_GALLIUM_ZINK", icon: "memory", label: "Gallium Zink", hint: "OpenGL через Vulkan" },
        { key: "wined3dVulkan", env: "PW_USE_WINED3D_VULKAN", icon: "memory", label: "WineD3D Vulkan", hint: "WineD3D через Vulkan" },
        { key: "suppliedDxvk", env: "PW_USE_SUPPLIED_DXVK_VKD3D", icon: "inventory_2", label: "DXVK из Wine", hint: "DXVK/VKD3D из состава Wine" },
        { key: "nativeWayland", env: "PW_USE_NATIVE_WAYLAND", icon: "open_in_browser", label: "Native Wayland", hint: "Экспериментальный Wayland" },
        { key: "dxvkHdr", env: "PW_USE_DXVK_HDR", icon: "hdr_on", label: "DXVK HDR", hint: "HDR в играх с Wayland" },
        { key: "gamescope", env: "PW_GAMESCOPE", icon: "sports_esports", label: "GameScope", hint: "Запуск через GameScope" },
        { key: "wineDxgi", env: "PW_USE_WINE_DXGI", icon: "filter_alt", label: "Wine DXGI", hint: "Встроенный DXGI Wine" },
        { key: "wineFsr", env: "PW_WINE_FULLSCREEN_FSR", icon: "zoom_out_map", label: "Wine FSR", hint: "Полноэкранный FSR" },
        { key: "eacBe", env: "PW_USE_EAC_AND_BE", icon: "security", label: "EAC и BattlEye", hint: "Рантаймы античитов" }
    ]

    readonly property var prefixAdvancedItems: [
        { key: "windowsVer", label: "Версия Windows", hint: "Версия эмуляции Windows для префикса", type: "select", options: ["11", "10", "7", "XP"], values: ["11", "10", "7", "XP"] },
        { key: "dllInstall", label: "Winetricks", hint: "Библиотеки через winetricks, через пробел", type: "text", placeholder: "vcrun2019 corefonts lucida" },
        { key: "dllOverrides", label: "WINEDLLOVERRIDES", hint: "Принудительные библиотеки; пусто — не менять", type: "text", placeholder: "d3dx9_36=n,b" },
        { key: "args", label: "Аргументы .exe", hint: "Добавить аргументы после exe-файла", type: "text", placeholder: "-dx11 -skipintro" },
        { key: "runAfterExe", label: "Второй .exe", hint: "Запустить после основного exe", type: "text", placeholder: "/path/to/second.exe" },
        { key: "runAfterDelay", label: "Задержка второго .exe", hint: "Секунды перед запуском второго exe", type: "text", placeholder: "3" },
        { key: "cpuLimit", label: "Ядра CPU", hint: "Ограничить число используемых ядер", type: "select", options: ["Отключено", "2", "4", "6", "8", "12", "16", "24", "32"], values: ["disabled", "2", "4", "6", "8", "12", "16", "24", "32"] },
        { key: "glVersion", label: "Версия OpenGL", hint: "Форсированная версия OpenGL", type: "select", options: ["Отключено", "4.6COMPAT", "4.5COMPAT", "4.3COMPAT", "4.1COMPAT", "3.3COMPAT", "3.2COMPAT"], values: ["disabled", "4.6COMPAT", "4.5COMPAT", "4.3COMPAT", "4.1COMPAT", "3.3COMPAT", "3.2COMPAT"] },
        { key: "vkd3dLevel", label: "VKD3D feature level", hint: "Максимальная версия DX12 для VKD3D", type: "select", options: ["Отключено", "12_2", "12_1", "12_0", "11_1", "11_0"], values: ["disabled", "12_2", "12_1", "12_0", "11_1", "11_0"] },
        { key: "locale", label: "Язык приложения", hint: "Например ru_RU.utf8; пусто — не менять", type: "text", placeholder: "ru_RU.utf8" },
        { key: "wsiMode", label: "Режим окна Vulkan/OpenGL", hint: "fifo, immediate, mailbox или relaxed", type: "select", options: ["Отключено", "fifo", "immediate", "mailbox", "relaxed"], values: ["disabled", "fifo", "immediate", "mailbox", "relaxed"] },
        { key: "soundDriver", label: "Звуковой драйвер", hint: "Драйвер звука Wine", type: "select", options: ["Отключено", "alsa", "oss", "pulse"], values: ["disabled", "alsa", "oss", "pulse"] }
    ]

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape) {
            if (root.showGameDialog) root.closeGameDialog();
            else if (root.showConfirm) root.cancelConfirm();
            else GlobalStates.portProtonOpen = false;
            event.accepted = true;
        }
    }

    onViewIndexChanged: {
        if (root.viewIndex === 3) root.refreshLog();
        if (root.viewIndex === 2 && !root.wineCatalogAttempted && !root.wineCatalogLoading && !wineProc.running) {
            root.loadWineCatalog(false);
        }
        if (root.viewIndex === 4) {
            userConfFile.reload();
            if (root.settingsPrefix.length === 0 || (root.prefixes.length > 0 && root.prefixes.indexOf(root.settingsPrefix) < 0)) {
                root.settingsPrefix = root.settingsPrefixName();
            }
        }
    }

    Component.onCompleted: {
        root.refreshPortProton();
        libraryFile.reload();
        portProtonConfFile.reload();
        userConfFile.reload();
    }

    function defaultSettings() {
        return {
            mangohud: false,
            gamemode: false,
            vulkan: "2",
            ntsync: true,
            fsync: false,
            esync: true,
            defaultPrefix: "DEFAULT",
            defaultWine: ""
        };
    }

    function defaultPrefixSettings() {
        return {
            mangohud: false,
            mangohudUserConf: false,
            vkbasalt: false,
            vkbasaltUserConf: false,
            dgvoodoo2: false,
            esync: false,
            fsync: false,
            ntsync: false,
            rayTracing: false,
            dlss: false,
            optiscaler: false,
            lsFrameGen: false,
            hideNvidia: false,
            virtualDesktop: false,
            terminal: false,
            guiDisabledCs: false,
            gamemode: false,
            inhibitSleep: true,
            d3dExtras: true,
            fixVideo: false,
            reducePulse: false,
            gstreamer: true,
            shaderCache: true,
            systemVkLayers: false,
            obsVkcapture: false,
            disableCompositing: false,
            runtime: true,
            dinput: false,
            galliumZink: false,
            wined3dVulkan: false,
            suppliedDxvk: true,
            nativeWayland: false,
            dxvkHdr: false,
            gamescope: false,
            wineDxgi: false,
            wineFsr: true,
            eacBe: true,
            windowsVer: "10",
            dllInstall: "",
            dllOverrides: "",
            args: "",
            runAfterExe: "",
            runAfterDelay: "3",
            cpuLimit: "disabled",
            glVersion: "disabled",
            vkd3dLevel: "disabled",
            locale: "",
            wsiMode: "disabled",
            soundDriver: "disabled"
        };
    }

    function settingsPrefixName() {
        const current = root.settingsPrefix;
        if (current.length > 0 && root.prefixes.indexOf(current) >= 0) return current;
        if (root.settings.defaultPrefix && (root.prefixes.length === 0 || root.prefixes.indexOf(root.settings.defaultPrefix) >= 0)) {
            return root.settings.defaultPrefix;
        }
        return root.prefixes.length > 0 ? root.prefixes[0] : "DEFAULT";
    }

    function prefixSettingsFor(prefix) {
        const name = prefix && prefix.length > 0 ? prefix : root.settingsPrefixName();
        return Object.assign(root.defaultPrefixSettings(), root.prefixSettings[name] || {});
    }

    function prefixValue(key, fallback) {
        const values = root.prefixSettingsFor(root.settingsPrefixName());
        if (Object.prototype.hasOwnProperty.call(values, key)) return values[key];
        return fallback !== undefined ? fallback : "";
    }

    function prefixBool(key) {
        return root.prefixValue(key, false) === true;
    }

    function prefixSelectIndex(item) {
        const value = String(root.prefixValue(item.key, item.values[0]));
        const index = item.values.indexOf(value);
        return index >= 0 ? index : 0;
    }

    function updatePrefixSetting(key, value) {
        const name = root.settingsPrefixName();
        const all = Object.assign({}, root.prefixSettings);
        const current = Object.assign(root.defaultPrefixSettings(), all[name] || {});
        current[key] = value;
        all[name] = current;
        root.prefixSettings = all;
        root.persistLibrary();
    }

    function resetPrefixSettings() {
        const name = root.settingsPrefixName();
        const all = Object.assign({}, root.prefixSettings);
        delete all[name];
        root.prefixSettings = all;
        root.persistLibrary();
        root.setStatus(`Настройки префикса ${name} сброшены`);
    }

    function cpuTopology(limit) {
        if (!limit || limit === "disabled") return "disabled";
        const count = parseInt(limit, 10);
        if (!count || count < 1) return "disabled";
        const cores = [];
        for (let i = 0; i < count; i++) cores.push(i);
        return `${count}:${cores.join(",")}`;
    }

    function setStatus(text) {
        root.statusText = text;
    }

    function bool01(value) {
        return value ? "1" : "0";
    }

    function userConfValue(key, fallback) {
        if (Object.prototype.hasOwnProperty.call(root.userConf, key)) return root.userConf[key];
        return fallback !== undefined ? fallback : "";
    }

    function userConfBool(key) {
        return ["1", "true", "enabled", "yes", "on"].indexOf(String(root.userConfValue(key, "0")).toLowerCase()) >= 0;
    }

    function userConfSelectIndex(item) {
        const value = String(root.userConfValue(item.key, item.values[0]));
        const index = item.values.indexOf(value);
        return index >= 0 ? index : 0;
    }

    function parseUserConf(text) {
        const values = {};
        const lines = String(text || "").split("\n");
        for (let i = 0; i < lines.length; i++) {
            const match = lines[i].match(/^\s*export\s+([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
            if (!match) continue;
            let value = match[2].trim();
            if ((value.startsWith("\"") && value.endsWith("\"")) || (value.startsWith("'") && value.endsWith("'"))) {
                value = value.slice(1, -1);
            }
            values[match[1]] = value;
        }
        root.userConf = values;
    }

    function saveUserConf(key, value) {
        const text = userConfFile.text() || "";
        const line = `export ${key}="${String(value).replace(/"/g, '\\"')}"`;
        const regex = new RegExp(`^\\s*export\\s+${key}=.*$`, "m");
        let next;
        if (text.length === 0) next = `${line}\n`;
        else if (regex.test(text)) next = text.replace(regex, line);
        else next = `${text}${text.endsWith("\n") ? "" : "\n"}${line}\n`;
        userConfFile.setText(next);
        const copy = Object.assign({}, root.userConf);
        copy[key] = String(value);
        root.userConf = copy;
        root.setStatus(`Сохранено: ${key}`);
    }

    function resetUserConf() {
        userConfFile.setText("");
        root.userConf = ({});
        root.setStatus("user.conf очищен");
    }

    function saveUserConfRaw() {
        const text = userConfEditor.text;
        userConfFile.setText(text);
        root.parseUserConf(text);
        root.setStatus("user.conf сохранён");
    }

    function reloadUserConfRaw() {
        userConfFile.reload();
        root.setStatus("user.conf перезагружен");
    }

    function persistLibrary() {
        libraryFile.setText(JSON.stringify({
            version: 2,
            settings: root.settings,
            prefixSettings: root.prefixSettings,
            games: root.games
        }, null, 2));
    }

    function parseLibrary(text) {
        try {
            const data = JSON.parse(text);
            root.games = Array.isArray(data.games) ? data.games : [];
            const next = Object.assign(root.defaultSettings(), data.settings || {});
            next.vulkan = String(next.vulkan || "2");
            root.settings = next;
            root.prefixSettings = data.prefixSettings && typeof data.prefixSettings === "object" && !Array.isArray(data.prefixSettings)
                ? data.prefixSettings
                : {};
            if (root.settingsPrefix.length === 0) root.settingsPrefix = next.defaultPrefix || "DEFAULT";
            const deduped = root.dedupeGames(root.games);
            if (JSON.stringify(deduped) !== JSON.stringify(root.games)) {
                root.games = deduped;
                root.persistLibrary();
            }
        } catch (e) {
            console.log("[portproton] library parse error:", e);
            root.setStatus("Не удалось прочитать библиотеку");
        }
        root.libraryLoaded = true;
        root.maybeImportShortcuts();
    }

    function normalizeExePath(path) {
        return (path || "").replace(/\/PortProton\/prefixes\//, "/PortProton/data/prefixes/");
    }

    function dedupeGames(list) {
        const result = [];
        for (let i = 0; i < list.length; i++) {
            const game = list[i];
            const index = result.findIndex((entry) => root.normalizeExePath(entry.exe) === root.normalizeExePath(game.exe));
            if (index < 0) {
                result.push(game);
                continue;
            }
            const previous = result[index];
            result[index] = Object.assign({}, previous, {
                name: previous.name || game.name,
                prefix: previous.prefix || game.prefix,
                wine: previous.wine || game.wine,
                args: previous.args || game.args,
                icon: previous.icon || game.icon || "",
                desktopFile: previous.desktopFile || game.desktopFile || "",
                source: previous.source || game.source || "",
                lastPlayed: Math.max(previous.lastPlayed || 0, game.lastPlayed || 0)
            });
        }
        return result;
    }

    function maybeImportShortcuts() {
        if (root.libraryLoaded && root.infoLoaded && root.portProtonRoot.length > 0 && !shortcutsProc.running) {
            shortcutsProc.running = true;
        }
    }

    function extractShortcutExe(exec) {
        const quoted = [];
        const re = /"([^"]+)"/g;
        let match;
        while ((match = re.exec(exec)) !== null) quoted.push(match[1]);
        for (let i = quoted.length - 1; i >= 0; i--) {
            if (/\.(exe|msi|bat|lnk)$/i.test(quoted[i])) return quoted[i];
        }
        const tokens = exec.split(/\s+/);
        for (let i = tokens.length - 1; i >= 0; i--) {
            const token = tokens[i].replace(/^"|"$/g, "");
            if (/\.(exe|msi|bat|lnk)$/i.test(token)) return token;
        }
        return "";
    }

    function parseDesktopShortcuts(text) {
        const result = [];
        const chunks = text.split("@@@FILE@@@");
        for (let c = 1; c < chunks.length; c++) {
            const chunk = chunks[c];
            const nl = chunk.indexOf("\n");
            if (nl < 0) continue;
            const file = chunk.substring(0, nl).trim();
            const body = chunk.substring(nl + 1);
            const readKey = (key) => {
                const match = body.match(new RegExp("^" + key + "=(.*)$", "m"));
                return match ? match[1].trim() : "";
            };
            const exe = root.extractShortcutExe(readKey("Exec"));
            if (exe.length === 0) continue;
            const prefixMatch = exe.match(/\/prefixes\/([^/]+)\//);
            const wineMatch = body.match(/PW_WINE_USE="?([^"\s]+)"?/);
            result.push({
                file: file,
                name: readKey("Name"),
                exe: exe,
                icon: readKey("Icon"),
                prefix: prefixMatch ? prefixMatch[1] : "",
                wine: wineMatch ? wineMatch[1] : ""
            });
        }
        return result;
    }

    function importShortcuts(shortcuts) {
        if (!shortcuts || shortcuts.length === 0) return;
        const next = root.games.slice();
        let added = 0;
        let enriched = 0;
        for (let i = 0; i < shortcuts.length; i++) {
            const shortcut = shortcuts[i];
            const normalized = root.normalizeExePath(shortcut.exe);
            const index = next.findIndex((game) => root.normalizeExePath(game.exe) === normalized
                || (shortcut.file.length > 0 && game.desktopFile === shortcut.file));
            if (index < 0) {
                next.push({
                    id: root.newGameId(),
                    name: shortcut.name || shortcut.exe.substring(shortcut.exe.lastIndexOf("/") + 1),
                    exe: shortcut.exe,
                    prefix: shortcut.prefix || root.settings.defaultPrefix || "DEFAULT",
                    wine: shortcut.wine || "",
                    args: "",
                    icon: shortcut.icon || "",
                    desktopFile: shortcut.file,
                    source: "portproton",
                    lastPlayed: 0
                });
                added++;
                continue;
            }
            const game = next[index];
            const updated = Object.assign({}, game, {
                prefix: game.prefix || shortcut.prefix || root.settings.defaultPrefix || "DEFAULT",
                wine: game.wine || shortcut.wine || "",
                icon: game.icon || shortcut.icon || "",
                desktopFile: game.desktopFile || shortcut.file,
                source: game.source || "portproton"
            });
            if (JSON.stringify(updated) !== JSON.stringify(game)) {
                next[index] = updated;
                enriched++;
            }
        }
        const deduped = root.dedupeGames(next);
        if (JSON.stringify(deduped) !== JSON.stringify(root.games)) {
            root.games = deduped;
            root.persistLibrary();
        }
        if (added > 0) root.setStatus(`Импортировано ярлыков: ${added}`);
        else if (enriched > 0) root.setStatus("Ярлыки обновлены");
    }

    function updateSetting(key, value) {
        const next = Object.assign({}, root.settings);
        next[key] = value;
        root.settings = next;
        root.persistLibrary();
    }

    function normalizeSettings() {
        const next = Object.assign(root.defaultSettings(), root.settings || {});
        next.vulkan = String(next.vulkan || "2");
        root.settings = next;
    }

    function newGameId() {
        return Date.now().toString(36) + Math.random().toString(36).slice(2, 7);
    }

    function openAddDialog() {
        root.editIndex = -1;
        root.draftName = "";
        root.draftExe = "";
        root.draftPrefix = root.settings.defaultPrefix || (root.prefixes.length > 0 ? root.prefixes[0] : "DEFAULT");
        root.draftWine = root.settings.defaultWine || "";
        root.draftArgs = "";
        root.showGameDialog = true;
    }

    function openEditDialog(index) {
        const game = root.games[index];
        if (!game) return;
        root.editIndex = index;
        root.draftName = game.name || "";
        root.draftExe = game.exe || "";
        root.draftPrefix = game.prefix || root.settings.defaultPrefix || "DEFAULT";
        root.draftWine = game.wine || "";
        root.draftArgs = game.args || "";
        root.showGameDialog = true;
    }

    function closeGameDialog() {
        root.showGameDialog = false;
    }

    function saveGame() {
        const name = root.draftName.trim();
        const exe = root.draftExe.trim();
        if (name.length === 0 || exe.length === 0) {
            root.setStatus("Укажи название и путь к исполняемому файлу");
            return;
        }
        const existing = root.editIndex >= 0 ? root.games[root.editIndex] : null;
        const game = {
            id: existing ? existing.id : root.newGameId(),
            name: name,
            exe: exe,
            prefix: root.draftPrefix || "DEFAULT",
            wine: root.draftWine || "",
            args: root.draftArgs || "",
            icon: existing ? (existing.icon || "") : "",
            desktopFile: existing ? (existing.desktopFile || "") : "",
            source: existing ? (existing.source || "manual") : "manual",
            lastPlayed: existing ? (existing.lastPlayed || 0) : 0
        };
        const next = root.games.slice();
        if (root.editIndex >= 0) next[root.editIndex] = game;
        else next.push(game);
        root.games = next;
        root.persistLibrary();
        root.closeGameDialog();
        root.setStatus(`Сохранено: ${game.name}`);
    }

    function removeGame(index) {
        const game = root.games[index];
        if (!game) return;
        const next = root.games.slice();
        next.splice(index, 1);
        root.games = next;
        root.persistLibrary();
        root.setStatus(`Удалено из библиотеки: ${game.name}`);
    }

    function askConfirm(title, text, action) {
        root.confirmTitle = title;
        root.confirmText = text;
        root.confirmAction = action;
        root.showConfirm = true;
    }

    function cancelConfirm() {
        root.showConfirm = false;
        root.confirmAction = null;
    }

    function confirmProceed() {
        const action = root.confirmAction;
        root.showConfirm = false;
        root.confirmAction = null;
        if (action) action();
    }

    function askRemoveGame(index) {
        const game = root.games[index];
        if (!game) return;
        root.askConfirm("Удалить игру?",
            `Убрать «${game.name}» из библиотеки? Файлы игры и префикс останутся на диске.`,
            function () { root.removeGame(index); });
    }

    function askClearPrefix(prefix) {
        root.askConfirm("Очистить префикс?",
            `Очистить префикс ${prefix}? Все данные внутри него будут удалены.`,
            function () {
                root.runHelper("clear-prefix", ["clear-prefix", "--root", root.portProtonRoot, "--prefix", prefix]);
                root.setStatus(`Очищаю префикс ${prefix}…`);
            });
    }

    function launchGame(index) {
        const game = root.games[index];
        if (!game || !game.exe) return;
        const prefix = game.prefix || root.settings.defaultPrefix || "DEFAULT";
        const prefixConfig = root.prefixSettingsFor(prefix);
        const args = [
            "launch",
            "--root", root.portProtonRoot,
            "--prefix", prefix,
            "--exe", game.exe
        ];
        if (game.name) args.push("--name", game.name);
        const wine = game.wine || root.settings.defaultWine || "";
        if (wine.length > 0) args.push("--wine", wine);
        const launchArgs = prefixConfig.args.length > 0 ? prefixConfig.args : (game.args || "");
        if (launchArgs.length > 0) args.push("--args", launchArgs);
        const add = (key, value) => {
            if (value !== undefined && value !== null && String(value).length > 0) {
                args.push("--env", `${key}=${value}`);
            }
        };
        add("PW_PREFIX_NAME", prefix);
        add("PW_WINE_USE", wine);
        add("PW_VULKAN_USE", root.settings.vulkan || "2");
        for (let i = 0; i < root.prefixMainToggles.length; i++) {
            const item = root.prefixMainToggles[i];
            add(item.env, root.bool01(prefixConfig[item.key]));
        }
        add("PW_WINDOWS_VER", prefixConfig.windowsVer);
        add("PW_DLL_INSTALL", prefixConfig.dllInstall);
        add("WINEDLLOVERRIDES", prefixConfig.dllOverrides);
        add("PW_RUN_AFTER_EXE", prefixConfig.runAfterExe);
        add("PW_RUN_AFTER_DELAY", prefixConfig.runAfterDelay);
        add("PW_WINE_CPU_TOPOLOGY", root.cpuTopology(prefixConfig.cpuLimit));
        add("PW_MESA_GL_VERSION_OVERRIDE", prefixConfig.glVersion);
        add("PW_VKD3D_FEATURE_LEVEL", prefixConfig.vkd3dLevel);
        add("PW_LOCALE_SELECT", prefixConfig.locale);
        add("PW_MESA_VK_WSI_PRESENT_MODE", prefixConfig.wsiMode);
        add("PW_SOUND_DRIVER_USE", prefixConfig.soundDriver);
        root.launchSucceeded = false;
        root.runHelper("launch", args);

        const next = root.games.slice();
        if (next[index]) {
            next[index] = Object.assign({}, next[index], { lastPlayed: Date.now() });
            root.games = next;
            root.persistLibrary();
        }
        root.setStatus(`Запускаю: ${game.name}`);
    }

    function runHelper(action, args) {
        if (helperProc.running) {
            root.setStatus("Дождись завершения текущей операции");
            return;
        }
        root.helperAction = action;
        root.helperCommand = ["python3", root.installHelperPath].concat(args);
        helperProc.running = true;
    }

    function stopGame(exe) {
        const args = ["stop", "--root", root.portProtonRoot];
        if (exe) args.push("--exe", exe);
        root.runHelper("stop", args);
        root.setStatus("Останавливаю Wine-процессы…");
    }

    function stopAllGames() {
        root.runHelper("stop", ["stop", "--root", root.portProtonRoot, "--all"]);
        root.setStatus("Останавливаю все Wine-процессы…");
    }

    function openPath(path) {
        if (!path || path.length === 0) return;
        Quickshell.execDetached(["xdg-open", path]);
    }

    function wineManaged(wineId) {
        for (let i = 0; i < root.wineDetails.length; i++) {
            const wine = root.wineDetails[i];
            if (wine.id === wineId) return !!wine.managed;
        }
        return false;
    }

    function loadWineCatalog(refresh) {
        if (wineProc.running) return;
        root.wineCatalogAttempted = true;
        root.wineManagerAction = "catalog";
        root.wineResultReceived = false;
        root.wineCatalogLoading = true;
        root.wineCatalogError = "";
        root.wineCommand = [
            "python3", root.installHelperPath, "wine-catalog",
            "--root", root.portProtonRoot
        ];
        if (refresh) root.wineCommand.push("--refresh");
        wineProc.running = true;
    }

    function downloadWineVersion(name, url) {
        if (wineProc.running) {
            root.setStatus("Дождись завершения текущей операции с Wine/Proton");
            return;
        }
        root.wineManagerAction = "install";
        root.wineManagerName = name;
        root.wineManagerStage = "download";
        root.wineManagerMessage = `Скачиваю ${name}…`;
        root.wineManagerPercent = 0;
        root.wineManagerLog = "";
        root.wineResultReceived = false;
        root.wineManagerBusy = true;
        root.wineCommand = [
            "python3", root.installHelperPath, "wine-install",
            "--root", root.portProtonRoot, "--wine", name
        ];
        if (url) root.wineCommand.push("--url", url);
        wineProc.running = true;
        root.setStatus(`Скачивание Wine/Proton: ${name}`);
    }

    function askRemoveWine(name) {
        root.askConfirm("Удалить Wine/Proton?",
            `Удалить ${name} из data/dist? Префиксы и игры, использующие эту версию, могут перестать запускаться.`,
            function () {
                if (wineProc.running) {
                    root.setStatus("Дождись завершения текущей операции с Wine/Proton");
                    return;
                }
                root.wineManagerAction = "remove";
                root.wineManagerName = name;
                root.wineManagerStage = "remove";
                root.wineManagerMessage = `Удаляю ${name}…`;
                root.wineManagerPercent = 0;
                root.wineManagerLog = "";
                root.wineResultReceived = false;
                root.wineManagerBusy = true;
                root.wineCommand = [
                    "python3", root.installHelperPath, "wine-remove",
                    "--root", root.portProtonRoot, "--wine", name
                ];
                wineProc.running = true;
                root.setStatus(`Удаление Wine/Proton: ${name}`);
            });
    }

    function applyWineCatalog(data) {
        root.wineCatalog = Array.isArray(data.categories) ? data.categories : [];
        root.wineCatalogError = String(data.warning || "");
        if (root.wineCategoryIndex >= root.wineCatalog.length) root.wineCategoryIndex = 0;
        if (wineCategoryTabs) wineCategoryTabs.currentIndex = root.wineCategoryIndex;
        if (root.wineTabIndex === 0 && root.wineVersions.length === 0 && root.wineCatalog.length > 0) root.wineTabIndex = 1;
        if (wineSectionTabs) wineSectionTabs.currentIndex = root.wineTabIndex;
        root.wineCatalogLoading = false;
        const count = root.wineCatalog.reduce((total, category) => total + (category.items ? category.items.length : 0), 0);
        root.setStatus(`Доступно версий Wine/Proton: ${count}`);
    }

    function handleWineData(data) {
        if (!data) return;
        if (data.type === "progress") {
            root.wineManagerStage = String(data.stage || "");
            root.wineManagerMessage = String(data.message || "");
            if (typeof data.percent === "number") root.wineManagerPercent = data.percent;
            if (data.log) root.wineManagerLog = String(data.log);
            return;
        }
        if (data.type === "error" || data.error) {
            const message = String(data.error || "неизвестная ошибка");
            root.wineResultReceived = true;
            root.wineManagerBusy = false;
            root.wineCatalogLoading = false;
            if (root.wineManagerAction === "catalog") root.wineCatalogError = message;
            root.setStatus(`Ошибка Wine/Proton: ${message}`);
            return;
        }
        if (data.type !== "result") return;
        root.wineResultReceived = true;
        if (root.wineManagerAction === "catalog") {
            root.applyWineCatalog(data);
        } else if (root.wineManagerAction === "install") {
            root.wineManagerBusy = false;
            root.wineManagerPercent = 100;
            root.setStatus(`Wine/Proton установлен: ${data.installed || root.wineManagerName}`);
            root.refreshPortProton();
            root.wineCatalogReloadPending = true;
        } else if (root.wineManagerAction === "remove") {
            root.wineManagerBusy = false;
            root.wineManagerPercent = 100;
            root.setStatus(`Wine/Proton удалён: ${data.removed || root.wineManagerName}`);
            root.refreshPortProton();
            root.wineCatalogReloadPending = true;
        }
        root.wineManagerAction = "";
    }

    function openGameFolder(index) {
        const game = root.games[index];
        if (!game || !game.exe) return;
        const slash = game.exe.lastIndexOf("/");
        root.openPath(slash > 0 ? game.exe.substring(0, slash) : root.homePath);
    }

    function openWineFolder(version) {
        if (!root.portProtonRoot || !version) return;
        root.openPath(`${root.portProtonRoot}/data/dist/${version}`);
    }

    function openWineTool(tool, prefix) {
        const name = String(tool || "").replace(/^--/, "").replace(/^winecmd$/, "cmd");
        root.runHelper("tool", [
            "tool", "--root", root.portProtonRoot,
            "--prefix", prefix || "DEFAULT",
            "--tool", name
        ]);
        root.setStatus(`Открываю ${name} для ${prefix || "DEFAULT"}…`);
    }

    function refreshPortProton() {
        if (infoProc.running) return;
        infoProc.running = true;
    }

    function parseJsonLine(text) {
        const lines = String(text || "").trim().split("\n");
        for (let i = lines.length - 1; i >= 0; i--) {
            const line = lines[i].trim();
            if (!line.startsWith("{")) continue;
            try {
                return JSON.parse(line);
            } catch (e) {
                console.log("[portproton] json parse error:", e, line);
            }
        }
        return null;
    }

    function parsePortProtonInfo(text) {
        const data = root.parseJsonLine(text);
        if (!data) {
            root.setStatus("Не удалось получить данные PortProton");
            root.infoLoaded = true;
            root.maybeImportShortcuts();
            return;
        }
        root.backendMode = data.mode || "standalone";
        root.portProtonRoot = data.root || "";
        root.originalRoot = data.originalRoot || "";
        root.originalAvailable = !!data.originalAvailable;
        root.commandAvailable = !!data.commandAvailable;
        root.portProtonReady = !!data.ready;
        root.prefixes = Array.isArray(data.prefixes) ? data.prefixes : [];
        root.wineDetails = Array.isArray(data.wines) ? data.wines : [];
        root.wineVersions = Array.isArray(data.wineVersions)
            ? data.wineVersions
            : root.wineDetails.map(wine => wine.id);
        root.runningGames = Array.isArray(data.running) ? data.running : [];

        const next = Object.assign({}, root.settings);
        if (root.prefixes.length > 0 && root.prefixes.indexOf(next.defaultPrefix) === -1) {
            next.defaultPrefix = root.prefixes.indexOf("DEFAULT") !== -1 ? "DEFAULT" : root.prefixes[0];
        }
        if (next.defaultWine.length > 0 && root.wineVersions.indexOf(next.defaultWine) === -1) {
            next.defaultWine = "";
        }
        root.settings = next;
        if (root.settingsPrefix.length === 0 || (root.prefixes.length > 0 && root.prefixes.indexOf(root.settingsPrefix) < 0)) {
            root.settingsPrefix = next.defaultPrefix || "DEFAULT";
        }

        if (root.portProtonReady) {
            const modeLabel = root.standaloneMode ? "автономный" : "native";
            root.setStatus(`PortProton (${modeLabel}): ${root.prefixes.length} префикс(ов), ${root.wineVersions.length} версия(й) Wine/Proton`);
        } else if (root.standaloneMode) {
            root.setStatus(root.originalAvailable
                ? "Не найден Wine/Proton — установи wine или укажи версию"
                : "PortProton не найден — установи wine или PortProton");
        } else {
            root.setStatus("PortProton не настроен — запусти первичную настройку");
        }
        root.infoLoaded = true;
        root.maybeImportShortcuts();
    }

    function parseHelperResult(text) {
        const data = root.parseJsonLine(text);
        if (!data) return null;
        if (data.type === "error" || data.error) {
            root.setStatus(`Ошибка: ${data.error || "неизвестная ошибка"}`);
            return data;
        }
        return data;
    }

    function handleHelperResult(data) {
        if (!data) return;
        const action = root.helperAction;
        if (data.type === "error" || data.error) {
            root.helperAction = "";
            return;
        }
        if (action === "launch" && data.running) {
            root.launchSucceeded = true;
            launchCloseTimer.restart();
            root.runningGames = root.runningGames.concat([data.running]);
            root.setStatus(`Запущено: ${data.running.name || data.running.exe}`);
        } else if (action === "stop") {
            root.refreshRunning();
            root.setStatus("Wine-процессы остановлены");
        } else if (action === "clear-prefix") {
            root.setStatus(`Префикс ${data.prefix || ""} очищен`);
            root.refreshPortProton();
        } else if (action === "backup") {
            root.setStatus(`Бэкап создан: ${data.archive || ""}`);
        } else if (action === "restore") {
            root.setStatus(`Префикс восстановлен из ${data.restored || ""}`);
            root.refreshPortProton();
        } else if (action === "tool") {
            root.setStatus(`Открыто: ${data.tool || ""}`);
        } else if (action === "create-prefix") {
            root.setStatus(`Префикс ${data.prefix || ""} готов`);
            root.refreshPortProton();
        }
        root.helperAction = "";
    }

    function refreshRunning() {
        if (statusProc.running || root.portProtonRoot.length === 0) return;
        statusProc.command = ["python3", root.installHelperPath, "status", "--root", root.portProtonRoot];
        statusProc.running = true;
    }

    function refreshLog() {
        if (!root.portProtonReady) {
            root.logText = "PortProton ещё не настроен. Сначала запусти первичную настройку.";
            return;
        }
        root.logLoading = true;
        logProc.running = true;
    }

    function createPrefix() {
        inputProc.running = true;
    }

    function applyNewPrefix(name) {
        const prefix = name.trim();
        if (prefix.length === 0) return;
        root.openWineTool("--winecfg", prefix);
        refreshTimer.start();
    }

    function backupPrefix(prefix) {
        root.pendingBackupPrefix = prefix;
        pickDirProc.running = true;
    }

    function applyBackupDir(path) {
        const prefix = root.pendingBackupPrefix;
        root.pendingBackupPrefix = "";
        if (!prefix || !path) return;
        root.runHelper("backup", [
            "backup", "--root", root.portProtonRoot,
            "--prefix", prefix, "--dest", path
        ]);
        root.setStatus(`Бэкап префикса ${prefix} → ${path}…`);
    }

    function restorePrefix() {
        pickPackProc.running = true;
    }

    function applyRestorePack(path) {
        if (!path) return;
        root.runHelper("restore", ["restore", "--root", root.portProtonRoot, "--pack", path]);
        root.setStatus(`Восстанавливаю префикс из ${path}…`);
    }

    function pickExe() {
        pickExeProc.running = true;
    }

    function applyPickedExe(path) {
        root.draftExe = path;
        if (root.draftName.trim().length === 0) {
            const base = path.substring(path.lastIndexOf("/") + 1);
            const dot = base.lastIndexOf(".");
            root.draftName = dot > 0 ? base.substring(0, dot) : base;
        }
    }

    function vulkanIndex() {
        const index = root.vulkanValues.indexOf(String(root.settings.vulkan));
        return index >= 0 ? index : 2;
    }

    function setVulkanIndex(index) {
        if (index >= 0 && index < root.vulkanValues.length) {
            root.updateSetting("vulkan", root.vulkanValues[index]);
        }
    }

    function prefixNameFromGame(name) {
        return String(name || "").trim().toUpperCase()
            .replace(/[^A-Z0-9]+/g, "_")
            .replace(/^_+|_+$/g, "");
    }

    function applyGlobalSettingsToPrefix(prefix) {
        if (!prefix || prefix.length === 0) return;
        const all = Object.assign({}, root.prefixSettings);
        const current = Object.assign(root.defaultPrefixSettings(), all[prefix] || {});
        current.mangohud = !!root.settings.mangohud;
        current.gamemode = !!root.settings.gamemode;
        current.esync = !!root.settings.esync;
        current.fsync = !!root.settings.fsync;
        current.ntsync = !!root.settings.ntsync;
        for (let i = 0; i < root.prefixMainToggles.length; i++) {
            const item = root.prefixMainToggles[i];
            if (Object.prototype.hasOwnProperty.call(root.userConf, item.env)) {
                current[item.key] = root.userConfBool(item.env);
            }
        }
        const windowsVer = root.userConfValue("PW_WINDOWS_VER", "");
        if (windowsVer.length > 0) current.windowsVer = windowsVer;
        const locale = root.userConfValue("PW_LOCALE_SELECT", "");
        if (locale.length > 0) current.locale = locale;
        const soundDriver = root.userConfValue("PW_SOUND_DRIVER_USE", "");
        if (soundDriver.length > 0) current.soundDriver = soundDriver;
        all[prefix] = current;
        root.prefixSettings = all;
    }

    function updateInstallName(text) {
        const previousAuto = root.prefixNameFromGame(root.installName);
        root.installName = text;
        const nextAuto = root.prefixNameFromGame(text);
        if (root.installPrefixName.length === 0 || root.installPrefixName === previousAuto) {
            root.installPrefixName = nextAuto;
        }
    }

    function installResolvedPrefix() {
        if (root.installPrefixMode === "existing") {
            return root.installPrefix || root.settings.defaultPrefix || "DEFAULT";
        }
        let name = root.prefixNameFromGame(root.installPrefixName.trim());
        if (name.length === 0) name = root.prefixNameFromGame(root.installName);
        if (name.length === 0) name = "GAME_" + Date.now().toString(36).toUpperCase();
        return name;
    }

    function openInstallDialog() {
        root.installInstaller = "";
        root.installName = "";
        root.installPrefixMode = "new";
        root.installPrefix = root.settings.defaultPrefix || (root.prefixes.length > 0 ? root.prefixes[0] : "DEFAULT");
        root.installPrefixName = "";
        root.installWine = root.settings.defaultWine || "";
        root.installStep = "idle";
        root.installStage = "";
        root.installMessage = "";
        root.installPercent = -1;
        root.installLog = "";
        root.installElapsed = 0;
        root.installResultReceived = false;
        root.showInstallDialog = true;
    }

    function closeInstallDialog() {
        if (root.installStep === "installing" || root.installStep === "scanning") return;
        root.showInstallDialog = false;
    }

    function pickInstaller() {
        pickInstallerProc.running = true;
    }

    function applyPickedInstaller(path) {
        root.installInstaller = path;
        const base = path.substring(path.lastIndexOf("/") + 1).replace(/\.(exe|msi|bat)$/i, "");
        const cleaned = base.replace(/[_\-. ]?(setup|installer|install|setup_x64|x64|win64|win32)$/i, "").trim();
        const guess = cleaned.length > 0 ? cleaned : base;
        if (root.installName.trim().length === 0) {
            root.installName = guess;
            root.installPrefixName = root.prefixNameFromGame(guess);
        }
    }

    function startInstall() {
        const installer = root.installInstaller.trim();
        const name = root.installName.trim();
        if (installer.length === 0 || name.length === 0) {
            root.setStatus("Укажи установщик и название игры");
            return;
        }
        if (!root.portProtonReady) {
            root.setStatus("PortProton не настроен — сначала запусти первичную настройку");
            return;
        }
        const prefix = root.installResolvedPrefix();
        if (root.installPrefixMode === "new") {
            if (root.prefixes.indexOf(prefix) >= 0) {
                root.setStatus(`Префикс ${prefix} уже существует — выбери его в списке существующих`);
                return;
            }
        }
        root.installPrefix = prefix;
        root.installStep = "installing";
        root.installStage = "prepare";
        root.installMessage = "Подготовка установки…";
        root.installPercent = 3;
        root.installLog = "";
        root.installElapsed = 0;
        root.installStartedAt = Date.now();
        root.installResultReceived = false;
        const config = root.prefixSettingsFor(prefix);
        root.installCommand = [
            "python3", root.installHelperPath, "install",
            "--root", root.portProtonRoot,
            "--prefix", prefix,
            "--name", name,
            "--installer", installer,
            "--wine", root.installWine || root.settings.defaultWine || "",
            "--windows-ver", config.windowsVer || "",
            "--locale", config.locale || "",
            "--sound-driver", config.soundDriver || "",
            "--dll-install", config.dllInstall || "",
            "--dll-overrides", config.dllOverrides || ""
        ];
        installProc.running = true;
        installElapsedTimer.start();
        root.setStatus(/\.bat$/i.test(installer)
            ? `Установка ${name} в префикс ${prefix}… Заверши установку в окне Wine`
            : `Установка ${name} в префикс ${prefix}…`);
    }

    function appendInstallLog(line) {
        if (!line) return;
        const next = (root.installLog.length > 0 ? root.installLog + "\n" : "") + String(line).trim();
        root.installLog = next.length > 4000 ? next.substring(next.length - 4000) : next;
    }

    function handleInstallLine(line) {
        const data = root.parseJsonLine(line);
        if (!data) return;
        if (data.type === "progress") {
            root.installStage = data.stage || root.installStage;
            if (data.message) {
                root.installMessage = data.message;
                root.setStatus(data.message);
            }
            if (typeof data.percent === "number") root.installPercent = data.percent;
            if (data.log) root.appendInstallLog(data.log);
            return;
        }
        if (data.type === "result") {
            root.applyInstallResult(data);
            return;
        }
        if (data.type === "error") {
            root.applyInstallResult(data);
        }
    }

    function applyInstallResult(payload) {
        if (root.installStep !== "installing") return;
        let data = payload;
        if (typeof payload === "string") data = root.parseJsonLine(payload);
        const prefix = root.installPrefix;
        const gameName = root.installName.trim() || "Игра";
        root.installResultReceived = true;
        installElapsedTimer.stop();
        root.installStep = "idle";
        if (!data || data.type === "error" || data.error) {
            root.showInstallDialog = true;
            root.installMessage = data && data.error ? data.error : "Установщик завершился без результата";
            root.setStatus(`Установка не удалась: ${root.installMessage}`);
            return;
        }
        root.installPercent = 100;
        root.showInstallDialog = false;
        if (root.installPrefixMode === "new") {
            root.applyGlobalSettingsToPrefix(prefix);
            root.persistLibrary();
        }
        if (!data || !data.exe) {
            root.draftName = gameName;
            root.draftExe = "";
            root.draftPrefix = prefix;
            root.draftWine = root.installWine;
            root.draftArgs = "";
            root.editIndex = -1;
            root.showGameDialog = true;
            root.setStatus("Установка завершена, но файл запуска не найден — укажи его вручную");
            return;
        }
        const existingIndex = root.games.findIndex((game) => root.normalizeExePath(game.exe) === root.normalizeExePath(data.exe));
        const existing = existingIndex >= 0 ? root.games[existingIndex] : null;
        const game = {
            id: existing ? existing.id : root.newGameId(),
            name: gameName,
            exe: data.exe,
            prefix: data.prefix || prefix,
            wine: root.installWine || (existing ? existing.wine : "") || "",
            args: existing ? (existing.args || "") : "",
            icon: data.icon || (existing ? existing.icon : "") || "",
            desktopFile: data.desktopFile || (existing ? existing.desktopFile : "") || "",
            source: existing ? (existing.source || "installer") : "installer",
            lastPlayed: existing ? (existing.lastPlayed || 0) : 0
        };
        const next = root.games.slice();
        if (existingIndex >= 0) next[existingIndex] = game;
        else next.push(game);
        root.games = next;
        root.persistLibrary();
        root.refreshPortProton();
        root.viewIndex = 0;
        root.setStatus(`Установлено: ${game.name} → ${game.exe}`);
    }

    FileView {
        id: libraryFile
        path: root.libraryPath
        onLoaded: root.parseLibrary(text())
        onLoadFailed: (error) => {
            if (error === FileViewError.FileNotFound) {
                root.games = [];
                root.settings = root.defaultSettings();
            } else {
                console.log("[portproton] library load failed:", error);
            }
            root.libraryLoaded = true;
            root.maybeImportShortcuts();
        }
        onSaved: root.setStatus("Библиотека сохранена")
        onSaveFailed: (error) => root.setStatus(`Ошибка сохранения библиотеки: ${FileViewError.toString(error)}`)
    }

    FileView {
        id: portProtonConfFile
        path: root.portProtonConfigPath
        onLoaded: root.refreshPortProton()
        onLoadFailed: (error) => {
            if (error !== FileViewError.FileNotFound) {
                console.log("[portproton] config load failed:", error);
            }
        }
    }

    FileView {
        id: userConfFile
        path: root.userConfPath
        onLoaded: {
            root.parseUserConf(text());
            userConfEditor.text = text();
        }
        onLoadFailed: (error) => {
            if (error === FileViewError.FileNotFound) {
                root.userConf = ({});
                userConfEditor.text = "";
            } else {
                console.log("[portproton] user.conf load failed:", error);
            }
        }
        onSaved: root.setStatus("user.conf сохранён")
        onSaveFailed: (error) => root.setStatus(`Ошибка user.conf: ${FileViewError.toString(error)}`)
    }

    Process {
        id: infoProc
        running: false
        command: ["python3", root.installHelperPath, "info", "--root", root.portProtonRoot]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.parsePortProtonInfo(text)
        }
        stderr: SplitParser {
            onRead: data => console.log("[portproton] info:", data)
        }
        onExited: (exitCode) => {
            if (exitCode !== 0) root.setStatus("Не удалось прочитать данные PortProton");
        }
    }

    Process {
        id: statusProc
        running: false
        command: ["python3", root.installHelperPath, "status", "--root", root.portProtonRoot]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const data = root.parseJsonLine(text);
                if (data && Array.isArray(data.running)) root.runningGames = data.running;
            }
        }
    }

    Process {
        id: helperProc
        running: false
        command: root.helperCommand
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.handleHelperResult(root.parseHelperResult(text))
        }
        stderr: SplitParser {
            onRead: data => console.log("[portproton] helper:", data)
        }
        onExited: (exitCode) => {
            Qt.callLater(() => {
                const action = root.helperAction;
                if (action === "launch" && root.launchSucceeded) {
                    launchCloseTimer.restart();
                } else if (action === "launch") {
                    root.setStatus(exitCode === 0
                        ? "Не удалось запустить игру: helper не вернул результат"
                        : `Запуск завершился с кодом ${exitCode}`);
                } else if (action.length > 0) {
                    if (exitCode !== 0) root.setStatus(`Операция завершилась с кодом ${exitCode}`);
                }
                root.helperAction = "";
            });
        }
    }

    Timer {
        id: launchCloseTimer
        interval: 350
        repeat: false
        onTriggered: {
            if (root.launchSucceeded) {
                root.launchSucceeded = false;
                GlobalStates.portProtonOpen = false;
            }
        }
    }

    Process {
        id: wineProc
        running: false
        command: root.wineCommand
        stdout: SplitParser {
            onRead: data => root.handleWineData(root.parseJsonLine(data))
        }
        stderr: SplitParser {
            onRead: data => console.log("[portproton] wine:", data)
        }
        onExited: (exitCode) => {
            Qt.callLater(() => {
                if (!root.wineResultReceived) {
                    const message = `Операция Wine/Proton завершилась с кодом ${exitCode}`;
                    if (root.wineManagerAction === "catalog") root.wineCatalogError = message;
                    else root.setStatus(message);
                }
                root.wineResultReceived = false;
                root.wineManagerBusy = false;
                root.wineCatalogLoading = false;
                root.wineManagerAction = "";
                if (root.wineCatalogReloadPending) {
                    root.wineCatalogReloadPending = false;
                    root.loadWineCatalog(false);
                }
            });
        }
    }

    Process {
        id: shortcutsProc
        running: false
        command: [
            "bash", "-c",
            'root="$1"; [ -d "$root" ] || exit 0; for f in "$root"/*.desktop; do [ -f "$f" ] || continue; [ "$(basename "$f")" = "PortProton.desktop" ] && continue; printf "@@@FILE@@@%s\\n" "$f"; cat "$f"; printf "\\n"; done',
            "_", root.portProtonRoot
        ]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.importShortcuts(root.parseDesktopShortcuts(text))
        }
    }

    Process {
        id: logProc
        running: false
        command: [
            "bash", "-c",
            'log="$1/PortProton.log"; if [ -f "$log" ]; then tail -n 800 "$log"; else echo "Лог не найден: $log"; fi',
            "_", root.portProtonRoot
        ]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.logText = text;
                root.logLoading = false;
            }
        }
        onExited: root.logLoading = false
    }

    Process {
        id: pickExeProc
        running: false
        command: ["kdialog", "--getopenfilename", root.homePath, "*.exe *.msi *.bat *.lnk"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const path = text.trim();
                if (path.length > 0) root.applyPickedExe(path);
            }
        }
    }

    Process {
        id: pickInstallerProc
        running: false
        command: ["kdialog", "--getopenfilename", root.homePath, "*.exe *.msi *.bat"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const path = text.trim();
                if (path.length > 0) root.applyPickedInstaller(path);
            }
        }
    }

    Process {
        id: installProc
        running: false
        command: root.installCommand
        stdout: SplitParser {
            onRead: data => root.handleInstallLine(data)
        }
        stderr: SplitParser {
            onRead: data => root.appendInstallLog(data)
        }
        onExited: (exitCode) => {
            if (root.installStep === "installing" && !root.installResultReceived) {
                root.applyInstallResult({
                    type: "error",
                    error: exitCode === 0
                        ? "Установщик завершился без результата"
                        : `Установщик завершился с кодом ${exitCode}`
                });
            }
        }
    }

    Process {
        id: pickDirProc
        running: false
        command: ["kdialog", "--getexistingdirectory", root.homePath]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const path = text.trim();
                if (path.length > 0) root.applyBackupDir(path);
            }
        }
    }

    Process {
        id: pickPackProc
        running: false
        command: ["kdialog", "--getopenfilename", root.homePath, "*.ppack"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const path = text.trim();
                if (path.length > 0) root.applyRestorePack(path);
            }
        }
    }

    Process {
        id: inputProc
        running: false
        command: ["kdialog", "--inputbox", "Имя нового префикса", "DEFAULT"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const name = text.trim();
                if (name.length > 0) root.applyNewPrefix(name);
            }
        }
    }

    Timer {
        id: refreshTimer
        interval: 1200
        repeat: false
        onTriggered: root.refreshPortProton()
    }

    Timer {
        id: runningTimer
        interval: 5000
        repeat: true
        running: root.portProtonRoot.length > 0
        onTriggered: root.refreshRunning()
    }

    Timer {
        id: installElapsedTimer
        interval: 1000
        repeat: true
        onTriggered: {
            if (root.installStep === "installing") {
                root.installElapsed = Math.floor((Date.now() - root.installStartedAt) / 1000);
            } else {
                installElapsedTimer.stop();
            }
        }
    }

    Rectangle {
        id: background
        anchors.fill: parent
        radius: Appearance.rounding.screenRounding - Appearance.sizes.elevationMargin
        color: Appearance.colors.colLayer0
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 58
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 10

                    Rectangle {
                        implicitWidth: 42
                        implicitHeight: 42
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colPrimary

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "sports_esports"
                            iconSize: 25
                            color: Appearance.colors.colOnPrimary
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            text: "PortProton"
                            font.pixelSize: Appearance.font.pixelSize.larger
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            text: root.portProtonReady
                                ? (root.standaloneMode
                                    ? (root.originalAvailable ? "Автономный режим · данные PortProton импортированы" : "Автономный режим · Wine/Proton")
                                    : "Оригинальный PortProton CLI")
                                : "Требуется Wine/Proton или PortProton"
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colOnLayer1Inactive
                        }
                    }

                    Rectangle {
                        implicitWidth: statusChip.implicitWidth + 18
                        implicitHeight: 24
                        radius: height / 2
                        color: root.portProtonReady ? Appearance.colors.colPrimaryContainer : Appearance.colors.colErrorContainer

                        StyledText {
                            id: statusChip
                            anchors.centerIn: parent
                            text: root.anyRunning
                                ? `${root.runningGames.length} запущено`
                                : (root.portProtonReady ? "готов" : "не настроен")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: root.portProtonReady ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnErrorContainer
                        }
                    }

                    IconToolbarButton {
                        implicitWidth: 34
                        implicitHeight: 34
                        visible: root.anyRunning
                        text: "stop_circle"
                        onClicked: root.stopAllGames()
                        StyledToolTip { text: "Остановить все Wine-процессы" }
                    }

                    IconAndTextToolbarButton {
                        implicitHeight: 34
                        iconText: "refresh"
                        text: "Обновить"
                        onClicked: root.refreshPortProton()
                        StyledToolTip { text: "Перечитать префиксы и версии Wine/Proton" }
                    }

                    IconAndTextToolbarButton {
                        implicitHeight: 34
                        iconText: "add"
                        text: "Добавить игру"
                        onClicked: root.openAddDialog()
                        StyledToolTip { text: "Добавить .exe/.msi/.bat в библиотеку" }
                    }

                    IconAndTextToolbarButton {
                        implicitHeight: 34
                        iconText: "install_desktop"
                        text: "Установить"
                        onClicked: root.openInstallDialog()
                        StyledToolTip { text: "Установить игру из setup.exe в отдельный префикс" }
                    }

                    IconToolbarButton {
                        implicitWidth: 34
                        implicitHeight: 34
                        text: "close"
                        onClicked: GlobalStates.portProtonOpen = false
                        StyledToolTip { text: "Закрыть" }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 200
                    Layout.fillHeight: true
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4

                        Repeater {
                            model: root.navItems

                            RippleButton {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 42
                                buttonRadius: Appearance.rounding.normal
                                toggled: root.viewIndex === modelData.index
                                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                                colBackgroundHover: Appearance.colors.colLayer2Hover
                                onClicked: root.viewIndex = modelData.index

                                contentItem: Item {
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        spacing: 10

                                        MaterialSymbol {
                                            text: modelData.icon
                                            iconSize: 20
                                            color: root.viewIndex === modelData.index
                                                ? Appearance.colors.colOnSecondaryContainer
                                                : Appearance.colors.colOnLayer1
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: modelData.label
                                            elide: Text.ElideRight
                                            color: root.viewIndex === modelData.index
                                                ? Appearance.colors.colOnSecondaryContainer
                                                : Appearance.colors.colOnLayer1
                                        }
                                    }
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }

                        Rectangle {
                            visible: !root.portProtonReady
                            Layout.fillWidth: true
                            implicitHeight: setupColumn.implicitHeight + 20
                            radius: Appearance.rounding.normal
                            color: Appearance.colors.colErrorContainer

                            ColumnLayout {
                                id: setupColumn
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 6

                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.commandAvailable ? "PortProton не настроен" : "Не найден Wine/Proton"
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnErrorContainer
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: "Скачай Wine/Proton во вкладке «Wine / Proton» — оригинальный PortProton не нужен."
                                    wrapMode: Text.Wrap
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colOnErrorContainer
                                }
                                DialogButton {
                                    buttonText: "Скачать Wine/Proton"
                                    onClicked: {
                                        root.viewIndex = 2;
                                        root.loadWineCatalog(true);
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1
                    clip: true

                    StackLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        currentIndex: root.viewIndex

                        Item {
                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: "Библиотека"
                                        font.pixelSize: Appearance.font.pixelSize.larger
                                        font.weight: Font.Medium
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    StyledText {
                                        text: `${root.games.length} игр`
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colOnLayer1Inactive
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    ColumnLayout {
                                        visible: root.games.length === 0
                                        anchors.centerIn: parent
                                        spacing: 10

                                        MaterialSymbol {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: "videogame_asset_off"
                                            iconSize: 56
                                            color: Appearance.colors.colOnLayer1Inactive
                                        }
                                        StyledText {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: "Пока нет игр"
                                            font.pixelSize: Appearance.font.pixelSize.larger
                                            font.weight: Font.Medium
                                            color: Appearance.colors.colOnLayer1
                                        }
                                        StyledText {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: "Добавь .exe/.msi/.bat — PortProton создаст префикс и запустит игру."
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: Appearance.colors.colOnLayer1Inactive
                                        }
                                        DialogButton {
                                            Layout.alignment: Qt.AlignHCenter
                                            buttonText: "Добавить игру"
                                            onClicked: root.openAddDialog()
                                        }
                                    }

                                    GridView {
                                        id: gamesGrid
                                        anchors.fill: parent
                                        visible: root.games.length > 0
                                        clip: true
                                        cellWidth: Math.max(240, (width - 12) / 2)
                                        cellHeight: 166
                                        model: root.games

                                        delegate: Rectangle {
                                            required property var modelData
                                            required property int index

                                            width: gamesGrid.cellWidth - 12
                                            height: gamesGrid.cellHeight - 12
                                            radius: Appearance.rounding.normal
                                            color: cardMouse.containsMouse
                                                ? Appearance.colors.colLayer2Hover
                                                : Appearance.colors.colLayer2
                                            border.width: 1
                                            border.color: Appearance.colors.colLayer0Border

                                            MouseArea {
                                                id: cardMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                acceptedButtons: Qt.NoButton
                                            }

                                            ColumnLayout {
                                                anchors.fill: parent
                                                anchors.margins: 12
                                                spacing: 6

                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 10

                                                    Rectangle {
                                                        implicitWidth: 44
                                                        implicitHeight: 44
                                                        radius: Appearance.rounding.normal
                                                        color: Appearance.colors.colPrimaryContainer
                                                        clip: true

                                                        MaterialSymbol {
                                                            anchors.centerIn: parent
                                                            text: "sports_esports"
                                                            iconSize: 24
                                                            color: Appearance.colors.colOnPrimaryContainer
                                                        }
                                                        Image {
                                                            anchors.fill: parent
                                                            anchors.margins: 4
                                                            source: modelData.icon ? `file://${modelData.icon}` : ""
                                                            fillMode: Image.PreserveAspectFit
                                                            asynchronous: true
                                                            visible: status === Image.Ready
                                                        }
                                                    }

                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 1

                                                        StyledText {
                                                            Layout.fillWidth: true
                                                            text: modelData.name
                                                            elide: Text.ElideRight
                                                            font.weight: Font.Medium
                                                            color: Appearance.colors.colOnLayer2
                                                        }
                                                        StyledText {
                                                            Layout.fillWidth: true
                                                            text: `${modelData.prefix || "DEFAULT"} · ${modelData.wine || "авто"}`
                                                            elide: Text.ElideRight
                                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                                            color: Appearance.colors.colOnLayer1Inactive
                                                        }
                                                    }
                                                }

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: modelData.exe
                                                    elide: Text.ElideMiddle
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    color: Appearance.colors.colOnLayer1Inactive
                                                }

                                                Item { Layout.fillHeight: true }

                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 4

                                                    RippleButton {
                                                        id: playButton
                                                        implicitHeight: 32
                                                        implicitWidth: playRow.implicitWidth + 24
                                                        buttonRadius: Appearance.rounding.full
                                                        colBackground: Appearance.colors.colPrimary
                                                        colBackgroundHover: Appearance.colors.colPrimaryHover
                                                        onClicked: root.launchGame(index)

                                                        contentItem: RowLayout {
                                                            id: playRow
                                                            spacing: 4
                                                            MaterialSymbol {
                                                                text: "play_arrow"
                                                                iconSize: 18
                                                                color: Appearance.colors.colOnPrimary
                                                            }
                                                            StyledText {
                                                                text: "Играть"
                                                                color: Appearance.colors.colOnPrimary
                                                            }
                                                        }
                                                    }

                                                    IconToolbarButton {
                                                        implicitWidth: 32
                                                        implicitHeight: 32
                                                        text: "edit"
                                                        onClicked: root.openEditDialog(index)
                                                        StyledToolTip { text: "Изменить" }
                                                    }

                                                    IconToolbarButton {
                                                        implicitWidth: 32
                                                        implicitHeight: 32
                                                        text: "delete"
                                                        onClicked: root.askRemoveGame(index)
                                                        StyledToolTip { text: "Убрать из библиотеки" }
                                                    }

                                                    Item { Layout.fillWidth: true }

                                                    IconToolbarButton {
                                                        implicitWidth: 32
                                                        implicitHeight: 32
                                                        text: "folder_open"
                                                        onClicked: root.openGameFolder(index)
                                                        StyledToolTip { text: "Открыть папку игры" }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Item {
                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 34
                                    Layout.maximumHeight: 34
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: "Префиксы"
                                        font.pixelSize: Appearance.font.pixelSize.larger
                                        font.weight: Font.Medium
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    IconAndTextToolbarButton {
                                        implicitHeight: 32
                                        iconText: "restore"
                                        text: "Восстановить"
                                        onClicked: root.restorePrefix()
                                    }
                                    IconAndTextToolbarButton {
                                        implicitHeight: 32
                                        iconText: "create_new_folder"
                                        text: "Создать"
                                        onClicked: root.createPrefix()
                                    }
                                }

                                StyledText {
                                    visible: root.prefixes.length === 0
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignHCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    text: root.portProtonReady
                                        ? "Префиксов пока нет. Создай первый префикс."
                                        : "Сначала настрой PortProton."
                                    color: Appearance.colors.colOnLayer1Inactive
                                }

                                ListView {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    visible: root.prefixes.length > 0
                                    clip: true
                                    spacing: 6
                                    model: root.prefixes

                                    delegate: Rectangle {
                                        required property string modelData

                                        width: ListView.view ? ListView.view.width : 0
                                        height: 62
                                        radius: Appearance.rounding.normal
                                        color: Appearance.colors.colLayer2

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 10
                                            spacing: 8

                                            MaterialSymbol {
                                                text: "folder"
                                                iconSize: 22
                                                color: Appearance.colors.colOnLayer2
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1
                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: modelData
                                                    elide: Text.ElideRight
                                                    font.weight: Font.Medium
                                                    color: Appearance.colors.colOnLayer2
                                                }
                                                StyledText {
                                                    text: "Wine prefix"
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    color: Appearance.colors.colOnLayer1Inactive
                                                }
                                            }

                                            IconToolbarButton {
                                                implicitWidth: 30
                                                implicitHeight: 30
                                                text: "settings"
                                                onClicked: root.openWineTool("--winecfg", modelData)
                                                StyledToolTip { text: "Winecfg" }
                                            }
                                            IconToolbarButton {
                                                implicitWidth: 30
                                                implicitHeight: 30
                                                text: "folder_open"
                                                onClicked: root.openWineTool("--winefile", modelData)
                                                StyledToolTip { text: "Wine file manager" }
                                            }
                                            IconToolbarButton {
                                                implicitWidth: 30
                                                implicitHeight: 30
                                                text: "terminal"
                                                onClicked: root.openWineTool("--winecmd", modelData)
                                                StyledToolTip { text: "Wine cmd" }
                                            }
                                            IconToolbarButton {
                                                implicitWidth: 30
                                                implicitHeight: 30
                                                text: "archive"
                                                onClicked: root.backupPrefix(modelData)
                                                StyledToolTip { text: "Бэкап префикса" }
                                            }
                                            IconToolbarButton {
                                                implicitWidth: 30
                                                implicitHeight: 30
                                                text: "delete_sweep"
                                                onClicked: root.askClearPrefix(modelData)
                                                StyledToolTip { text: "Очистить префикс" }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Item {
                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 34
                                    Layout.maximumHeight: 34
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: "Wine / Proton"
                                        font.pixelSize: Appearance.font.pixelSize.larger
                                        font.weight: Font.Medium
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    StyledText {
                                        visible: root.wineCatalogLoading
                                        text: "загрузка списка…"
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colOnLayer1Inactive
                                    }
                                    IconAndTextToolbarButton {
                                        implicitHeight: 32
                                        iconText: "refresh"
                                        text: "Обновить"
                                        onClicked: root.refreshPortProton()
                                    }
                                    IconAndTextToolbarButton {
                                        implicitHeight: 32
                                        iconText: "cloud_download"
                                        text: "Список версий"
                                        onClicked: root.loadWineCatalog(true)
                                    }
                                }

                                SecondaryTabBar {
                                    id: wineSectionTabs
                                    Layout.fillWidth: true
                                    currentIndex: root.wineTabIndex
                                    onCurrentIndexChanged: root.wineTabIndex = currentIndex

                                    SecondaryTabButton {
                                        buttonIcon: "check_circle"
                                        buttonText: "Установленные"
                                    }
                                    SecondaryTabButton {
                                        buttonIcon: "cloud_download"
                                        buttonText: "Не установленные"
                                    }
                                }

                                StackLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    currentIndex: root.wineTabIndex

                                    Item {
                                        ColumnLayout {
                                            anchors.fill: parent
                                            spacing: 6

                                            StyledText {
                                                Layout.fillWidth: true
                                                text: `Установленные версии Wine/Proton: ${root.wineVersions.length}`
                                                font.weight: Font.Medium
                                                color: Appearance.colors.colOnLayer1
                                            }

                                            StyledText {
                                                visible: root.wineVersions.length === 0
                                                Layout.fillWidth: true
                                                horizontalAlignment: Text.AlignHCenter
                                                text: "Версии Wine/Proton не найдены."
                                                color: Appearance.colors.colOnLayer1Inactive
                                            }

                                            ListView {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                visible: root.wineVersions.length > 0
                                                clip: true
                                                spacing: 6
                                                model: root.wineVersions

                                                delegate: Rectangle {
                                                    required property string modelData

                                                    width: ListView.view ? ListView.view.width : 0
                                                    height: 58
                                                    radius: Appearance.rounding.normal
                                                    color: Appearance.colors.colLayer2

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.margins: 10
                                                        spacing: 8

                                                        MaterialSymbol {
                                                            text: "wine_bar"
                                                            iconSize: 22
                                                            color: Appearance.colors.colOnLayer2
                                                        }
                                                        ColumnLayout {
                                                            Layout.fillWidth: true
                                                            spacing: 1
                                                            StyledText {
                                                                Layout.fillWidth: true
                                                                text: modelData
                                                                elide: Text.ElideRight
                                                                font.weight: Font.Medium
                                                                color: Appearance.colors.colOnLayer2
                                                            }
                                                            StyledText {
                                                                text: root.settings.defaultWine === modelData ? "По умолчанию" : "Wine/Proton"
                                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                                color: root.settings.defaultWine === modelData
                                                                    ? Appearance.colors.colPrimary
                                                                    : Appearance.colors.colOnLayer1Inactive
                                                            }
                                                        }

                                                        IconToolbarButton {
                                                            implicitWidth: 30
                                                            implicitHeight: 30
                                                            text: "star"
                                                            onClicked: {
                                                                root.updateSetting("defaultWine", modelData);
                                                                root.setStatus(`Wine/Proton по умолчанию: ${modelData}`);
                                                            }
                                                            StyledToolTip { text: "Сделать версией по умолчанию" }
                                                        }
                                                        IconToolbarButton {
                                                            implicitWidth: 30
                                                            implicitHeight: 30
                                                            text: "folder_open"
                                                            onClicked: root.openWineFolder(modelData)
                                                            StyledToolTip { text: "Открыть папку версии" }
                                                        }
                                                        IconToolbarButton {
                                                            implicitWidth: 30
                                                            implicitHeight: 30
                                                            visible: root.wineManaged(modelData)
                                                            text: "delete"
                                                            onClicked: root.askRemoveWine(modelData)
                                                            StyledToolTip { text: "Удалить версию из data/dist" }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    Item {
                                        ColumnLayout {
                                            anchors.fill: parent
                                            spacing: 6

                                            SecondaryTabBar {
                                                id: wineCategoryTabs
                                                Layout.fillWidth: true
                                                visible: root.wineCatalog.length > 0
                                                currentIndex: root.wineCategoryIndex
                                                onCurrentIndexChanged: root.wineCategoryIndex = currentIndex

                                                Repeater {
                                                    model: root.wineCatalog
                                                    delegate: SecondaryTabButton {
                                                        required property var modelData
                                                        buttonIcon: "deployed_code"
                                                        buttonText: modelData.label
                                                    }
                                                }
                                            }

                                            StyledText {
                                                visible: root.wineCatalogError.length > 0
                                                Layout.fillWidth: true
                                                text: root.wineCatalogError
                                                wrapMode: Text.Wrap
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: Appearance.colors.colError
                                            }

                                            StyledText {
                                                visible: root.wineCatalogLoading
                                                Layout.fillWidth: true
                                                horizontalAlignment: Text.AlignHCenter
                                                text: "Загрузка списка версий…"
                                                color: Appearance.colors.colOnLayer1Inactive
                                            }

                                            StyledText {
                                                visible: !root.wineCatalogLoading
                                                    && root.wineCatalog.length === 0
                                                    && root.wineCatalogError.length === 0
                                                Layout.fillWidth: true
                                                horizontalAlignment: Text.AlignHCenter
                                                text: "Список ещё не загружен."
                                                color: Appearance.colors.colOnLayer1Inactive
                                            }

                                            StyledText {
                                                visible: !root.wineCatalogLoading
                                                    && root.wineCatalog.length > 0
                                                    && root.wineAvailableItems.length === 0
                                                Layout.fillWidth: true
                                                horizontalAlignment: Text.AlignHCenter
                                                text: "Все версии из этой категории уже установлены."
                                                color: Appearance.colors.colOnLayer1Inactive
                                            }

                                            ListView {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                visible: root.wineAvailableItems.length > 0
                                                clip: true
                                                spacing: 6
                                                model: root.wineAvailableItems

                                                delegate: Rectangle {
                                                    required property var modelData

                                                    width: ListView.view ? ListView.view.width : 0
                                                    height: 52
                                                    radius: Appearance.rounding.normal
                                                    color: Appearance.colors.colLayer2

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.margins: 8
                                                        spacing: 8

                                                        MaterialSymbol {
                                                            text: "download"
                                                            iconSize: 20
                                                            color: Appearance.colors.colOnLayer2
                                                        }
                                                        ColumnLayout {
                                                            Layout.fillWidth: true
                                                            spacing: 1
                                                            StyledText {
                                                                Layout.fillWidth: true
                                                                text: modelData.name
                                                                elide: Text.ElideRight
                                                                color: Appearance.colors.colOnLayer2
                                                            }
                                                            StyledText {
                                                                Layout.fillWidth: true
                                                                text: modelData.size || (modelData.compatible ? "Wine/Proton" : "Может не поддерживаться этим CPU")
                                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                                color: modelData.compatible
                                                                    ? Appearance.colors.colOnLayer1Inactive
                                                                    : Appearance.colors.colError
                                                            }
                                                        }
                                                        IconToolbarButton {
                                                            implicitWidth: 30
                                                            implicitHeight: 30
                                                            text: "download"
                                                            onClicked: root.downloadWineVersion(modelData.name, modelData.url)
                                                            StyledToolTip { text: "Скачать и установить" }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    visible: root.wineManagerBusy
                                    implicitHeight: visible ? busyColumn.implicitHeight + 16 : 0
                                    radius: Appearance.rounding.normal
                                    color: Appearance.colors.colLayer2

                                    ColumnLayout {
                                        id: busyColumn
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 5

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: root.wineManagerMessage.length > 0
                                                ? root.wineManagerMessage
                                                : "Операция с Wine/Proton…"
                                            wrapMode: Text.Wrap
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: Appearance.colors.colOnLayer2
                                        }
                                        StyledProgressBar {
                                            Layout.fillWidth: true
                                            visible: root.wineManagerPercent >= 0
                                            value: Math.max(0, Math.min(1, root.wineManagerPercent / 100))
                                        }
                                        StyledIndeterminateProgressBar {
                                            Layout.fillWidth: true
                                            visible: root.wineManagerPercent < 0
                                        }
                                    }
                                }
                            }
                        }

                        Item {
                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 34
                                    Layout.maximumHeight: 34
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: "Лог PortProton"
                                        font.pixelSize: Appearance.font.pixelSize.larger
                                        font.weight: Font.Medium
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    StyledText {
                                        visible: root.logLoading
                                        text: "загрузка…"
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colOnLayer1Inactive
                                    }
                                    IconAndTextToolbarButton {
                                        implicitHeight: 32
                                        iconText: "refresh"
                                        text: "Обновить"
                                        onClicked: root.refreshLog()
                                    }
                                    IconToolbarButton {
                                        implicitWidth: 32
                                        implicitHeight: 32
                                        text: "folder_open"
                                        onClicked: root.openPath(root.portProtonRoot)
                                        StyledToolTip { text: "Открыть папку PortProton" }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: Appearance.rounding.normal
                                    color: Appearance.colors.colLayer0
                                    clip: true

                                    ScrollView {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        clip: true

                                        TextArea {
                                            id: logArea
                                            readOnly: true
                                            text: root.logText
                                            wrapMode: TextEdit.NoWrap
                                            color: Appearance.colors.colOnLayer0
                                            selectionColor: Appearance.colors.colSecondaryContainer
                                            selectedTextColor: Appearance.colors.colOnSecondaryContainer
                                            font.family: "monospace"
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            background: null
                                        }
                                    }
                                }
                            }
                        }

                        Item {
                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 8

                                SecondaryTabBar {
                                    id: settingsTabBar
                                    Layout.fillWidth: true
                                    currentIndex: root.settingsTabIndex
                                    onCurrentIndexChanged: {
                                        root.settingsTabIndex = currentIndex;
                                        if (currentIndex === 2)
                                            userConfEditor.text = userConfFile.text() || "";
                                    }

                                    SecondaryTabButton {
                                        buttonIcon: "public"
                                        buttonText: "Глобальные"
                                    }
                                    SecondaryTabButton {
                                        buttonIcon: "folder_managed"
                                        buttonText: "Префиксы"
                                    }
                                    SecondaryTabButton {
                                        buttonIcon: "code"
                                        buttonText: "Конфиг"
                                    }
                                }

                                StackLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    currentIndex: settingsTabBar.currentIndex

                                    Flickable {
                                        id: globalSettingsFlickable
                                        clip: true
                                        contentWidth: width
                                        contentHeight: globalSettingsColumn.implicitHeight + 12

                                        ColumnLayout {
                                            id: globalSettingsColumn
                                            width: Math.min(parent.width, 900)
                                            x: Math.max(0, (parent.width - width) / 2)
                                            spacing: 8

                                            StyledText {
                                                Layout.fillWidth: true
                                                text: "Глобальные настройки PortProton"
                                        font.pixelSize: Appearance.font.pixelSize.larger
                                        font.weight: Font.Medium
                                        color: Appearance.colors.colOnLayer1
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: `Файл: ${root.userConfPath}`
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colOnLayer1Inactive
                                        elide: Text.ElideMiddle
                                    }

                                    Repeater {
                                        model: root.globalSettings

                                        delegate: ColumnLayout {
                                            id: globalSection
                                            required property var modelData
                                            Layout.fillWidth: true
                                            spacing: 4

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.topMargin: 4
                                                spacing: 6

                                                MaterialSymbol {
                                                    text: globalSection.modelData.icon
                                                    iconSize: 18
                                                    color: Appearance.colors.colPrimary
                                                }
                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: globalSection.modelData.title
                                                    font.weight: Font.Medium
                                                    color: Appearance.colors.colOnLayer1
                                                }
                                            }

                                            Repeater {
                                                model: globalSection.modelData.items

                                                delegate: Rectangle {
                                                    id: globalRow
                                                    required property var modelData
                                                    Layout.fillWidth: true
                                                    implicitHeight: Math.max(58, globalRowLayout.implicitHeight + 20)
                                                    radius: Appearance.rounding.normal
                                                    color: Appearance.colors.colLayer2

                                                    RowLayout {
                                                        id: globalRowLayout
                                                        anchors.fill: parent
                                                        anchors.margins: 10
                                                        spacing: 10

                                                        MaterialSymbol {
                                                            text: globalRow.modelData.type === "bool" ? "toggle_on" : "edit"
                                                            iconSize: 20
                                                            color: Appearance.colors.colOnLayer2
                                                        }
                                                        ColumnLayout {
                                                            Layout.fillWidth: true
                                                            spacing: 1
                                                            StyledText {
                                                                Layout.fillWidth: true
                                                                text: globalRow.modelData.label
                                                                font.weight: Font.Medium
                                                                color: Appearance.colors.colOnLayer2
                                                            }
                                                            StyledText {
                                                                Layout.fillWidth: true
                                                                text: globalRow.modelData.hint
                                                                wrapMode: Text.Wrap
                                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                                color: Appearance.colors.colOnLayer1Inactive
                                                            }
                                                        }
                                                        StyledSwitch {
                                                            visible: globalRow.modelData.type === "bool"
                                                            checked: root.userConfBool(globalRow.modelData.key)
                                                            onToggled: root.saveUserConf(globalRow.modelData.key, checked ? "1" : "0")
                                                        }
                                                        StyledComboBox {
                                                            visible: globalRow.modelData.type === "select"
                                                            Layout.preferredWidth: 190
                                                            model: globalRow.modelData.options
                                                            currentIndex: root.userConfSelectIndex(globalRow.modelData)
                                                            onActivated: (index) => root.saveUserConf(globalRow.modelData.key, globalRow.modelData.values[index])
                                                        }
                                                        MaterialTextField {
                                                            visible: globalRow.modelData.type === "text"
                                                            Layout.preferredWidth: 250
                                                            placeholderText: globalRow.modelData.placeholder || ""
                                                            text: root.userConfValue(globalRow.modelData.key, "")
                                                            onEditingFinished: root.saveUserConf(globalRow.modelData.key, text)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 58
                                        radius: Appearance.rounding.normal
                                        color: Appearance.colors.colLayer2

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 10
                                            spacing: 10

                                            MaterialSymbol {
                                                text: "memory"
                                                iconSize: 20
                                                color: Appearance.colors.colOnLayer2
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1
                                                StyledText {
                                                    text: "DirectX → Vulkan"
                                                    font.weight: Font.Medium
                                                    color: Appearance.colors.colOnLayer2
                                                }
                                                StyledText {
                                                    text: "Режим DXVK/VKD3D, который передаётся PortProton"
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    color: Appearance.colors.colOnLayer1Inactive
                                                }
                                            }
                                            StyledComboBox {
                                                Layout.preferredWidth: 170
                                                model: root.vulkanLabels
                                                currentIndex: root.vulkanIndex()
                                                onActivated: (index) => root.setVulkanIndex(index)
                                            }
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 58
                                        radius: Appearance.rounding.normal
                                        color: Appearance.colors.colLayer2

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 10
                                            spacing: 10

                                            MaterialSymbol {
                                                text: "folder"
                                                iconSize: 20
                                                color: Appearance.colors.colOnLayer2
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1
                                                StyledText {
                                                    text: "Префикс по умолчанию"
                                                    font.weight: Font.Medium
                                                    color: Appearance.colors.colOnLayer2
                                                }
                                                StyledText {
                                                    text: "Используется, если у игры не задан свой префикс"
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    color: Appearance.colors.colOnLayer1Inactive
                                                }
                                            }
                                            StyledComboBox {
                                                Layout.preferredWidth: 170
                                                model: root.prefixes.length > 0 ? root.prefixes : ["DEFAULT"]
                                                currentIndex: Math.max(0, model.indexOf(root.settings.defaultPrefix))
                                                onActivated: (index) => root.updateSetting("defaultPrefix", model[index])
                                            }
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 58
                                        radius: Appearance.rounding.normal
                                        color: Appearance.colors.colLayer2

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 10
                                            spacing: 10

                                            MaterialSymbol {
                                                text: "wine_bar"
                                                iconSize: 20
                                                color: Appearance.colors.colOnLayer2
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1
                                                StyledText {
                                                    text: "Wine/Proton по умолчанию"
                                                    font.weight: Font.Medium
                                                    color: Appearance.colors.colOnLayer2
                                                }
                                                StyledText {
                                                    text: "Авто — использовать доступную версию"
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    color: Appearance.colors.colOnLayer1Inactive
                                                }
                                            }
                                            StyledComboBox {
                                                Layout.preferredWidth: 190
                                                model: ["Авто"].concat(root.wineVersions)
                                                currentIndex: root.settings.defaultWine.length > 0
                                                    ? 1 + Math.max(0, root.wineVersions.indexOf(root.settings.defaultWine))
                                                    : 0
                                                onActivated: (index) => root.updateSetting("defaultWine", index === 0 ? "" : model[index])
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.topMargin: 4
                                        spacing: 8

                                        DialogButton {
                                            buttonText: "Управление Wine/Proton"
                                            onClicked: {
                                                root.viewIndex = 2;
                                                root.loadWineCatalog(false);
                                            }
                                        }
                                        DialogButton {
                                            buttonText: "Папка PortProton"
                                            onClicked: root.openPath(root.portProtonRoot)
                                        }
                                        DialogButton {
                                            buttonText: "Сбросить user.conf"
                                            onClicked: root.askConfirm("Сбросить настройки?", "Удалить все значения из user.conf?", () => root.resetUserConf())
                                        }
                                        Item { Layout.fillWidth: true }
                                        StyledText {
                                            text: "Изменения сохраняются автоматически"
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: Appearance.colors.colOnLayer1Inactive
                                        }
                                    }

                                        }
                                    }

                                    Item {
                                        ColumnLayout {
                                            anchors.fill: parent
                                            spacing: 8

                                            Rectangle {
                                                Layout.fillWidth: true
                                                implicitHeight: 68
                                                radius: Appearance.rounding.normal
                                                color: Appearance.colors.colLayer2
                                                border.width: 1
                                                border.color: Appearance.colors.colOutlineVariant

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.margins: 12
                                                    spacing: 10

                                                    Rectangle {
                                                        implicitWidth: 40
                                                        implicitHeight: 40
                                                        radius: Appearance.rounding.full
                                                        color: Appearance.colors.colPrimaryContainer

                                                        MaterialSymbol {
                                                            anchors.centerIn: parent
                                                            text: "folder_managed"
                                                            iconSize: 22
                                                            color: Appearance.colors.colOnPrimaryContainer
                                                        }
                                                    }
                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 1
                                                        StyledText {
                                                            text: "Настраиваемый префикс"
                                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                                            color: Appearance.colors.colOnLayer1Inactive
                                                        }
                                                        StyledText {
                                                            Layout.fillWidth: true
                                                            text: root.settingsPrefixName()
                                                            font.pixelSize: Appearance.font.pixelSize.larger
                                                            font.weight: Font.DemiBold
                                                            color: Appearance.colors.colOnLayer1
                                                            elide: Text.ElideRight
                                                        }
                                                    }
                                                    StyledComboBox {
                                                        Layout.preferredWidth: 210
                                                        model: root.prefixes.length > 0 ? root.prefixes : ["DEFAULT"]
                                                        currentIndex: Math.max(0, model.indexOf(root.settingsPrefixName()))
                                                        onActivated: (index) => {
                                                            const list = root.prefixes.length > 0 ? root.prefixes : ["DEFAULT"];
                                                            root.settingsPrefix = list[index];
                                                        }
                                                    }
                                                }
                                            }

                                            StyledText {
                                                Layout.fillWidth: true
                                                text: "Настройки применяются для выбранного префикса (как в оригинальном PortProton)"
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: Appearance.colors.colOnLayer1Inactive
                                            }

                                            Flickable {
                                                id: prefixSettingsFlickable
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                clip: true
                                                contentWidth: width
                                                contentHeight: prefixSettingsColumn.implicitHeight + 12

                                                ColumnLayout {
                                                    id: prefixSettingsColumn
                                                    width: Math.min(parent.width, 900)
                                                    x: Math.max(0, (parent.width - width) / 2)
                                                    spacing: 8

                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        Layout.topMargin: 4
                                                        text: "Основные"
                                                        font.weight: Font.Medium
                                                        color: Appearance.colors.colOnLayer1
                                                    }

                                    GridLayout {
                                        Layout.fillWidth: true
                                        columns: 2
                                        columnSpacing: 8
                                        rowSpacing: 8

                                        Repeater {
                                            model: root.prefixMainToggles

                                            Rectangle {
                                                required property var modelData
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: 1
                                                Layout.preferredHeight: 64
                                                radius: Appearance.rounding.normal
                                                color: Appearance.colors.colLayer2

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.margins: 9
                                                    spacing: 8

                                                    MaterialSymbol {
                                                        Layout.alignment: Qt.AlignVCenter
                                                        text: modelData.icon
                                                        iconSize: 18
                                                        color: Appearance.colors.colOnLayer2
                                                    }
                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 1
                                                        StyledText {
                                                            Layout.fillWidth: true
                                                            text: modelData.label
                                                            font.weight: Font.Medium
                                                            elide: Text.ElideRight
                                                            color: Appearance.colors.colOnLayer2
                                                        }
                                                        StyledText {
                                                            Layout.fillWidth: true
                                                            text: modelData.hint
                                                            wrapMode: Text.Wrap
                                                            maximumLineCount: 2
                                                            elide: Text.ElideRight
                                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                                            color: Appearance.colors.colOnLayer1Inactive
                                                        }
                                                    }
                                                    StyledSwitch {
                                                        Layout.alignment: Qt.AlignVCenter
                                                        Layout.preferredWidth: 38
                                                        Layout.maximumWidth: 38
                                                        scale: 0.7
                                                        checked: root.prefixBool(modelData.key)
                                                        onToggled: root.updatePrefixSetting(modelData.key, checked)
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.topMargin: 4
                                        text: "Дополнительные"
                                        font.weight: Font.Medium
                                        color: Appearance.colors.colOnLayer1
                                    }

                                    Repeater {
                                        model: root.prefixAdvancedItems

                                        Rectangle {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            implicitHeight: Math.max(58, prefixAdvLayout.implicitHeight + 20)
                                            radius: Appearance.rounding.normal
                                            color: Appearance.colors.colLayer2

                                            RowLayout {
                                                id: prefixAdvLayout
                                                anchors.fill: parent
                                                anchors.margins: 10
                                                spacing: 10

                                                MaterialSymbol {
                                                    text: modelData.type === "bool" ? "toggle_on" : "edit"
                                                    iconSize: 20
                                                    color: Appearance.colors.colOnLayer2
                                                }
                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 1
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: modelData.label
                                                        font.weight: Font.Medium
                                                        color: Appearance.colors.colOnLayer2
                                                    }
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: modelData.hint
                                                        wrapMode: Text.Wrap
                                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                                        color: Appearance.colors.colOnLayer1Inactive
                                                    }
                                                }
                                                StyledComboBox {
                                                    visible: modelData.type === "select"
                                                    Layout.preferredWidth: 190
                                                    model: modelData.options
                                                    currentIndex: root.prefixSelectIndex(modelData)
                                                    onActivated: (index) => root.updatePrefixSetting(modelData.key, modelData.values[index])
                                                }
                                                MaterialTextField {
                                                    visible: modelData.type === "text"
                                                    Layout.preferredWidth: 250
                                                    placeholderText: modelData.placeholder || ""
                                                    text: root.prefixValue(modelData.key, "")
                                                    onEditingFinished: root.updatePrefixSetting(modelData.key, text)
                                                }
                                            }
                                        }
                                    }

                                    IconAndTextToolbarButton {
                                        Layout.fillWidth: true
                                        Layout.topMargin: 4
                                        implicitHeight: 36
                                        iconText: "restart_alt"
                                        text: "Сбросить настройки префикса"
                                        onClicked: root.askConfirm(
                                            "Сброс настроек префикса",
                                            `Вернуть настройки ${root.settingsPrefixName()} к значениям PortProton по умолчанию?`,
                                            () => root.resetPrefixSettings()
                                        )
                                    }
                                }
                            }
                        }
                    }

                                    Item {
                                        ColumnLayout {
                                            anchors.fill: parent
                                            spacing: 8

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 8

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: `Файл: ${root.userConfPath}`
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    color: Appearance.colors.colOnLayer1Inactive
                                                    elide: Text.ElideMiddle
                                                }
                                                IconAndTextToolbarButton {
                                                    implicitHeight: 32
                                                    Layout.fillHeight: false
                                                    iconText: "refresh"
                                                    text: "Перезагрузить"
                                                    onClicked: root.reloadUserConfRaw()
                                                }
                                                IconAndTextToolbarButton {
                                                    implicitHeight: 32
                                                    Layout.fillHeight: false
                                                    iconText: "save"
                                                    text: "Сохранить"
                                                    onClicked: root.saveUserConfRaw()
                                                }
                                            }

                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                radius: Appearance.rounding.normal
                                                color: Appearance.colors.colLayer0
                                                border.width: 1
                                                border.color: Appearance.colors.colOutlineVariant
                                                clip: true

                                                ScrollView {
                                                    anchors.fill: parent
                                                    anchors.margins: 1
                                                    clip: true
                                                    ScrollBar.horizontal.policy: ScrollBar.AsNeeded
                                                    ScrollBar.vertical.policy: ScrollBar.AsNeeded

                                                    TextArea {
                                                        id: userConfEditor
                                                        textFormat: TextEdit.PlainText
                                                        wrapMode: TextEdit.NoWrap
                                                        selectByMouse: true
                                                        padding: 12
                                                        color: Appearance.colors.colOnLayer1
                                                        selectionColor: Appearance.colors.colSecondaryContainer
                                                        selectedTextColor: Appearance.colors.colOnSecondaryContainer
                                                        font.family: Appearance.font.family.monospace
                                                        font.pixelSize: 13
                                                        background: Rectangle { color: "transparent" }

                                                        Keys.onPressed: (event) => {
                                                            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_S) {
                                                                root.saveUserConfRaw();
                                                                event.accepted = true;
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                }
            }
        }

                        Item {
                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 8

                                StyledText {
                                    Layout.fillWidth: true
                                    text: "Импорт игр"
                                    font.pixelSize: Appearance.font.pixelSize.larger
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnLayer1
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: "PortProton хранит ярлыки игр в виде .desktop-файлов. Автоматический импорт добавит все найденные ярлыки в библиотеку, не затрагивая уже добавленные игры."
                                    wrapMode: Text.Wrap
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colOnLayer1Inactive
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 112
                                    radius: Appearance.rounding.normal
                                    color: Appearance.colors.colLayer2

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 12

                                        MaterialSymbol {
                                            Layout.alignment: Qt.AlignVCenter
                                            text: "download"
                                            iconSize: 28
                                            color: Appearance.colors.colPrimary
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: "Автоматический импорт"
                                                font.weight: Font.Medium
                                                color: Appearance.colors.colOnLayer2
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: `Найти ярлыки в ${root.portProtonRoot || "папке PortProton"}`
                                                elide: Text.ElideMiddle
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: Appearance.colors.colOnLayer1Inactive
                                            }
                                        }
                                        DialogButton {
                                            buttonText: shortcutsProc.running ? "Импорт…" : "Импортировать"
                                            enabled: !shortcutsProc.running
                                            onClicked: {
                                                if (root.portProtonRoot.length > 0)
                                                    shortcutsProc.running = true;
                                                else
                                                    root.setStatus("PortProton не настроен — импорт недоступен");
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 112
                                    radius: Appearance.rounding.normal
                                    color: Appearance.colors.colLayer2

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 12

                                        MaterialSymbol {
                                            Layout.alignment: Qt.AlignVCenter
                                            text: "add_circle"
                                            iconSize: 28
                                            color: Appearance.colors.colPrimary
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: "Выбрать вручную"
                                                font.weight: Font.Medium
                                                color: Appearance.colors.colOnLayer2
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: "Добавить конкретный .exe / .msi / .bat в библиотеку"
                                                wrapMode: Text.Wrap
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: Appearance.colors.colOnLayer1Inactive
                                            }
                                        }
                                        DialogButton {
                                            buttonText: "Добавить вручную"
                                            onClicked: root.openAddDialog()
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 4
                                    spacing: 8

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: `Игр в библиотеке: ${root.games.length}`
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnLayer1Inactive
                                    }
                                    DialogButton {
                                        buttonText: "Папка PortProton"
                                        onClicked: root.openPath(root.portProtonRoot)
                                    }
                                }

                                Item { Layout.fillHeight: true }
                            }
                        }

                        Item {
                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 8

                                StyledText {
                                    Layout.fillWidth: true
                                    text: "Установка игр"
                                    font.pixelSize: Appearance.font.pixelSize.larger
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnLayer1
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: "Выбери setup.exe или .msi, задай название и префикс. PortProton установит игру, а лаунчер сам найдёт исполняемый файл, заберёт иконку и создаст ярлык."
                                    wrapMode: Text.Wrap
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colOnLayer1Inactive
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 128
                                    radius: Appearance.rounding.normal
                                    color: Appearance.colors.colLayer2

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 12

                                        MaterialSymbol {
                                            Layout.alignment: Qt.AlignVCenter
                                            text: "install_desktop"
                                            iconSize: 30
                                            color: Appearance.colors.colPrimary
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: "Установить из setup.exe"
                                                font.weight: Font.Medium
                                                color: Appearance.colors.colOnLayer2
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: "Новый или существующий префикс · глобальные настройки · авто-ярлык"
                                                wrapMode: Text.Wrap
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: Appearance.colors.colOnLayer1Inactive
                                            }
                                        }
                                        DialogButton {
                                            buttonText: "Выбрать установщик"
                                            enabled: root.portProtonReady
                                            onClicked: root.openInstallDialog()
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 96
                                    radius: Appearance.rounding.normal
                                    color: Appearance.colors.colLayer2

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 12

                                        MaterialSymbol {
                                            Layout.alignment: Qt.AlignVCenter
                                            text: "folder_managed"
                                            iconSize: 26
                                            color: Appearance.colors.colPrimary
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: "Изолированный префикс"
                                                font.weight: Font.Medium
                                                color: Appearance.colors.colOnLayer2
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: "Для установщика можно сразу создать отдельный префикс и перенести в него глобальные настройки."
                                                wrapMode: Text.Wrap
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: Appearance.colors.colOnLayer1Inactive
                                            }
                                        }
                                    }
                                }

                                Item { Layout.fillHeight: true }
                            }
                        }
    }
}
}

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 6

                    MaterialSymbol {
                        text: root.portProtonReady ? "check_circle" : "warning"
                        iconSize: 14
                        color: root.portProtonReady ? Appearance.colors.colPrimary : Appearance.colors.colError
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.statusText.length > 0
                            ? root.statusText
                            : (root.portProtonReady ? "PortProton готов" : "PortProton не настроен")
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colOnLayer1Inactive
                    }
                    StyledText {
                        text: root.portProtonRoot
                        elide: Text.ElideMiddle
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colOnLayer1Inactive
                        Layout.maximumWidth: 360
                    }
                }
            }
        }
    }

    WindowDialog {
        id: gameDialog
        z: 10
        anchors.fill: parent
        show: root.showGameDialog
        backgroundWidth: 560
        onDismiss: root.closeGameDialog()

        WindowDialogTitle {
            text: root.editIndex >= 0 ? "Изменить игру" : "Добавить игру"
        }
        WindowDialogSeparator {}

        MaterialTextField {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            placeholderText: "Название"
            text: root.draftName
            onTextEdited: root.draftName = text
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            MaterialTextField {
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                placeholderText: "Путь к .exe / .msi / .bat"
                text: root.draftExe
                onTextEdited: root.draftExe = text
            }
            IconToolbarButton {
                implicitWidth: 44
                implicitHeight: 44
                text: "folder_open"
                onClicked: root.pickExe()
                StyledToolTip { text: "Выбрать файл" }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                StyledText {
                    text: "Префикс"
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnLayer1Inactive
                }
                StyledComboBox {
                    model: root.prefixes.length > 0 ? root.prefixes : ["DEFAULT"]
                    currentIndex: Math.max(0, model.indexOf(root.draftPrefix))
                    onActivated: (index) => root.draftPrefix = model[index]
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                StyledText {
                    text: "Wine/Proton"
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnLayer1Inactive
                }
                StyledComboBox {
                    model: ["Авто"].concat(root.wineVersions)
                    currentIndex: root.draftWine.length > 0
                        ? 1 + Math.max(0, root.wineVersions.indexOf(root.draftWine))
                        : 0
                    onActivated: (index) => root.draftWine = index === 0 ? "" : model[index]
                }
            }
        }

        MaterialTextField {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            placeholderText: "Аргументы запуска (необязательно)"
            text: root.draftArgs
            onTextEdited: root.draftArgs = text
        }

        WindowDialogButtonRow {
            DialogButton {
                buttonText: "Отмена"
                onClicked: root.closeGameDialog()
            }
            Item { Layout.fillWidth: true }
            DialogButton {
                buttonText: root.editIndex >= 0 ? "Сохранить" : "Добавить"
                onClicked: root.saveGame()
            }
        }
    }

    WindowDialog {
        id: installDialog
        z: 10
        anchors.fill: parent
        show: root.showInstallDialog
        backgroundWidth: 600
        onDismiss: root.closeInstallDialog()

        WindowDialogTitle {
            text: "Установить игру"
        }
        WindowDialogSeparator {}

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            MaterialTextField {
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                placeholderText: "Установщик: setup.exe / .msi"
                text: root.installInstaller
                onTextEdited: root.installInstaller = text
            }
            IconToolbarButton {
                implicitWidth: 44
                implicitHeight: 44
                text: "folder_open"
                onClicked: root.pickInstaller()
                StyledToolTip { text: "Выбрать установщик" }
            }
        }

        MaterialTextField {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            placeholderText: "Название игры"
            text: root.installName
            onTextEdited: root.updateInstallName(text)
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                StyledText {
                    text: "Префикс"
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnLayer1Inactive
                }
                StyledComboBox {
                    model: ["Новый префикс", "Существующий префикс"]
                    currentIndex: root.installPrefixMode === "existing" ? 1 : 0
                    onActivated: (index) => root.installPrefixMode = index === 1 ? "existing" : "new"
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                StyledText {
                    text: "Wine/Proton"
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnLayer1Inactive
                }
                StyledComboBox {
                    model: ["Авто"].concat(root.wineVersions)
                    currentIndex: root.installWine.length > 0
                        ? 1 + Math.max(0, root.wineVersions.indexOf(root.installWine))
                        : 0
                    onActivated: (index) => root.installWine = index === 0 ? "" : model[index]
                }
            }
        }

        MaterialTextField {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            visible: root.installPrefixMode === "new"
            placeholderText: "Имя нового префикса"
            text: root.installPrefixName
            onTextEdited: root.installPrefixName = text
        }

        StyledComboBox {
            Layout.fillWidth: true
            visible: root.installPrefixMode === "existing"
            model: root.prefixes.length > 0 ? root.prefixes : ["DEFAULT"]
            currentIndex: Math.max(0, model.indexOf(root.installPrefix))
            onActivated: (index) => root.installPrefix = model[index]
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.installStep !== "idle" || root.installMessage.length > 0
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    Layout.fillWidth: true
                    text: root.installMessage.length > 0
                        ? root.installMessage
                        : (root.installStep === "installing"
                            ? "Идёт установка. Заверши её в окне Wine."
                            : "Установка завершена.")
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    visible: root.installStep === "installing"
                    text: `${root.installElapsed} с`
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnLayer1Inactive
                }
            }

            StyledProgressBar {
                Layout.fillWidth: true
                visible: root.installPercent >= 0
                value: Math.max(0, Math.min(1, root.installPercent / 100))
            }

            StyledIndeterminateProgressBar {
                Layout.fillWidth: true
                visible: root.installPercent < 0 && root.installStep === "installing"
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: root.installLog.length > 0 ? 96 : 0
                visible: root.installLog.length > 0
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer0
                clip: true

                ScrollView {
                    anchors.fill: parent
                    anchors.margins: 6
                    clip: true

                    TextArea {
                        readOnly: true
                        text: root.installLog
                        wrapMode: TextEdit.NoWrap
                        color: Appearance.colors.colOnLayer0
                        font.family: "monospace"
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        background: null
                    }
                }
            }
        }

        WindowDialogButtonRow {
            DialogButton {
                buttonText: "Отмена"
                enabled: root.installStep === "idle"
                onClicked: root.closeInstallDialog()
            }
            Item { Layout.fillWidth: true }
            DialogButton {
                buttonText: root.installStep === "installing" ? "Установка…" : (root.installStep === "scanning" ? "Поиск…" : "Установить")
                enabled: root.installStep === "idle"
                    && root.portProtonReady
                    && root.installInstaller.trim().length > 0
                    && root.installName.trim().length > 0
                onClicked: root.startInstall()
            }
        }
    }

    WindowDialog {
        id: confirmDialog
        z: 11
        anchors.fill: parent
        show: root.showConfirm
        backgroundWidth: 420
        onDismiss: root.cancelConfirm()

        WindowDialogTitle {
            text: root.confirmTitle
        }
        WindowDialogSeparator {}
        StyledText {
            Layout.fillWidth: true
            text: root.confirmText
            wrapMode: Text.Wrap
            color: Appearance.colors.colOnLayer1
        }
        WindowDialogButtonRow {
            DialogButton {
                buttonText: "Отмена"
                onClicked: root.cancelConfirm()
            }
            Item { Layout.fillWidth: true }
            DialogButton {
                buttonText: "Продолжить"
                onClicked: root.confirmProceed()
            }
        }
    }
}
