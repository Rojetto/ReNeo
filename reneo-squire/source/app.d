import std.stdio;
import std.utf;
import std.regex;
import std.conv;

import core.runtime;
import core.sys.windows.windows;

alias VK = WPARAM;

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

    this(uint keysym, VK vk_code) {
        this.keysym = keysym;
        this.keytype = NeoKeyType.VKEY;
        this.vk_code = vk_code;
    }

    this(uint keysym, wchar char_code) {
        this.keysym = keysym;
        this.keytype = NeoKeyType.CHAR;
        this.char_code = char_code;
    }
    
    this(string keysym_str, VK vk_code) {
        this.keysym = parseKeysym(keysym_str);
        this.keytype = NeoKeyType.VKEY;
        this.vk_code = vk_code;
    }

    this(string keysym_str, wchar char_code) {
        this.keysym = parseKeysym(keysym_str);
        this.keytype = NeoKeyType.CHAR;
        this.char_code = char_code;
    }
}

NeoKey[6][VK] mapping;

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
    return 0xffffffff;
}

void initMapping() {
    mapping[VK_OEM_PERIOD] = [NeoKey("period", VK_OEM_PERIOD), NeoKey("enfilledcircbullet", '•'),
                              NeoKey("apostrophe", '\''), NeoKey("KP_3", VK_NUMPAD3),
                              NeoKey("U03D1", 'ϑ'), NeoKey("U21A6", '↦')];
    mapping['S'] = [NeoKey("s", to!VK('S')), NeoKey("S", to!VK('S')),
                    NeoKey("question", '?'), NeoKey("questiondown", '¿'),
                    NeoKey("Greek_sigma", 'σ'), NeoKey("Greek_SIGMA", 'Σ')];
    mapping['E'] = [NeoKey("e", to!VK('E')), NeoKey("E", to!VK('E')),
                    NeoKey("braceright", '}'), NeoKey("Right", VK_RIGHT),
                    NeoKey("Greek_epsilon", 'ε'), NeoKey("U220323", '∃')];
    mapping[VK_OEM_1] = [NeoKey("dead_circumflex", '^'), NeoKey("dead_caron", 'ˇ'),
                         NeoKey("U21BB", '↻'), NeoKey("dead_abovedot", '˙'),
                         NeoKey("dead_hook", '˞'), NeoKey("dead_belowdot", '.')];
    mapping[VK_TAB] = [NeoKey("tab", VK_TAB), NeoKey("tab", VK_TAB),
                       NeoKey("Multi_key", '♫'), NeoKey("tab", VK_TAB),
                       NeoKey("VoidSymbol", 0xFF), NeoKey("VoidSymbol", 0xFF)];   
}

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
