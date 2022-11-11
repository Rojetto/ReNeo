import core.sys.windows.windows;
import core.stdc.stdio;
import core.stdc.string;
import core.stdc.wchar_;
import core.stdc.stdlib : exit;

import reneo;
import mapping;
import composer;
import trayicon;
import osk;
import localization : initLocalization, appString, appStringwz, Language, AppString, hotkeyString;

import std.utf;
import std.string;
import std.conv;
import std.file;
import std.path;
import std.stdio;
import std.json;
import std.regex : matchFirst;

HHOOK hHook;
HWINEVENTHOOK foregroundHook;

// The following three flags contain the hook activation state.
// Any time any of them are changed, onHookStateUpdate is called!

// Is the keyboard hook registered and called? Corresponds to
// enable/disable function in tray menu, state shown via tray icon.
// This is *always set by the user*.
bool _keyboardHookActive;
@property bool keyboardHookActive() nothrow {
    return _keyboardHookActive;
}
@property void keyboardHookActive(bool val) nothrow {
    _keyboardHookActive = val;
    onHookStateUpdate();
}
// There are multiple ways the hook can still get bypassed. In that case,
// the tray icon is blue, but the tooltip shows "(inaktiv)". This
// *always happens automatically*.
// 1. Standalone mode is disabled and the native layout is not set
//    to a Neo layout
bool _bypassBecauseNoMatchingLayout;
@property bool bypassBecauseNoMatchingLayout() nothrow {
    return _bypassBecauseNoMatchingLayout;
}
@property void bypassBecauseNoMatchingLayout(bool val) nothrow {
    _bypassBecauseNoMatchingLayout = val;
    onHookStateUpdate();
}
// 2. The current window is on the configured blacklist
bool _bypassBecauseWindowInBlacklist;
@property bool bypassBecauseWindowInBlacklist() nothrow {
    return _bypassBecauseWindowInBlacklist;
}
@property void bypassBecauseWindowInBlacklist(bool val) nothrow {
    _bypassBecauseWindowInBlacklist = val;
    onHookStateUpdate();
}

@property bool resultingHookState() nothrow {
    return keyboardHookActive && !(bypassBecauseNoMatchingLayout || bypassBecauseWindowInBlacklist);
}

// Cache the last resulting hook state to detect changes
bool previousResultingHookState;

bool foregroundWindowChanged;
bool previousNumlockState;

bool oskOpen;

bool configStandaloneMode;
NeoLayout *configStandaloneLayout;
bool configAutoNumlock;
bool configFilterNeoModifiers;
HotkeyConfig configHotkeyToggleActivation;
HotkeyConfig configHotkeyToggleOSK;
HotkeyConfig configHotkeyToggleOneHandedMode;
Scancode configOneHandedModeMirrorKey;
Scancode[Scancode] configOneHandedModeMirrorMap;
BlacklistEntry[] configBlacklist;

// Default values, are overwritten if hotkeys are set in user config
string hotkeyToggleActivationStr;
string hotkeyToggleOSKStr = "Mod3+F1";
string hotkeyToggleOneHandedModeStr = "Mod3+F10";

HWND hwnd;

HMENU contextMenu;
HMENU layoutMenu;
HICON iconEnabled;
HICON iconDisabled;

// set in checkKeyboardLayout (if not null) and used when translating characters to native key combos
HKL lastInputLocale;

const MOD_NOREPEAT = 0x4000;

const UINT ID_MYTRAYICON = 0x1000;
const UINT ID_TRAY_ACTIVATE_CONTEXTMENU = 0x1100;
const UINT ID_TRAY_RELOAD_CONTEXTMENU = 0x1101;
const UINT ID_TRAY_OSK_CONTEXTMENU = 0x1102;
const UINT ID_TRAY_ONE_HANDED_MODE_CONTEXTMENU = 0x1103;
const UINT ID_TRAY_VERSION = 0x110E;
const UINT ID_TRAY_QUIT_CONTEXTMENU = 0x110F;
const UINT ID_LAYOUTMENU = 0x1200;

