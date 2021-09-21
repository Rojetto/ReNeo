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

import std.utf;
import std.string;
import std.conv;
import std.file;
import std.path;
import std.stdio;
import std.json;

HHOOK hHook;
HWINEVENTHOOK foregroundHook;

bool bypassMode;
bool foregroundWindowChanged;
bool keyboardHookActive;
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

string disableAppMenuMsg    = "Deaktivieren";
string enableAppMenuMsg     = "Aktivieren";
string reloadMenuMsg        = "Neu laden";
string layoutMenuMsg        = "Tastaturlayout";
string quitMenuMsg          = "Beenden";
string oskMenuMsg           = "Bildschirmtastatur";
string oneHandedModeMenuMsg = "Einhandmodus";

string oskMenuWithHotkeyMsg;  // strings are combined with loaded hotkey on initialization
string oneHandedModeMenuWithHotkeyMsg;
string disableAppMenuWithHotkeyMsg;
string enableAppMenuWithHotkeyMsg;

const APPNAME            = "ReNeo"w;
string executableDir;

TrayIcon trayIcon;

struct HotkeyConfig {
    uint modFlags;
    uint key;  // main key vk
}

extern (Windows)
LRESULT LowLevelKeyboardProc(int nCode, WPARAM wParam, LPARAM lParam) nothrow {
    if (foregroundWindowChanged) {
        checkKeyboardLayout();
        updateTrayTooltip();
        foregroundWindowChanged = false;
    }

    if (bypassMode) {
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
        if (!bypassMode && activeLayout) {
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
        if (bypassMode) {
            debugWriteln("No bypassing keyboard input");
            bypassMode = false;
            previousNumlockState = getNumlockState();
            resetHookStates();  // Reset potential locks when activating hook
        }

        if (setActiveLayout(layout)) {
            debugWriteln("Changing keyboard layout to ", layout.name);
        }
    } else {
        if (!bypassMode) {
            debugWriteln("Starting bypass mode");
            bypassMode = true;
            setNumlockState(previousNumlockState);
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
            switchKeyboardHook();
            updateContextMenu();
            updateTrayTooltip();
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
                updateTrayTooltip();
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
            switchKeyboardHook();
            updateContextMenu();
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
        modifyMenuItemString(contextMenu, ID_TRAY_ACTIVATE_CONTEXTMENU, enableAppMenuWithHotkeyMsg);
    } else {
        trayIcon.setIcon(iconEnabled);
        modifyMenuItemString(contextMenu, ID_TRAY_ACTIVATE_CONTEXTMENU, disableAppMenuWithHotkeyMsg);
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
    if (keyboardHookActive && !bypassMode) {
        layoutName = (standaloneModeActive ? ""w : "+"w) ~ activeLayout.name;
    }
    trayIcon.setTip((APPNAME ~ " (" ~ layoutName ~ ")").to!(wchar[]));
}

void switchKeyboardHook() {
    if (!keyboardHookActive) {
        previousNumlockState = getNumlockState();

        HINSTANCE hInstance = GetModuleHandle(NULL);
        hHook = SetWindowsHookEx(WH_KEYBOARD_LL, &LowLevelKeyboardProc, hInstance, 0);
        debugWriteln("Keyboard hook active!");

        // Activating keyboard hook must start without bypass mode, so that checkKeyboardLayout() does not store
        // the already active Numlock state.
        bypassMode = false;
        checkKeyboardLayout();
        resetHookStates();  // Reset potential locks when activating hook
    } else {
        UnhookWindowsHookEx(hHook);
        // Only reset Numlock state if we were active before
        if (!bypassMode) { setNumlockState(previousNumlockState); }
        debugWriteln("Keyboard hook inactive!");
    }

    keyboardHookActive = !keyboardHookActive;
}


extern (Windows)
void WinEventProc(HWINEVENTHOOK hWinEventHook, DWORD event, HWND hwnd, LONG idObject, LONG idChild, DWORD idEventThread, DWORD dwmsEventTime) nothrow @nogc {
    foregroundWindowChanged = true;
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
                throw new Exception("Nicht existierender Hotkey-Modifier '" ~ keyString ~ "'. Mögliche Werte sind Shift, Ctrl, Alt, Win.");
            }
            break;
        }
    }

    return config;
}

