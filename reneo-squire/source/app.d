import std.stdio;
import std.utf;
import std.regex;
import std.conv;

import core.runtime;
import core.sys.windows.windows;

alias VK = DWORD;

enum NeoKeyType {
    VKEY,
    CHAR
}

struct NeoKey {
    uint keysym;
    NeoKeyType keytype;
    union {
        VK vk_code;
        wchar char_code;
    }
}

NeoKey mapVK(string keysym_str, VK vk) {
    NeoKey nk = { keysym: parseKeysym(keysym_str), keytype: NeoKeyType.VKEY, vk_code: vk };
    return nk;
}

NeoKey mapChar(string keysym_str, wchar char_code) {
    NeoKey nk = { keysym: parseKeysym(keysym_str), keytype: NeoKeyType.CHAR, char_code: char_code };
    return nk;
}


NeoKey[6][VK] mapping;
NeoKey VOID_KEY;

struct KeySymEntry {
    uint key_code;
    wchar unicode_char;
}

KeySymEntry[string] keysymdefs;

void initKeysyms() {
    // group 1: name, group 2: hex, group 3: unicode codepoint
    auto unicode_pattern = r"^\#define XK_([a-zA-Z_0-9]+)\s+0x([0-9a-f]+)\s*\/\* U\+([0-9A-F]{4,6}) (.*) \*\/\s*$";
    auto unicode_pattern_with_parens = r"^\#define XK_([a-zA-Z_0-9]+)\s+0x([0-9a-f]+)\s*\/\*\(U\+([0-9A-F]{4,6}) (.*)\)\*\/\s*$";
    // group 1: name, group 2: hex, group 3 and 4: comment stuff
    auto no_unicode_pattern = r"^\#define XK_([a-zA-Z_0-9]+)\s+0x([0-9a-f]+)\s*(\/\*\s*(.*)\s*\*\/)?\s*$";

    File f = File("keysymdef.h", "r");
	while(!f.eof()) {
		string l = f.readln();
		if (auto m = matchFirst(l, unicode_pattern)) {
            string keysym_name = m[1];
            uint key_code = to!uint(m[2], 16);
            wchar unicode_char = to!wchar(to!ushort(m[3], 16));
            keysymdefs[keysym_name] = KeySymEntry(key_code, unicode_char);
        } else if (auto m = matchFirst(l, unicode_pattern_with_parens)) {
            string keysym_name = m[1];
            uint key_code = to!uint(m[2], 16);
            wchar unicode_char = to!wchar(to!ushort(m[3], 16));
            keysymdefs[keysym_name] = KeySymEntry(key_code, unicode_char);
        } else if (auto m = matchFirst(l, no_unicode_pattern)) {
            string keysym_name = m[1];
            uint key_code = to!uint(m[2], 16);
            keysymdefs[keysym_name] = KeySymEntry(key_code);
        }
	}
}

uint parseKeysym(string keysym) {
    if (keysym in keysymdefs) {
        return keysymdefs[keysym].key_code;
    } else if (auto m = matchFirst(keysym, r"^U([0-9a-fA-F]+)$")) {
        wchar unicode_char = to!wchar(to!ushort(m[1], 16));
        foreach (KeySymEntry entry; keysymdefs.byValue()) {
            if (entry.unicode_char == unicode_char) {
                return entry.key_code;
            }
        }

        return to!uint(unicode_char) + 0x01000000;
    }

    writeln("Keysym ", keysym, " not found.");
    return 0xffffff;
}

void initMapping() {
    VOID_KEY = mapVK("VoidSymbol", 0xFF);

    mapping[VK_OEM_PERIOD] = [mapVK("period", VK_OEM_PERIOD), mapChar("enfilledcircbullet", '•'),
                              mapChar("apostrophe", '\''), mapVK("KP_3", VK_NUMPAD3),
                              mapChar("U03D1", 'ϑ'), mapChar("U21A6", '↦')];
    mapping['S'] = [mapVK("s", 'S'), mapVK("S", 'S'),
                    mapChar("question", '?'), mapChar("questiondown", '¿'),
                    mapChar("Greek_sigma", 'σ'), mapChar("Greek_SIGMA", 'Σ')];
    mapping['E'] = [mapVK("e", 'E'), mapVK("E", 'E'),
                    mapChar("braceright", '}'), mapVK("Right", VK_RIGHT),
                    mapChar("Greek_epsilon", 'ε'), mapChar("U2203", '∃')];
    mapping[VK_OEM_1] = [mapChar("dead_circumflex", '^'), mapChar("dead_caron", 'ˇ'),
                         mapChar("U21BB", '↻'), mapChar("dead_abovedot", '˙'),
                         mapChar("dead_hook", '˞'), mapChar("dead_belowdot", '.')];
    mapping[VK_TAB] = [mapVK("Tab", VK_TAB), mapVK("Tab", VK_TAB),
                       mapChar("Multi_key", '♫'), mapVK("Tab", VK_TAB),
                       mapVK("VoidSymbol", 0xFF), mapVK("VoidSymbol", 0xFF)];   
}