const UINT ID_HOTKEY_DEACTIVATE = 0x001;
const UINT ID_HOTKEY_OSK = 0x002;
const UINT ID_HOTKEY_ONE_HANDED_MODE = 0x003;

const UINT LAYOUTMENU_POSITION = 0;

const APPNAME            = "ReNeo"w;
string executableDir;

TrayIcon trayIcon;

struct HotkeyConfig {
    uint modFlags;
    uint key;  // main key vk
}

struct BlacklistEntry {
    string windowTitleRegex;
}

extern (Windows)
LRESULT LowLevelKeyboardProc(int nCode, WPARAM wParam, LPARAM lParam) nothrow {
    if (foregroundWindowChanged) {
        checkKeyboardLayout();
        foregroundWindowChanged = false;
    }

    if (!resultingHookState) {
        return CallNextHookEx(hHook, nCode, wParam, lParam);
    }

    auto msgPtr = cast(LPKBDLLHOOKSTRUCT) lParam;
    auto msgStruct = *msgPtr;

    bool eat = keyboardHook(wParam, msgStruct);

    /*
    If nCode is less than zero, the hook procedure must return the value returned by CallNextHookEx.

    If nCode is greater than or equal to zero, and the hook procedure did not process the message,
    it is highly recommended that you call CallNextHookEx and return the value it returns;
    otherwise, other applications that have installed WH_KEYBOARD_LL hooks will not receive hook
    notifications and may behave incorrectly as a result. If the hook procedure processed the message,
    it may return a nonzero value to prevent the system from passing the message to the rest of the
    hook chain or the target window procedure.
    */

    if (nCode < 0) {
        return CallNextHookEx(hHook, nCode, wParam, lParam);
    }

    if (eat) {
        return -1;
    }

    return CallNextHookEx(hHook, nCode, wParam, lParam);
}