string hotkeyToString(HotkeyConfig hotkey) {
    string hotkeyString = "";

    if (hotkey.modFlags & core.sys.windows.winuser.MOD_WIN) {
        hotkeyString ~= "Win+";
    }
    if (hotkey.modFlags & core.sys.windows.winuser.MOD_CONTROL) {
        hotkeyString ~= "Strg+";
    }
    if (hotkey.modFlags & core.sys.windows.winuser.MOD_ALT) {
        hotkeyString ~= "Alt+";
    }
    if (hotkey.modFlags & core.sys.windows.winuser.MOD_SHIFT) {
        hotkeyString ~= "Shift+";
    }

    hotkeyString ~= hotkey.key.to!VKEY.to!string[3..$].capitalize;

    return hotkeyString;
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
                    if (value.type == JSONType.OBJECT && key in destination) {
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
            string hotkeyString = hotkeyToString(configHotkeyToggleActivation);
            disableAppMenuWithHotkeyMsg = disableAppMenuMsg ~ "\t" ~ hotkeyString;
            enableAppMenuWithHotkeyMsg = enableAppMenuMsg ~ "\t" ~ hotkeyString;
        }
        if (configJson["hotkeys"]["toggleOSK"].type == JSONType.STRING) {
            configHotkeyToggleOSK = parseHotkey(configJson["hotkeys"]["toggleOSK"].str);
            string hotkeyString = hotkeyToString(configHotkeyToggleOSK);
            oskMenuWithHotkeyMsg = oskMenuMsg ~ "\t" ~ hotkeyString;
        } else {
            oskMenuWithHotkeyMsg = oskMenuMsg ~ "\tMod3+F1";
        }
        if (configJson["hotkeys"]["toggleOneHandedMode"].type == JSONType.STRING) {
            configHotkeyToggleOneHandedMode = parseHotkey(configJson["hotkeys"]["toggleOneHandedMode"].str);
            string hotkeyString = hotkeyToString(configHotkeyToggleOneHandedMode);
            oneHandedModeMenuWithHotkeyMsg = oneHandedModeMenuMsg ~ "\t" ~ hotkeyString;
        } else {
            oneHandedModeMenuWithHotkeyMsg = oneHandedModeMenuMsg ~ "\tMod3+F10";
        }

        configOneHandedModeMirrorKey = parseScancode(configJson["oneHandedMode"]["mirrorKey"].str);
        foreach (string key, JSONValue value; configJson["oneHandedMode"]["mirrorMap"]) {
            configOneHandedModeMirrorMap[parseScancode(key)] = parseScancode(value.str);
        }
    } catch (Exception e) {
        string text = "Beim Starten von ReNeo ist ein Fehler aufgetreten:\n" ~ e.msg;
        MessageBox(hwnd, text.toUTF16z, "Fehler beim Initialisieren".toUTF16z, MB_OK | MB_ICONERROR);
        exit(0);
    }

    debugWriteln("Initialization complete!");
}

JSONValue parseJSONFile(string jsonFilename) {
    string jsonFilePath = buildPath(executableDir, jsonFilename);
    if (!exists(jsonFilePath))
        throw new Exception(jsonFilePath ~ " existiert nicht.");
    string jsonString = readText(jsonFilePath);
    try {
        return parseJSON(jsonString);
    } catch (Exception e) {
        throw new Exception("Fehler beim Parsen von " ~ jsonFilename ~ ".\n" ~ e.msg);
    }
}

void main(string[] args) {
    debugWriteln("Starting ReNeo...");
    version(FileLogging) {
        debugWriteln("WARNING: File logging enabled, make sure you know what you're doing!");
    }
    executableDir = dirName(thisExePath());

    initialize();

    // We want to detect when the selected keyboard layout changes so that we can activate or deactivate ReNeo as necessary.
    // Listening to input locale events directly is difficult and not very robust. So we listen to the foreground window changes
    // (which also fire when the language bar is activated) and then recheck the keyboard layout on the next keypress.
    foregroundHook = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, NULL, &WinEventProc, 0, 0, WINEVENT_OUTOFCONTEXT);
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
        AppendMenu(contextMenu, MF_POPUP, cast(UINT_PTR) layoutMenu, layoutMenuMsg.toUTF16z);
        AppendMenu(contextMenu, MF_SEPARATOR, 0, NULL);
    }
    AppendMenu(contextMenu, MF_STRING, ID_TRAY_OSK_CONTEXTMENU, oskMenuWithHotkeyMsg.toUTF16z);
    AppendMenu(contextMenu, MF_STRING, ID_TRAY_ONE_HANDED_MODE_CONTEXTMENU, oneHandedModeMenuWithHotkeyMsg.toUTF16z);
    AppendMenu(contextMenu, MF_STRING, ID_TRAY_RELOAD_CONTEXTMENU, reloadMenuMsg.toUTF16z);
    AppendMenu(contextMenu, MF_STRING, ID_TRAY_ACTIVATE_CONTEXTMENU, disableAppMenuWithHotkeyMsg.toUTF16z);
    AppendMenu(contextMenu, MF_SEPARATOR, 0, NULL);
    string versionMsg = "ReNeo %VERSION%";   // text is replaced by GitHub release action
    AppendMenu(contextMenu, MF_STRING, ID_TRAY_VERSION, versionMsg.toUTF16z);
    EnableMenuItem(contextMenu, ID_TRAY_VERSION, MF_BYCOMMAND | MF_GRAYED);
    AppendMenu(contextMenu, MF_STRING, ID_TRAY_QUIT_CONTEXTMENU, quitMenuMsg.toUTF16z);
    SetMenuDefaultItem(contextMenu, ID_TRAY_ACTIVATE_CONTEXTMENU, 0);

    keyboardHookActive = false;
    switchKeyboardHook();
    updateTrayTooltip();

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

    if (keyboardHookActive) { switchKeyboardHook(); }
}
