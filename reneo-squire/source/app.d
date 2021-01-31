import std.stdio;
import std.utf;
import std.conv;
import std.format;

import core.runtime;
import core.sys.windows.windows;

import arsd.terminal;
import clipboard_windows;

import squire;
import mapping;
import composer;

HHOOK hHook;

extern (Windows)
LRESULT LowLevelKeyboardProc(int nCode, WPARAM wParam, LPARAM lParam) nothrow {
    auto msg_ptr = cast(LPKBDLLHOOKSTRUCT) lParam;
    auto msg_struct = *msg_ptr;

    bool eat = keyboardHook(wParam, msg_struct);

    if (eat) {
        // TODO: is this a sensible value?
        return -1;
    }

    return CallNextHookEx(hHook, nCode, wParam, lParam);
}

extern (Windows)
LRESULT WindowProc(HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam) nothrow {
    switch (uMsg) {
    case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    case WM_PAINT:
        PAINTSTRUCT ps;
        HDC hdc = BeginPaint(hwnd, &ps);

        FillRect(hdc, &ps.rcPaint, cast(HBRUSH) (COLOR_WINDOW+1));

        EndPaint(hwnd, &ps);
        return 0;
    case WM_KEYDOWN:
        printf("WM_KEYDOWN wParam %x lParam %x\n", wParam, lParam);
        break;
    case WM_KEYUP:
        printf("WM_KEYUP wParam %x lParam %x\n", wParam, lParam);
        break;
    case WM_CHAR:
        printf("WM_CHAR wParam %x lParam %x\n", wParam, lParam);
        break;
    case WM_UNICHAR:
        printf("WM_UNICHAR wParam %x lParam %x\n", wParam, lParam);
        break;
    default:
        break;
    }

    return DefWindowProc(hwnd, uMsg, wParam, lParam);
}

void main() {
	printf("Started\n");
    initKeysyms();
    initMapping();
    initCompose();

    bool squire_mode;

    if (squire_mode) {
        HINSTANCE hInstance = GetModuleHandle(NULL);
        hHook = SetWindowsHookEx(WH_KEYBOARD_LL, &LowLevelKeyboardProc, hInstance, 0);

        // Register the window class.
        auto classNameDString = "Sample Window Class";

        WNDCLASS wc = { };

        wc.lpfnWndProc   = &WindowProc;
        wc.hInstance     = hInstance;
        wc.lpszClassName = classNameDString.toUTF16z;

        RegisterClass(&wc);

        // Create the window.

        HWND hwnd = CreateWindowEx(
            0,                              // Optional window styles.
            classNameDString.toUTF16z,                     // Window class
            "Learn to Program Windows".toUTF16z,    // Window text
            WS_OVERLAPPEDWINDOW,            // Window style

            // Size and position
            CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT,

            NULL,       // Parent window    
            NULL,       // Menu
            hInstance,  // Instance handle
            NULL        // Additional application data
            );

        if (hwnd == NULL)
        {
            return;
        }

        ShowWindow(hwnd, SW_SHOW);
        
        MSG msg;
        while(GetMessage(&msg, NULL, 0, 0)) {
            TranslateMessage(&msg);
            DispatchMessage(&msg);
        }

        // TODO: release hook
    } else {
        while (true) {
            auto terminal = Terminal(ConsoleOutputType.linear);
	        string input = terminal.getline();
            wstring input_wstring = input.to!(wstring);
            wchar searchChar = input_wstring[0];
            
            string keysym_str;

            foreach (entry; keysymdefs.byKeyValue()) {
                if (entry.value.unicode_char == searchChar) {
                    keysym_str = entry.key;
                }
            }

            if (!keysym_str) {
                keysym_str = format("U%04X", searchChar);
            }

            string callStr = format("mCH(\"%s\", '%s')", keysym_str, searchChar);
            writeln(" => ", callStr);

            writeClipboard(callStr.to!(wstring));
        }
    }
}