wstring inputLocaleToDllName(HKL inputLocale) nothrow {
    // Getting the layout name (which we can then look up in the registry) is a little tricky
    // https://stackoverflow.com/a/19321020/1610421

    // Assume that inputLocale is not null!
    ActivateKeyboardLayout(inputLocale, KLF_SETFORPROCESS);
    wchar[KL_NAMELENGTH] layoutName;
    GetKeyboardLayoutNameW(layoutName.ptr);

    wchar[256] regKey;
    wcscpy(regKey.ptr, r"SYSTEM\ControlSet001\Control\Keyboard Layouts\"w.ptr);
    wcscat(regKey.ptr, layoutName.ptr);

    wstring valueName = "Layout File"w;

    wchar[256] layoutFile;
    uint bufferSize = layoutFile.length;

    if (RegGetValueW(HKEY_LOCAL_MACHINE, regKey.ptr, valueName.ptr, RRF_RT_REG_SZ, NULL, layoutFile.ptr, &bufferSize) == ERROR_SUCCESS) {
        // read layout file name, get characters until null terminator
        wchar[] dllName = layoutFile[0 .. wcslen(layoutFile.ptr)];
        return dllName.to!wstring;
    } else {
        // something went wrong, return null
        return null;
    }
}

void checkKeyboardLayout() nothrow {
    // Function is called when we suspect that the native Windows layout may have changed.
    // This happens
    // - on launch and reload
    // - when enabling the keyboard hook
    // - when manually selecting a standalone layout from the tray menu
    // - on the first key event after a foreground window change

    debugWriteln("Updating keyboard layout");
    // inputLocale may be null, e.g. in console windows!
    HKL inputLocale = GetKeyboardLayout(GetWindowThreadProcessId(GetForegroundWindow(), NULL));
    debugWriteln("Found input locale ", inputLocale);
    wstring dllName;
    if (inputLocale) {  // only look up the inputLocale if it's not null, otherwise dllName is empty
        dllName = inputLocaleToDllName(inputLocale);
    }
    debugWriteln("Input locale corresponds to dll file name '", dllName, "'");

    NeoLayout *layout;

    // try to find a layout in the config that matches the currently active keyboard layout DLL
    for (int i = 0; i < layouts.length; i++) {
        if (dllName && layouts[i].dllName == dllName) {
            layout = &layouts[i];
        }
    }

    if (inputLocale) {  // check if inputLocale is null
        // We got a valid inputLocale, cache it for further use
        lastInputLocale = inputLocale;

        if (layout == null) {
            if (configStandaloneMode) {
                // user enabled standalone mode in config, so we want to overtake and replace it with the selected Neo related layout
                standaloneModeActive = true;
                layout = configStandaloneLayout;
            } else {
                // user just wants to use whatever native layout they selected
                standaloneModeActive = false;
            }
        } else {
            // there is a native Neo related layout active, just operate in extension mode
            standaloneModeActive = false;
        }
    } else {
        // GetKeyboardLayout returns null in Windows terminal, see #11
        // In that case, we want to just keep the current layout settings if there are any, otherwise deactivate
        if (resultingHookState && activeLayout) {
            layout = activeLayout;
        } else {
            layout = null;  // "dllName" and therefore "layout" might be an actual (but wrong) layout if inputLocale == null
            standaloneModeActive = false;
        }
    }

    // Update tray menu: enable layout selection only if standalone mode is currently active
    if (configStandaloneMode) {
        if (standaloneModeActive) {
            EnableMenuItem(contextMenu, LAYOUTMENU_POSITION, MF_BYPOSITION | MF_ENABLED);
        } else {
            EnableMenuItem(contextMenu, LAYOUTMENU_POSITION, MF_BYPOSITION | MF_GRAYED);
        }
    }

    if (layout != null) {
        bypassBecauseNoMatchingLayout = false;

        if (setActiveLayout(layout)) {
            debugWriteln("Changing keyboard layout to ", layout.name);
        }
    } else {
        if (!bypassBecauseNoMatchingLayout) {
            debugWriteln("No matching layout found, bypassing keyboard hook");
            bypassBecauseNoMatchingLayout = true;
        }
    }
}


extern(Windows)
LRESULT WndProc(HWND hwnd, uint msg, WPARAM wParam, LPARAM lParam) nothrow {
    // Huge try block because WndProc is defined as "nothrow"
    try {

    switch (msg) {
        case WM_DESTROY:
        // Hide the tray icon and cleanup before closing the application
        trayIcon.hide();
        DestroyMenu(contextMenu);
        // Not necessary to unload icons loaded from file
        PostQuitMessage(0);
        return 0;

        case WM_TRAYICON:
        // From https://docs.microsoft.com/en-us/windows/win32/shell/taskbar#adding-modifying-and-deleting-icons-in-the-notification-area:
        // The wParam parameter of the message contains the identifier of the taskbar icon in which the event occurred.
        // The lParam parameter holds the mouse or keyboard message associated with the event.

        // We can omit the check for wParam as we use only a single notification icon
        switch(lParam) {
            case WM_LBUTTONDBLCLK:
            // Execute the same action as the context menu default item
            auto menuItem = GetMenuDefaultItem(contextMenu, 0, 0);
            SendMessage(hwnd, WM_COMMAND, menuItem, 0);
            break;

            case WM_CONTEXTMENU:
            trayIcon.showContextMenu(hwnd, contextMenu);
            break;

            default: break;
        }
        break;

        case WM_COMMAND:
        switch (wParam) {
            case ID_TRAY_ACTIVATE_CONTEXTMENU:
            toggleKeyboardHook();
            break;

            case ID_TRAY_OSK_CONTEXTMENU:
            toggleOSK();
            break;

            case ID_TRAY_ONE_HANDED_MODE_CONTEXTMENU:
            toggleOneHandedMode();
            break;

            case ID_TRAY_RELOAD_CONTEXTMENU:
            debugWriteln("Re-initialize...");
            initialize();
            updateOSK();
            break;

            case ID_TRAY_QUIT_CONTEXTMENU:
            PostMessage(hwnd, WM_CLOSE, 0, 0);  // cleanup will be done in WM_DESTROY handler
            break;

            default:
            uint newLayoutIdx = cast(uint)wParam - ID_LAYOUTMENU;
            // Did the user select a valid layout index?
            if (newLayoutIdx >= 0 && newLayoutIdx < layouts.length) {
                configStandaloneLayout = &layouts[newLayoutIdx];
                checkKeyboardLayout();
                CheckMenuRadioItem(layoutMenu, 0, GetMenuItemCount(layoutMenu) - 1, newLayoutIdx, MF_BYPOSITION);
                // Persist new selected layout
                auto configJson = parseJSONFile("config.json");
                configJson["standaloneLayout"] = layouts[newLayoutIdx].name;
                std.file.write(buildPath(executableDir, "config.json"), toJSON(configJson, true));
                updateOSK();
            }
            break;
        }
        break;

        case WM_HOTKEY:
        switch (wParam) {
            case ID_HOTKEY_DEACTIVATE:
            // De(activation) hotkey
            toggleKeyboardHook();
            break;
            case ID_HOTKEY_OSK:
            toggleOSK();
            break;
            case ID_HOTKEY_ONE_HANDED_MODE:
            toggleOneHandedMode();
            break;
            default: break;
        }
        break;

        default:  // Pass everything else to OSK
        return oskWndProc(hwnd, msg, wParam, lParam);
    }

    } catch (Exception e) {
        // Doing nothing here. Might better be done in some methods in TrayIcon
    }

    return DefWindowProc(hwnd, msg, wParam, lParam);
}

// Redraw OSK. WARNING: This function blocks and shouldn't be called from the key event handler
void updateOSK() nothrow {
    try {
        drawOsk(hwnd, activeLayout, activeLayer, capslock);
    } catch (Exception e) {}
}

// Schedule an OSK redraw on the message queue. Safe to call from the key event handler
void updateOSKAsync() nothrow {
    PostMessage(hwnd, WM_DRAWOSK, 0, 0);
}

void toggleOSK() nothrow {
    oskOpen = !oskOpen;
    if (oskOpen) {
        ShowWindow(hwnd, SW_SHOWNA);
        updateOSK();
    } else {
        ShowWindow(hwnd, SW_HIDE);
    }
    try {
        updateContextMenu();
    } catch (Exception e) {
    }
}

void toggleOneHandedMode() nothrow {
    oneHandedModeActive = !oneHandedModeActive;
    try {
        updateContextMenu();
    } catch (Exception e) {
    }
}

void modifyMenuItemString(HMENU hMenu, UINT id, string text) {
    // Changing a menu entry is cumbersome by hand (or foot)
    MENUITEMINFO mii;
    mii.cbSize = MENUITEMINFO.sizeof;
    mii.fMask = MIIM_STRING;
    mii.dwTypeData = toUTFz!(wchar*)(text);
    SetMenuItemInfo(hMenu, id, 0, &mii);
}

void updateContextMenu() {
    if (!keyboardHookActive) {
        trayIcon.setIcon(iconDisabled);
        modifyMenuItemString(contextMenu, ID_TRAY_ACTIVATE_CONTEXTMENU, appString(AppString.MENU_ENABLE, hotkeyToggleActivationStr));
    } else {
        trayIcon.setIcon(iconEnabled);
        modifyMenuItemString(contextMenu, ID_TRAY_ACTIVATE_CONTEXTMENU, appString(AppString.MENU_DISABLE, hotkeyToggleActivationStr));
    }

    if (oskOpen) {
        CheckMenuItem(contextMenu, ID_TRAY_OSK_CONTEXTMENU, MF_BYCOMMAND | MF_CHECKED);
    } else {
        CheckMenuItem(contextMenu, ID_TRAY_OSK_CONTEXTMENU, MF_BYCOMMAND | MF_UNCHECKED);
    }

    if (oneHandedModeActive) {
        CheckMenuItem(contextMenu, ID_TRAY_ONE_HANDED_MODE_CONTEXTMENU, MF_BYCOMMAND | MF_CHECKED);
    } else {
        CheckMenuItem(contextMenu, ID_TRAY_ONE_HANDED_MODE_CONTEXTMENU, MF_BYCOMMAND | MF_UNCHECKED);
    }
}

void updateTrayTooltip() nothrow {
    wstring layoutName = "inaktiv"w;
    if (resultingHookState && activeLayout) {
        layoutName = (standaloneModeActive ? ""w : "+"w) ~ activeLayout.name;
    }
    trayIcon.setTip((APPNAME ~ " (" ~ layoutName ~ ")").to!(wchar[]));
}

void onHookStateUpdate() nothrow {
    // Called every time any of the three hook state flags are set

    if (!previousResultingHookState && resultingHookState) {  // on activation
        debugWriteln("Keyboard hook active");
        // store original numlock state so that we can reset it later when deactivating
        previousNumlockState = getNumlockState();

        // We want Numlock to be always on, because some apps (built on WinUI, see #32) misinterpret VK_NUMPADx events if Numlock is disabled
        // However, this means we have to deal with fake shift events on Numpad layer 2 (#15)
        // On some notebooks with a native Numpad layer on the main keyboard we shouldn't do this, because they
        // then always get numbers instead of letters.
        if (configAutoNumlock) {
            setNumlockState(true);
        }

        // Deactivate Kana lock because Kana permanently activates layer 4 in kbdneo
        setKanaState(false);

        resetHookStates();  // Reset potential locks when activating hook
    } else if (previousResultingHookState && !resultingHookState) {  // on deactivation
        debugWriteln("Keyboard hook inactive");
        setNumlockState(previousNumlockState);
    }

    updateTrayTooltip();

    previousResultingHookState = resultingHookState;
}

void toggleKeyboardHook() {
    keyboardHookActive = !keyboardHookActive;

    if (keyboardHookActive) {  // on activation
        HINSTANCE hInstance = GetModuleHandle(NULL);
        hHook = SetWindowsHookEx(WH_KEYBOARD_LL, &LowLevelKeyboardProc, hInstance, 0);
        debugWriteln("Keyboard hook registered!");

        checkKeyboardLayout();
    } else {  // on deactivation
        UnhookWindowsHookEx(hHook);
        // Only reset Numlock state if we were active before
        debugWriteln("Keyboard hook unregistered!");
    }

    updateContextMenu();
}


extern (Windows)
void WinEventProc(HWINEVENTHOOK hWinEventHook, DWORD event, HWND hwnd, LONG idObject, LONG idChild, DWORD idEventThread, DWORD dwmsEventTime) nothrow {
    foregroundWindowChanged = true;
    wchar[256] titleBuffer;
    uint titleLen = GetWindowTextW(hwnd, titleBuffer.ptr, 256);
    const auto windowTitle = titleBuffer[0..titleLen].toUTF8;
    debugWriteln("Changed to window with title '", windowTitle, "'");
    try {
        bool windowInBlacklist;

        foreach (blacklistEntry; configBlacklist) {
            if (matchFirst(windowTitle, blacklistEntry.windowTitleRegex)) {
                windowInBlacklist = true;
                break;
            }
        }

        if (windowInBlacklist) {
            debugWriteln("Current window is in blacklist");
        }
        bypassBecauseWindowInBlacklist = windowInBlacklist;
    } catch(Exception e) {}
}

HotkeyConfig parseHotkey(string hotkeyString) {
    HotkeyConfig config;
    config.modFlags = MOD_NOREPEAT;

    auto keyStrings = hotkeyString.split("+");

    foreach (i, keyString; keyStrings) {
        string normalizedKey = keyString.strip.toUpper;

        switch (normalizedKey) {
            case "SHIFT": config.modFlags |= core.sys.windows.winuser.MOD_SHIFT; break;
            case "CTRL": config.modFlags |= core.sys.windows.winuser.MOD_CONTROL; break;
            case "ALT": config.modFlags |= core.sys.windows.winuser.MOD_ALT; break;
            case "WIN": config.modFlags |= core.sys.windows.winuser.MOD_WIN; break;
            default:
            if (i == keyStrings.length - 1) {
                config.key = ("VK_" ~ normalizedKey).to!VKEY;
            } else {
                throw new Exception(appString(AppString.ERROR_INVALID_HOTKEY_MODIFIER, keyString));
            }
            break;
        }
    }

    return config;
}

void initialize() {
    try {
        initKeysyms(executableDir);
        initCompose(executableDir);

        // Load default config (shipped with the program) as a base
        auto configJson = parseJSONFile("config.default.json");
        // Load user config if it exists
        if (exists(buildPath(executableDir, "config.json"))) {
            auto userConfigJson = parseJSONFile("config.json");

            // Overwrite values from default config with user config settings
            void copyJsonObjectOverOther(ref JSONValue source, ref JSONValue destination) {
                foreach (string key, JSONValue value; source) {
                    // The "mirrorMap" thing is a hack to not fill the user config.json with mirror map
                    // entries for scancodes that they have removed but that exist in config.default.json
                    if (value.type == JSONType.OBJECT && key in destination && key != "mirrorMap") {
                        copyJsonObjectOverOther(value, destination[key]);
                    } else {
                        destination[key] = value;
                    }
                }
            }

            copyJsonObjectOverOther(userConfigJson, configJson);
        }

        // Write combined config (default values + user settings) to user config file
        std.file.write(buildPath(executableDir, "config.json"), toJSON(configJson, true));

        // First of all, set the langage so that subsequent stuff is localized correctly
        initLocalization(configJson["language"].str.toUpper.to!Language);


        auto layoutsJson = parseJSONFile("layouts.json");
        initLayouts(layoutsJson["layouts"]);

        initOsk(configJson["osk"]);

        // Initialize layout menu
        layoutMenu = CreatePopupMenu();
        for (int i = 0; i < layouts.length; i++) {
            AppendMenu(layoutMenu, MF_STRING, ID_LAYOUTMENU + i, layouts[i].name.toUTF16z);
        }

        configStandaloneMode = configJson["standaloneMode"].boolean;
        if (configStandaloneMode) {
            wstring standaloneLayoutName = configJson["standaloneLayout"].str.to!wstring;
            for (int i = 0; i < layouts.length; i++) {
                if (layouts[i].name == standaloneLayoutName) {
                    configStandaloneLayout = &layouts[i];
                    // Select the current layout (only visible if standalone mode is active)
                    CheckMenuRadioItem(layoutMenu, 0, GetMenuItemCount(layoutMenu) - 1, i, MF_BYPOSITION);
                    break;
                }
            }

            if (configStandaloneLayout == null) {
                debugWriteln("Standalone layout '", standaloneLayoutName, "' not found!");
            }
        }

        configAutoNumlock = configJson["autoNumlock"].boolean;
        configFilterNeoModifiers = configJson["filterNeoModifiers"].boolean;

        // Parse hotkeys (might be null -> user doesn't want to use hotkey)
        if (configJson["hotkeys"]["toggleActivation"].type == JSONType.STRING) {
            configHotkeyToggleActivation = parseHotkey(configJson["hotkeys"]["toggleActivation"].str);
            hotkeyToggleActivationStr = hotkeyString(configHotkeyToggleActivation);
        }
        if (configJson["hotkeys"]["toggleOSK"].type == JSONType.STRING) {
            configHotkeyToggleOSK = parseHotkey(configJson["hotkeys"]["toggleOSK"].str);
            hotkeyToggleOSKStr = hotkeyString(configHotkeyToggleOSK);
        }
        if (configJson["hotkeys"]["toggleOneHandedMode"].type == JSONType.STRING) {
            configHotkeyToggleOneHandedMode = parseHotkey(configJson["hotkeys"]["toggleOneHandedMode"].str);
            hotkeyToggleOneHandedModeStr = hotkeyString(configHotkeyToggleOneHandedMode);
        }

        configOneHandedModeMirrorKey = parseScancode(configJson["oneHandedMode"]["mirrorKey"].str);
        foreach (string key, JSONValue value; configJson["oneHandedMode"]["mirrorMap"]) {
            configOneHandedModeMirrorMap[parseScancode(key)] = parseScancode(value.str);
        }

        configBlacklist = [];
        foreach (blacklistEntryJson; configJson["blacklist"].array) {
            BlacklistEntry blacklistEntry;
            if (!("windowTitle" in blacklistEntryJson)) {
                throw new Exception(appString(AppString.ERROR_BLACKLIST_MUST_CONTAIN_WINDOW_TITLE));
            }
            blacklistEntry.windowTitleRegex = blacklistEntryJson["windowTitle"].str;
            configBlacklist ~= blacklistEntry;
        }
    } catch (Exception e) {
        MessageBox(hwnd, appStringwz(AppString.ERROR_ERROR_OCCURRED_WHILE_STARTING, e.msg), appStringwz(AppString.ERROR_WHILE_INITIALIZING), MB_OK | MB_ICONERROR);
        exit(0);
    }

    debugWriteln("Initialization complete!");
}

JSONValue parseJSONFile(string jsonFilename) {
    string jsonFilePath = buildPath(executableDir, jsonFilename);
    if (!exists(jsonFilePath))
        throw new Exception(appString(AppString.ERROR_PATH_DOES_NOT_EXIST, jsonFilePath));
    string jsonString = readText(jsonFilePath);
    try {
        return parseJSON(jsonString);
    } catch (Exception e) {
        throw new Exception(appString(AppString.ERROR_WHILE_PARSING, jsonFilename, e.msg));
    }
}

void main(string[] args) {
    debug {
        const auto codePage = CP_UTF8;
        if (!SetConsoleCP(codePage))
            debugWriteln("WARNING: Could not set input CP to UTF-8. This probably doesn’t matter.");
        if (!SetConsoleOutputCP(codePage))
            debugWriteln("WARNING: Could not set output CP to UTF-8. Some characters may be displayed wrongly.");
    }

    debugWriteln("Starting ReNeo...");
    version(FileLogging) {
        debugWriteln("WARNING: File logging enabled, make sure you know what you're doing!");
    }
    executableDir = dirName(thisExePath());

    initialize();

    // We want to detect when the selected keyboard layout changes so that we can activate or deactivate ReNeo as necessary.
    // Listening to input locale events directly is difficult and not very robust. So we listen to the foreground window changes
    // (which also fire when the language bar is activated) and then recheck the keyboard layout on the next keypress.
    // For some reason (probably by mistake) WINEVENTPROCs must be @nogc. That's annoying, so we just cast our function pointer
    // and use the GC anyway.
    foregroundHook = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, NULL, cast(WINEVENTPROC) &WinEventProc, 0, 0, WINEVENT_OUTOFCONTEXT);
    if (foregroundHook) {
        debugWriteln("Foreground window hook active!");
    } else {
        debugWriteln("Could not install foreground window hook!");
    }

    // Create window for on-screen keyboard
    WNDCLASS wndclass;
    wndclass.lpszClassName = APPNAME.toUTF16z;
    wndclass.lpfnWndProc = &WndProc;
    RegisterClass(&wndclass);
    HINSTANCE hInstance = GetModuleHandle(NULL);
    hwnd = CreateWindowEx(WS_EX_TOPMOST | WS_EX_LAYERED | WS_EX_TOOLWINDOW, wndclass.lpszClassName, APPNAME.toUTF16z, WS_POPUP, CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT, NULL, NULL, hInstance, NULL);

    // Move and scale window to center of its current monitor
    centerOskOnScreen(hwnd);

    // Names of icons are defined in icons.rc
    iconEnabled = LoadImage(hInstance, "trayenabled", IMAGE_ICON, 0, 0, LR_SHARED | LR_DEFAULTSIZE);
    iconDisabled = LoadImage(hInstance, "traydisabled", IMAGE_ICON, 0, 0, LR_SHARED | LR_DEFAULTSIZE);

    SetClassLongPtr(hwnd, GCLP_HICON, cast(LONG_PTR) iconEnabled);

    // Install icon in notification area, based on the hwnd
    trayIcon = new TrayIcon(hwnd, ID_MYTRAYICON, iconEnabled, APPNAME.to!(wchar[]));
    trayIcon.show();

    // Define context menu
    contextMenu = CreatePopupMenu();
    if (configStandaloneMode) {
        AppendMenu(contextMenu, MF_POPUP, cast(UINT_PTR) layoutMenu, appStringwz(AppString.MENU_CHOOSE_LAYOUT));
        AppendMenu(contextMenu, MF_SEPARATOR, 0, NULL);
    }
    AppendMenu(contextMenu, MF_STRING, ID_TRAY_OSK_CONTEXTMENU, appStringwz(AppString.MENU_OSK, hotkeyToggleOSKStr));
    AppendMenu(contextMenu, MF_STRING, ID_TRAY_ONE_HANDED_MODE_CONTEXTMENU, appStringwz(AppString.MENU_ONE_HANDED_MODE, hotkeyToggleOneHandedModeStr));
    AppendMenu(contextMenu, MF_STRING, ID_TRAY_RELOAD_CONTEXTMENU, appStringwz(AppString.MENU_RELOAD));
    AppendMenu(contextMenu, MF_STRING, ID_TRAY_ACTIVATE_CONTEXTMENU, appStringwz(AppString.MENU_DISABLE, hotkeyToggleActivationStr));
    AppendMenu(contextMenu, MF_SEPARATOR, 0, NULL);
    string versionMsg = "ReNeo %VERSION%";   // text is replaced by GitHub release action
    AppendMenu(contextMenu, MF_STRING, ID_TRAY_VERSION, versionMsg.toUTF16z);
    EnableMenuItem(contextMenu, ID_TRAY_VERSION, MF_BYCOMMAND | MF_GRAYED);
    AppendMenu(contextMenu, MF_STRING, ID_TRAY_QUIT_CONTEXTMENU, appStringwz(AppString.MENU_QUIT));
    SetMenuDefaultItem(contextMenu, ID_TRAY_ACTIVATE_CONTEXTMENU, 0);

    keyboardHookActive = false;
    toggleKeyboardHook();

    // Register global (de)activation hotkey
    if (configHotkeyToggleActivation.key)
        RegisterHotKey(hwnd, ID_HOTKEY_DEACTIVATE, configHotkeyToggleActivation.modFlags, configHotkeyToggleActivation.key);
    // Register alternate OSK hotkey (M3+F1 always works)
    if (configHotkeyToggleOSK.key)
        RegisterHotKey(hwnd, ID_HOTKEY_OSK, configHotkeyToggleOSK.modFlags, configHotkeyToggleOSK.key);
    // Register alternate one handed mode hotkey (M3+F10 always works)
    if (configHotkeyToggleOneHandedMode.key)
        RegisterHotKey(hwnd, ID_HOTKEY_ONE_HANDED_MODE, configHotkeyToggleOneHandedMode.modFlags, configHotkeyToggleOneHandedMode.key);

    MSG msg;
    while(GetMessage(&msg, NULL, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessage(&msg);
    }

    UnregisterHotKey(hwnd, ID_HOTKEY_ONE_HANDED_MODE);
    UnregisterHotKey(hwnd, ID_HOTKEY_OSK);
    UnregisterHotKey(hwnd, ID_HOTKEY_DEACTIVATE);

    if (keyboardHookActive) { toggleKeyboardHook(); }
}
