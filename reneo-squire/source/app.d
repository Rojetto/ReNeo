import std.stdio;
import std.utf;

import core.runtime;
import core.sys.windows.windows;

HHOOK hHook;

extern (Windows)
LRESULT LowLevelKeyboardProc(int nCode, WPARAM wParam, LPARAM lParam) nothrow {
    auto msg_ptr = cast(LPKBDLLHOOKSTRUCT) lParam;
    auto vk = msg_ptr.vkCode;
    switch(wParam) {
        case WM_KEYDOWN:
        //printf("Key down %x\n", vk);
        break;
        default:
        break;
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
}
