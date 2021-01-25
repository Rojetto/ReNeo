import std.stdio;
import core.runtime;
import core.sys.windows.windows;

HHOOK hHook;

extern (Windows)
LRESULT LowLevelKeyboardProc(int nCode, WPARAM wParam, LPARAM lParam) nothrow {
    auto msg_ptr = cast(LPKBDLLHOOKSTRUCT) lParam;
    auto vk = msg_ptr.vkCode;
    switch(wParam) {
        case WM_KEYDOWN:
        printf("Key down %x\n", vk);
        break;
        default:
        break;
    }
    return CallNextHookEx(hHook, nCode, wParam, lParam);
}

void main() {
	printf("Started\n");
    HINSTANCE hInstance = GetModuleHandle(NULL);
    hHook = SetWindowsHookEx(WH_KEYBOARD_LL, &LowLevelKeyboardProc, hInstance, 0);
    MSG msg;
    while(GetMessage(&msg, NULL, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessage(&msg);
    }
}
