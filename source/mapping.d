module mapping;

import core.sys.windows.windows;

import std.conv;
import std.json;
import std.algorithm;
import std.array;

import reneo;

const uint KEYSYM_VOID = 0xFFFFFF;
const NeoKey VOID_KEY = NeoKey(KEYSYM_VOID, NeoKeyType.VKEY, VKEY.VK_VOID);

NeoLayout[] layouts;

enum VKEY {
    VK_LBUTTON = 0x01,
    VK_RBUTTON = 0x02,
    VK_CANCEL = 0x03,
    VK_MBUTTON = 0x04,
    VK_XBUTTON1 = 0x05,
    VK_XBUTTON2 = 0x06,
    // undefined 0x07
    VK_BACK = 0x08,
    VK_TAB = 0x09,
    // reserved 0x0A-0x0B
    VK_CLEAR = 0x0C,
    VK_RETURN = 0x0D,
    // undefined 0x0E-0x0F
    VK_SHIFT = 0x10,
    VK_CONTROL = 0x11,
    VK_MENU = 0x12,
    VK_PAUSE = 0x13,
    VK_CAPITAL = 0x14,
    VK_KANA = 0x15,
    VK_HANGEUL = 0x15,
    VK_HANGUL = 0x15,
    VK_JUNJA = 0x17,
    VK_FINAL = 0x18,
    VK_HANJA = 0x19,
    VK_KANJI = 0x19,
    VK_ESCAPE = 0x1B,
    VK_CONVERT = 0x1C,
    VK_NONCONVERT = 0x1D,
    VK_ACCEPT = 0x1E,
    VK_MODECHANGE = 0x1F,
    VK_SPACE = 0x20,
    VK_PRIOR = 0x21,
    VK_NEXT = 0x22,
    VK_END = 0x23,
    VK_HOME = 0x24,
    VK_LEFT = 0x25,
    VK_UP = 0x26,
    VK_RIGHT = 0x27,
    VK_DOWN = 0x28,
    VK_SELECT = 0x29,
    VK_PRINT = 0x2A,
    VK_EXECUTE = 0x2B,
    VK_SNAPSHOT = 0x2C,
    VK_INSERT = 0x2D,
    VK_DELETE = 0x2E,
    VK_HELP = 0x2F,
    VK_KEY_0 = 0x30,
    VK_KEY_1,
    VK_KEY_2,
    VK_KEY_3,
    VK_KEY_4,
    VK_KEY_5,
    VK_KEY_6,
    VK_KEY_7,
    VK_KEY_8,
    VK_KEY_9,
    // undefined 0x3A-0x40
    VK_KEY_A = 0x41,
    VK_KEY_B,
    VK_KEY_C,
    VK_KEY_D,
    VK_KEY_E,
    VK_KEY_F,
    VK_KEY_G,
    VK_KEY_H,
    VK_KEY_I,
    VK_KEY_J,
    VK_KEY_K,
    VK_KEY_L,
    VK_KEY_M,
    VK_KEY_N,
    VK_KEY_O,
    VK_KEY_P,
    VK_KEY_Q,
    VK_KEY_R,
    VK_KEY_S,
    VK_KEY_T,
    VK_KEY_U,
    VK_KEY_V,
    VK_KEY_W,
    VK_KEY_X,
    VK_KEY_Y,
    VK_KEY_Z,
    VK_LWIN = 0x5B,
    VK_RWIN = 0x5C,
    VK_APPS = 0x5D,
    // reserved 0x5E
    VK_SLEEP = 0x5F,
    VK_NUMPAD0 = 0x60,
    VK_NUMPAD1 = 0x61,
    VK_NUMPAD2 = 0x62,
    VK_NUMPAD3 = 0x63,
    VK_NUMPAD4 = 0x64,
    VK_NUMPAD5 = 0x65,
    VK_NUMPAD6 = 0x66,
    VK_NUMPAD7 = 0x67,
    VK_NUMPAD8 = 0x68,
    VK_NUMPAD9 = 0x69,
    VK_MULTIPLY = 0x6A,
    VK_ADD = 0x6B,
    VK_SEPARATOR = 0x6C,
    VK_SUBTRACT = 0x6D,
    VK_DECIMAL = 0x6E,
    VK_DIVIDE = 0x6F,
    VK_F1 = 0x70,
    VK_F2 = 0x71,
    VK_F3 = 0x72,
    VK_F4 = 0x73,
    VK_F5 = 0x74,
    VK_F6 = 0x75,
    VK_F7 = 0x76,
    VK_F8 = 0x77,
    VK_F9 = 0x78,
    VK_F10 = 0x79,
    VK_F11 = 0x7A,
    VK_F12 = 0x7B,
    VK_F13 = 0x7C,
    VK_F14 = 0x7D,
    VK_F15 = 0x7E,
    VK_F16 = 0x7F,
    VK_F17 = 0x80,
    VK_F18 = 0x81,
    VK_F19 = 0x82,
    VK_F20 = 0x83,
    VK_F21 = 0x84,
    VK_F22 = 0x85,
    VK_F23 = 0x86,
    VK_F24 = 0x87,
    // unassigned 0x88-0x8F
    // Fake VK for Ctrl+Z combo
    VK_UNDO = 0x89,
    VK_NUMLOCK = 0x90,
    VK_SCROLL = 0x91,
    // OEM specific 0x92-0x96
    // unassigned 0x97-0x9F
    VK_LSHIFT = 0xA0,
    VK_RSHIFT = 0xA1,
    VK_LCONTROL = 0xA2,
    VK_RCONTROL = 0xA3,
    VK_LMENU = 0xA4,
    VK_RMENU = 0xA5,
    VK_BROWSER_BACK = 0xA6,
    VK_BROWSER_FORWARD = 0xA7,
    VK_BROWSER_REFRESH = 0xA8,
    VK_BROWSER_STOP = 0xA9,
    VK_BROWSER_SEARCH = 0xAA,
    VK_BROWSER_FAVORITES = 0xAB,
    VK_BROWSER_HOME = 0xAC,
    VK_VOLUME_MUTE = 0xAD,
    VK_VOLUME_DOWN = 0xAE,
    VK_VOLUME_UP = 0xAF,
    VK_MEDIA_NEXT_TRACK = 0xB0,
    VK_MEDIA_PREV_TRACK = 0xB1,
    VK_MEDIA_STOP = 0xB2,
    VK_MEDIA_PLAY_PAUSE = 0xB3,
    VK_LAUNCH_MAIL = 0xB4,
    VK_LAUNCH_MEDIA_SELECT = 0xB5,
    VK_LAUNCH_APP1 = 0xB6,
    VK_LAUNCH_APP2 = 0xB7,
    // reserved 0xB8-0xB9
    VK_OEM_1 = 0xBA,
    VK_OEM_PLUS = 0xBB,
    VK_OEM_COMMA = 0xBC,
    VK_OEM_MINUS = 0xBD,
    VK_OEM_PERIOD = 0xBE,
    VK_OEM_2 = 0xBF,
    VK_OEM_3 = 0xC0,
    // reserved 0xC1-0xD7
    // unassigned 0xD8-0xDA
    VK_OEM_4 = 0xDB,
    VK_OEM_5 = 0xDC,
    VK_OEM_6 = 0xDD,
    VK_OEM_7 = 0xDE,
    VK_OEM_8 = 0xDF,
    // reserved 0xE0
    // OEM specific 0xE1
    VK_OEM_102 = 0xE2,
    // OEM specific 0xE3-0xE4
    VK_PROCESSKEY = 0xE5,
    // OEM specific 0xE6
    VK_PACKET = 0xE7,
    // unassigned 0xE8
    // OEM specific 0xE9-0xF5
    VK_ATTN = 0xF6,
    VK_CRSEL = 0xF7,
    VK_EXSEL = 0xF8,
    VK_EREOF = 0xF9,
    VK_PLAY = 0xFA,
    VK_ZOOM = 0xFB,
    VK_NONAME = 0xFC,
    VK_PA1 = 0xFD,
    VK_OEM_CLEAR = 0xFE,
    VK_VOID = 0xFF
}

