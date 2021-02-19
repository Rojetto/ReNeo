import core.sys.windows.windows;
import core.stdc.stdio;
import core.stdc.wchar_;

import reneo;
import mapping;
import composer;
import std.path;
import std.utf;
import std.string;
import std.conv;

HHOOK hHook;
HWINEVENTHOOK foregroundHook;

bool keyboardHookActive;
bool foregroundWindowChanged;

extern (Windows)
LRESULT LowLevelKeyboardProc(int nCode, WPARAM wParam, LPARAM lParam) nothrow {
    if (foregroundWindowChanged) {
        checkKeyboardLayout();
        foregroundWindowChanged = false;
    }

    if (!keyboardHookActive) {
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

int getNeoLayoutName() nothrow @nogc {
    HKL inputLocale = GetKeyboardLayout(GetWindowThreadProcessId(GetForegroundWindow(), NULL));
    
    return inputLocaleToLayoutName(inputLocale);
}

int inputLocaleToLayoutName(HKL inputLocale) nothrow @nogc {
    // because of @nogc we can't use most of the nice phobos string functions here :(
    // Getting the layout name (which we can then look up in the registry) is a little tricky
    // https://stackoverflow.com/a/19321020/1610421
    ActivateKeyboardLayout(inputLocale, KLF_SETFORPROCESS);
    wchar[KL_NAMELENGTH] layoutName;
    GetKeyboardLayoutNameW(layoutName.ptr);

    wchar[256] regKey;
    wcscpy(regKey.ptr, r"SYSTEM\ControlSet001\Control\Keyboard Layouts\"w.ptr);
    wcscat(regKey.ptr, layoutName.ptr);

    wstring valueName = "Layout File\0"w;

    wchar[256] layoutFile;
    uint bufferSize = layoutFile.length;
    auto readResult = RegGetValueW(HKEY_LOCAL_MACHINE, regKey.ptr, valueName.ptr, RRF_RT_REG_SZ, NULL, layoutFile.ptr, &bufferSize);
    if (readResult != ERROR_SUCCESS) {
        debug_writeln("Could not read active keyboard layout DLL from registry");
        // If the user is running this script they probably also mainly use Neo so we'd rather have the app running.
        return true;
    }

    if (wcscmp(layoutFile.ptr, "kbdneo2.dll"w.ptr) == 0) {
        return LayoutName.NEO;
    } else if (wcscmp(layoutFile.ptr, "kbdbone.dll"w.ptr) == 0) {
        return LayoutName.BONE;
    } else if (wcscmp(layoutFile.ptr, "kbdgr2.dll"w.ptr) == 0) {
        return LayoutName.NEOQWERTZ;
    }

    return -1;
}

void checkKeyboardLayout() nothrow @nogc {
    int layoutName = getNeoLayoutName();

    if (layoutName >= 0) {
        if (!keyboardHookActive) {
            debug_writeln("Activating keyboard hook");
        }

        keyboardHookActive = true;
        if (setActiveLayout(cast(LayoutName) layoutName)) {
            debug_writeln("Changing keyboard layout to ", cast(LayoutName) layoutName);
        }
    } else {
        if (keyboardHookActive) {
            debug_writeln("Deactivating keyboard hook");
        }

        keyboardHookActive = false;
    }
}

extern (Windows)
void WinEventProc(HWINEVENTHOOK hWinEventHook, DWORD event, HWND hwnd, LONG idObject, LONG idChild, DWORD idEventThread, DWORD dwmsEventTime) nothrow @nogc {
    foregroundWindowChanged = true;
}

void main(string[] args) {
    debug_writeln("Starting ReNeo squire...");
    auto exeDir = dirName(absolutePath(buildNormalizedPath(args[0])));
    debug_writeln("EXE located in ", exeDir);
    initKeysyms(exeDir);
    initMapping();
    initCompose(exeDir);
    debug_writeln("Initialization complete!");

    checkKeyboardLayout();

    HINSTANCE hInstance = GetModuleHandle(NULL);
    hHook = SetWindowsHookEx(WH_KEYBOARD_LL, &LowLevelKeyboardProc, hInstance, 0);
    debug_writeln("Keyboard hook active!");

    // We want to detect when the selected keyboard layout changes so that we can activate or deactivate ReNeo as necessary.
    // Listening to input locale events directly is difficult and not very robust. So we listen to the foreground window changes
    // (which also fire when the language bar is activated) and then recheck the keyboard layout on the next keypress.
    foregroundHook = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, NULL, &WinEventProc, 0, 0, WINEVENT_OUTOFCONTEXT);
    if (foregroundHook) {
        debug_writeln("Foreground window hook active!");
    } else {
        debug_writeln("Could not install foreground window hook!");
    }

    MSG msg;
    while(GetMessage(&msg, NULL, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessage(&msg);
        debug_writeln("Message loop");
    }

    UnhookWindowsHookEx(hHook);
}
