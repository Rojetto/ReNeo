import core.sys.windows.windows;
import core.stdc.stdio;
import core.stdc.string;
import core.stdc.wchar_;

import reneo;
import mapping;
import composer;
import trayicon;
import std.path : dirName;
import std.file : thisExePath;
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

HMENU contextMenu;
HICON iconEnabled;
HICON iconDisabled;

const UINT ID_MYTRAYICON = 0x1000;
const UINT ID_TRAY_ACTIVATE_CONTEXTMENU = 0x1100;
const UINT ID_TRAY_RELOAD_CONTEXTMENU = 0x1101;
const UINT ID_TRAY_QUIT_CONTEXTMENU = 0x110F;
string disableAppMenuMsg = "ReNeo deaktivieren";
string enableAppMenuMsg  = "ReNeo aktivieren";
string reloadMenuMsg     = "Neu laden";
string quitMenuMsg       = "ReNeo beenden";

const APPNAME            = "ReNeo";
string executableDir;

TrayIcon trayIcon;

extern (Windows)
LRESULT LowLevelKeyboardProc(int nCode, WPARAM wParam, LPARAM lParam) nothrow {
    if (foregroundWindowChanged) {
        checkKeyboardLayout();
        foregroundWindowChanged = false;
    }

    if (bypassMode) {
        return CallNextHookEx(hHook, nCode, wParam, lParam);
    }

    auto msg_ptr = cast(LPKBDLLHOOKSTRUCT) lParam;
    auto msg_struct = *msg_ptr;

    bool eat = keyboardHook(wParam, msg_struct);

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

NeoLayout * getAppropriateNeoLayout() nothrow {
    HKL inputLocale = GetKeyboardLayout(GetWindowThreadProcessId(GetForegroundWindow(), NULL));
    
    wstring dllName = inputLocaleToDllName(inputLocale);

    for (int i = 0; i < layouts.length; i++) {
        if (layouts[i].dllName == dllName) {
            return &layouts[i];
        }
    }

    return null;
}

wstring inputLocaleToDllName(HKL inputLocale) nothrow {
    // Getting the layout name (which we can then look up in the registry) is a little tricky
    // https://stackoverflow.com/a/19321020/1610421
    ActivateKeyboardLayout(inputLocale, KLF_SETFORPROCESS);
    wchar[KL_NAMELENGTH] layoutName;
    GetKeyboardLayoutNameW(layoutName.ptr);

    wchar[256] regKey;
    wcscpy(regKey.ptr, r"SYSTEM\ControlSet001\Control\Keyboard Layouts\"w.ptr);
    wcscat(regKey.ptr, layoutName.ptr);

    wstring valueName = "Layout File"w;

    wchar[256] layoutFile;
    uint bufferSize = layoutFile.length;
    RegGetValueW(HKEY_LOCAL_MACHINE, regKey.ptr, valueName.ptr, RRF_RT_REG_SZ, NULL, layoutFile.ptr, &bufferSize);
    wchar[] dllName = layoutFile[0 .. wcslen(layoutFile.ptr)];
    return dllName.to!wstring;
}

void checkKeyboardLayout() nothrow {
    auto layout = getAppropriateNeoLayout();

    if (layout != null) {
        if (bypassMode) {
            debug_writeln("No bypassing keyboard input");
            bypassMode = false;
            previousNumlockState = getNumlockState();
        }

        if (setActiveLayout(layout)) {
            debug_writeln("Changing keyboard layout to ", layout.name);
        }
    } else {
        if (!bypassMode) {
            debug_writeln("Starting bypass mode");
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
        break;

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
            break;

            case ID_TRAY_RELOAD_CONTEXTMENU:
            debug_writeln("Re-initialize...");
            initialize();
            break;

            case ID_TRAY_QUIT_CONTEXTMENU:
            SendMessage(hwnd, WM_CLOSE, 0, 0);
            break;

            default: break;
        }
        break;

        default: break;
    }

    } catch (Throwable e) {
        // Doing nothing here. Might better be done in some methods in TrayIcon
    }

    return DefWindowProc(hwnd, msg, wParam, lParam);
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
        modifyMenuItemString(contextMenu, ID_TRAY_ACTIVATE_CONTEXTMENU, enableAppMenuMsg);
    } else {
        trayIcon.setIcon(iconEnabled);
        modifyMenuItemString(contextMenu, ID_TRAY_ACTIVATE_CONTEXTMENU, disableAppMenuMsg);
    }
}