struct Scancode {
    byte scan;
    bool extended;  // whether the extended bit is set for this physical key
}

struct NeoLayout {
    wstring name;
    wstring dllName;
    struct Modifiers {
        Scancode shiftLeft;
        Scancode shiftRight;
        Scancode mod3Left;
        Scancode mod3Right;
        Scancode mod4Left;
        Scancode mod4Right;
    }
    Modifiers modifiers;
    NeoKey[6][Scancode] map;  // map scancodes to a 6-array of keys for each layer
}

void initLayouts(JSONValue jsonLayoutArray) {
    layouts = [];

    foreach (JSONValue jsonLayout; jsonLayoutArray.array) {
        NeoLayout layout;
        layout.name = jsonLayout["name"].str.to!wstring;
        layout.dllName = jsonLayout["dllName"].str.to!wstring;
        layout.modifiers.shiftLeft = parseScancode(jsonLayout["modifiers"]["shiftLeft"].str);
        layout.modifiers.shiftRight = parseScancode(jsonLayout["modifiers"]["shiftRight"].str);
        layout.modifiers.mod3Left = parseScancode(jsonLayout["modifiers"]["mod3Left"].str);
        layout.modifiers.mod3Right = parseScancode(jsonLayout["modifiers"]["mod3Right"].str);
        layout.modifiers.mod4Left = parseScancode(jsonLayout["modifiers"]["mod4Left"].str);
        layout.modifiers.mod4Right = parseScancode(jsonLayout["modifiers"]["mod4Right"].str);

        foreach (string scancodeString, JSONValue jsonLayersArray; jsonLayout["map"]) {
            NeoKey[6] layers;
            for (int i = 0; i < 6; i++) {
                layers[i] = parseNeoKey(jsonLayersArray.array[i]);
            }
            layout.map[parseScancode(scancodeString)] = layers;
        }

        layouts ~= layout;
    }
}

NeoKey parseNeoKey(JSONValue jsonKey) {
    NeoKey key;
    
    if ("keysym" in jsonKey) {
        key.keysym = parseKeysym(jsonKey["keysym"].str);
    } else {
        key.keysym = KEYSYM_VOID;
    }

    if ("vk" in jsonKey) {
        key.keytype = NeoKeyType.VKEY;
        key.vk_code = jsonKey["vk"].str.to!VKEY;
    } else if ("char" in jsonKey) {
        key.keytype = NeoKeyType.CHAR;
        key.char_code = jsonKey["char"].str.to!wstring[0];
    }


    return key;
}

Scancode parseScancode(string scancodeString) {
    // scancode is a byte in hex, a + after the code means the extended bit is set
    bool extended = scancodeString.length == 3 && scancodeString[2] == '+';
    byte scan = scancodeString[0..2].to!byte(16);
    return Scancode(scan, extended);
}