bool isKeyDown(int vk) nothrow {
    return cast(bool)((GetAsyncKeyState(vk) & 0b1000_0000_0000_0000) >> 15);
}

void sendVK(int vk, bool down) nothrow {
    INPUT input_struct;
    input_struct.type = INPUT_KEYBOARD;
    input_struct.ki.wVk = cast(ushort)vk;
    input_struct.ki.wScan = 0;
    if (down) {
        input_struct.ki.dwFlags = 0x0000;
    } else {
        input_struct.ki.dwFlags = KEYEVENTF_KEYUP;
    }

    SendInput(1, &input_struct, INPUT.sizeof);
}

void sendUTF16(wchar unicode_char, bool down) nothrow {
    INPUT input_struct;
    input_struct.type = INPUT_KEYBOARD;
    input_struct.ki.wVk = 0;
    input_struct.ki.wScan = unicode_char;
    if (down) {
        input_struct.ki.dwFlags = KEYEVENTF_UNICODE;
    } else {
        input_struct.ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP;
    }

    SendInput(1, &input_struct, INPUT.sizeof);
}

void sendNeoKey(NeoKey nk, bool down) nothrow {
    if (nk.keysym == 0xffffff) {
        return;
    }

    if (nk.keytype == NeoKeyType.VKEY) {
        sendVK(nk.vk_code, down);
    } else {
        sendUTF16(nk.char_code, down);
    }
}

NeoKey mapToNeo(VK vk, uint layer) nothrow {
    if (vk in mapping) {
        return mapping[vk][layer - 1];
    }

    return VOID_KEY;
}

HHOOK hHook;

bool leftShiftDown;
bool rightShiftDown;
bool leftMod3Down;
bool rightMod3Down;
bool leftMod4Down;
bool rightMod4Down;

uint getLayer() nothrow {
    bool shiftDown = leftShiftDown || rightShiftDown;
    bool mod3Down = leftMod3Down || rightMod3Down;
    bool mod4Down = leftMod4Down || rightMod4Down;

    uint layer = 1;

    if (mod3Down && mod4Down) {
        layer = 6;
    } else if (shiftDown && mod3Down) {
        layer = 5;
    }  else if (mod4Down) {
        layer = 4;
    }  else if (mod3Down) {
        layer = 3;
    }  else if (shiftDown) {
        layer = 2;
    }

    return layer;
}

extern (Windows)
LRESULT LowLevelKeyboardProc(int nCode, WPARAM wParam, LPARAM lParam) nothrow {
    auto msg_ptr = cast(LPKBDLLHOOKSTRUCT) lParam;
    auto vk = msg_ptr.vkCode;
    auto scan = msg_ptr.scanCode;

    bool eat = false;

    switch(wParam) {
        case WM_KEYDOWN:
        if (vk == VK_LSHIFT) {
            leftShiftDown = true;
        } else if (vk == VK_RSHIFT) {
            rightShiftDown = true;
        } else if (vk == 0x8A) {
            leftMod3Down = true;
        } else if (vk == 0x8B) {
            rightMod3Down = true;
        } else if (vk == 0x8C) {
            leftMod4Down = true;
        } else if (vk == 0x8D) {
            rightMod4Down = true;
        }

        uint layer = getLayer();

        if (vk != VK_PACKET && scan != 0) {
            NeoKey nk = mapToNeo(vk, layer);
            //printf("Key down %x, layer %d, mapped to keysym %x\n", vk, layer, nk.keysym);

            if (layer >= 3) {
                eat = true;
                sendNeoKey(nk, true);
            }
        }
        break;

        case WM_KEYUP:
        if (vk == VK_LSHIFT) {
            leftShiftDown = false;
        } else if (vk == VK_RSHIFT) {
            rightShiftDown = false;
        } else if (vk == 0x8A) {
            leftMod3Down = false;
        } else if (vk == 0x8B) {
            rightMod3Down = false;
        } else if (vk == 0x8C) {
            leftMod4Down = false;
        } else if (vk == 0x8D) {
            rightMod4Down = false;
        }
        break;
        default:
        break;
    }

    if (eat) {
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