void switchKeyboardHook() {
    if (!keyboardHookActive) {
        previousNumlockState = getNumlockState();

        HINSTANCE hInstance = GetModuleHandle(NULL);
        hHook = SetWindowsHookEx(WH_KEYBOARD_LL, &LowLevelKeyboardProc, hInstance, 0);
        debug_writeln("Keyboard hook active!");

        // Activating keyboard hook must start without bypass mode, so that checkKeyboardLayout() does not store
        // the already active Numlock state.
        bypassMode = false;
        checkKeyboardLayout();
    } else {
        UnhookWindowsHookEx(hHook);
        // Only reset Numlock state if we were active before
        if (!bypassMode) { setNumlockState(previousNumlockState); }
        debug_writeln("Keyboard hook inactive!");
    }

    keyboardHookActive = !keyboardHookActive;
}


extern (Windows)
void WinEventProc(HWINEVENTHOOK hWinEventHook, DWORD event, HWND hwnd, LONG idObject, LONG idChild, DWORD idEventThread, DWORD dwmsEventTime) nothrow @nogc {
    foregroundWindowChanged = true;
}

void initialize() {
    initKeysyms(executableDir);
    initCompose(executableDir);

    string configPath = buildPath(executableDir, "config.json");
    string configString = readText(configPath);
    auto configJson = parseJSON(configString);
    initLayouts(configJson["layouts"]);

    debug_writeln("Initialization complete!");
}

void main(string[] args) {
    debug_writeln("Starting ReNeo...");
    executableDir = dirName(thisExePath());

    initialize();

    keyboardHookActive = false;
    switchKeyboardHook();

    // We want to detect when the selected keyboard layout changes so that we can activate or deactivate ReNeo as necessary.
    // Listening to input locale events directly is difficult and not very robust. So we listen to the foreground window changes
    // (which also fire when the language bar is activated) and then recheck the keyboard layout on the next keypress.
    foregroundHook = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, NULL, &WinEventProc, 0, 0, WINEVENT_OUTOFCONTEXT);
    if (foregroundHook) {
        debug_writeln("Foreground window hook active!");
    } else {
        debug_writeln("Could not install foreground window hook!");
    }

    HWND hwnd;
    WNDCLASS wndclass;

    // The necessary actions for getting a handle without displaying an actual window
    wndclass.lpszClassName = "MyWindow";
    wndclass.lpfnWndProc   = &WndProc;
    RegisterClass(&wndclass);
    HINSTANCE hInstance = GetModuleHandle(NULL);
    hwnd = CreateWindowEx(0, wndclass.lpszClassName, "", WS_TILED | WS_SYSMENU, 0, 0, 50, 50, NULL, NULL, hInstance, NULL);

    // Names of icons are defined in icons.rc
    iconEnabled = LoadImage(hInstance, "trayenabled", IMAGE_ICON, 0, 0, LR_SHARED | LR_DEFAULTSIZE);
    iconDisabled = LoadImage(hInstance, "traydisabled", IMAGE_ICON, 0, 0, LR_SHARED | LR_DEFAULTSIZE);
    // Install icon in notification area, based on the hwnd
    trayIcon = new TrayIcon(hwnd, ID_MYTRAYICON, iconEnabled, APPNAME.to!(wchar[]));
    trayIcon.show();

    // Define context menu
    contextMenu = CreatePopupMenu();
    AppendMenu(contextMenu, MF_STRING, ID_TRAY_ACTIVATE_CONTEXTMENU, disableAppMenuMsg.toUTF16z);
    AppendMenu(contextMenu, MF_STRING, ID_TRAY_RELOAD_CONTEXTMENU, reloadMenuMsg.toUTF16z);
    AppendMenu(contextMenu, MF_SEPARATOR, 0, NULL);
    AppendMenu(contextMenu, MF_STRING, ID_TRAY_QUIT_CONTEXTMENU, quitMenuMsg.toUTF16z);
    SetMenuDefaultItem(contextMenu, ID_TRAY_ACTIVATE_CONTEXTMENU, 0);

    MSG msg;
    while(GetMessage(&msg, NULL, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessage(&msg);
    }

    if (keyboardHookActive) { switchKeyboardHook(); }
}
