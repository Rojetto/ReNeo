module squire;

import std.stdio;
import std.utf;
import std.regex;
import std.conv;

import core.sys.windows.windows;

import mapping;
import composer;


alias VK = DWORD;

void debug_writeln(T...)(T args) {
    debug {
        writeln(args);
    }
}

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

NeoKey mVK(string keysym_str, VK vk) {
    NeoKey nk = { keysym: parseKeysym(keysym_str), keytype: NeoKeyType.VKEY, vk_code: vk };
    return nk;
}

NeoKey mCH(string keysym_str, wchar char_code) {
    NeoKey nk = { keysym: parseKeysym(keysym_str), keytype: NeoKeyType.CHAR, char_code: char_code };
    return nk;
}

struct KeySymEntry {
    uint key_code;
    wchar unicode_char;
}

KeySymEntry[string] keysymdefs;

void initKeysyms() {
    auto keysymfile = "keysymdef.h";
    debug_writeln("Initializing keysyms from ", keysymfile);
    // group 1: name, group 2: hex, group 3: unicode codepoint
    auto unicode_pattern = r"^\#define XK_([a-zA-Z_0-9]+)\s+0x([0-9a-f]+)\s*\/\* U\+([0-9A-F]{4,6}) (.*) \*\/\s*$";
    auto unicode_pattern_with_parens = r"^\#define XK_([a-zA-Z_0-9]+)\s+0x([0-9a-f]+)\s*\/\*\(U\+([0-9A-F]{4,6}) (.*)\)\*\/\s*$";
    // group 1: name, group 2: hex, group 3 and 4: comment stuff
    auto no_unicode_pattern = r"^\#define XK_([a-zA-Z_0-9]+)\s+0x([0-9a-f]+)\s*(\/\*\s*(.*)\s*\*\/)?\s*$";

    File f = File(keysymfile, "r");
	while(!f.eof()) {
		string l = f.readln();
        try {
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
        } catch (Exception e) {
            debug_writeln("Could not parse line '", l, "', skipping. Error: ", e.msg);
        }
	}
}

uint parseKeysym(string keysym) {
    if (keysym in keysymdefs) {
        return keysymdefs[keysym].key_code;
    } else if (auto m = matchFirst(keysym, r"^U([0-9a-fA-F]+)$")) {
        uint codepoint = to!uint(m[1], 16);

        if (codepoint <= 0xFFFF) {
            wchar unicode_char = to!wchar(codepoint);
            foreach (KeySymEntry entry; keysymdefs.byValue()) {
                if (entry.unicode_char == unicode_char) {
                    return entry.key_code;
                }
            }
        }

        return codepoint + 0x01000000;
    }

    debug_writeln("Keysym ", keysym, " not found.");

    return KEYSYM_VOID;
}

void sendVK(int vk, bool down) nothrow {
    INPUT[] inputs;

    // for some reason we must set the 'extended' flag for these keys, otherwise they won't work correctly in combination with Shift (?)
    bool extended = vk == VK_INSERT || vk == VK_DELETE || vk == VK_HOME || vk == VK_END || vk == VK_PRIOR || vk == VK_NEXT || vk == VK_UP || vk == VK_DOWN || vk == VK_LEFT || vk == VK_RIGHT || vk == VK_DIVIDE;

    INPUT input_struct;
    input_struct.type = INPUT_KEYBOARD;
    input_struct.ki.wVk = cast(ushort)vk;
    input_struct.ki.wScan = 0; // todo: maybe use a plausible value here
    input_struct.ki.dwFlags = 0;
    if (!down) {
        input_struct.ki.dwFlags |= KEYEVENTF_KEYUP;
    }
    if (extended) {
        input_struct.ki.dwFlags |= KEYEVENTF_EXTENDEDKEY;
    }
    inputs ~= input_struct;

    SendInput(cast(uint) inputs.length, inputs.ptr, INPUT.sizeof);
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

void sendString(wstring content) nothrow {
    INPUT[] inputs;
    inputs.length = content.length * 2;

    for (uint i = 0; i < content.length; i++) {    
        inputs[2*i].type = INPUT_KEYBOARD;
        inputs[2*i].ki.wVk = 0;
        inputs[2*i].ki.wScan = content[i];
        inputs[2*i].ki.dwFlags = KEYEVENTF_UNICODE;
        
        inputs[2*i + 1].type = INPUT_KEYBOARD;
        inputs[2*i + 1].ki.wVk = 0;
        inputs[2*i + 1].ki.wScan = content[i];
        inputs[2*i + 1].ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP;
    }

    SendInput(cast(uint) inputs.length, inputs.ptr, INPUT.sizeof);
}

void sendNeoKey(NeoKey nk, bool down) nothrow {
    if (nk.keysym == KEYSYM_VOID) {
        return;
    }

    if (nk.keytype == NeoKeyType.VKEY) {
        sendVK(nk.vk_code, down);
    } else {
        sendUTF16(nk.char_code, down);
    }
}

NeoKey mapToNeo(VK vk, uint layer) nothrow {
    if (vk in M) {
        return M[vk][layer - 1];
    }

    return VOID_KEY;
}


bool leftShiftDown;
bool rightShiftDown;
bool leftMod3Down;
bool rightMod3Down;
bool leftMod4Down;
bool rightMod4Down;

bool mod4Lock;

uint previousLayer = 1;

// when we press a VK, store what NeoKey we send so that we can release it correctly later
NeoKey[VK] heldKeys;


bool keyboardHook(WPARAM msg_type, KBDLLHOOKSTRUCT msg_struct) nothrow {
    auto vk = msg_struct.vkCode;
    auto scan = msg_struct.scanCode;
    bool down = msg_type == WM_KEYDOWN || msg_type == WM_SYSKEYDOWN;
    // TODO: do we need to use this somewhere?
    bool sys = msg_type == WM_SYSKEYDOWN || msg_type == WM_SYSKEYUP;

    // ignore all simulated keypresses
    // TODO: use LLKHF_INJECTED
    if (vk == VK_PACKET || scan == 0) {
        return false;
    }

    // setting eat = true stops the keypress from propagating further
    bool eat = false;

    // update stored modifier key states
    // GetAsyncKeyState didn't seem to work for multiple simultaneous keys
    if (vk == VK_LSHIFT) {
        leftShiftDown = down;

        // CAPSLOCK by pressing both Shift keys
        // TODO: Handle repeat correctly
        if (down && rightShiftDown) {
            sendVK(VK_CAPITAL, true);
            sendVK(VK_CAPITAL, false);
        }
    } else if (vk == VK_RSHIFT) {
        rightShiftDown = down;

        if (down && leftShiftDown) {
            sendVK(VK_CAPITAL, true);
            sendVK(VK_CAPITAL, false);
        }
    } else if (vk == 0x8A) {
        leftMod3Down = down;
    } else if (vk == 0x8B) {
        rightMod3Down = down;
    } else if (vk == 0x8C) {
        leftMod4Down = down;

        if (down && rightMod4Down) {
            mod4Lock = !mod4Lock;
        }
    } else if (vk == 0x8D) {
        rightMod4Down = down;

        if (down && leftMod4Down) {
            mod4Lock = !mod4Lock;
        }
    }

    bool shiftDown = leftShiftDown || rightShiftDown;
    bool mod3Down = leftMod3Down || rightMod3Down;
    bool mod4Down = leftMod4Down || rightMod4Down;

    // determine the layer we are currently on
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

    if (mod4Lock) {
        layer = 4;
    }

    // We want to treat layers 1 and 2 the same in terms of checking whether we switched
    // This is because pressing or releasing shift should not send a keyup for all held keys
    // (where as it should for keys from all other layers)
    uint patchedLayer = layer;
    if (patchedLayer == 2) {
        patchedLayer = 1;
    }
    bool changedLayer = patchedLayer != previousLayer;
    previousLayer = patchedLayer;

    // if we switched layers release all currently held keys
    if (changedLayer) {
        foreach (entry; heldKeys.byKeyValue()) {
            sendNeoKey(entry.value, false);
        }
        heldKeys.clear();
    }

    // early exit if key is not in map
    if (!(vk in M)) {
        return false;
    }

    // translate keypress to NEO layout factoring in the current layer
    NeoKey nk = mapToNeo(vk, layer);

    if (down) {
        auto composeResult = compose(nk);

        if (composeResult.type == ComposeResultType.PASS) {
            heldKeys[vk] = nk;

            if (layer >= 3) {
                eat = true;
                sendNeoKey(nk, true);
            }
        } else {
            eat = true;

            if (composeResult.type == ComposeResultType.FINISH || composeResult.type == ComposeResultType.ABORT) {
                sendString(composeResult.result);
            }
        }
    } else {
        if (layer >= 3) {
            eat = true;

            // release the key that is held for this vk
            // don't send a keyup if no key is stored as held
            if (vk in heldKeys) {
                auto heldKey = heldKeys[vk];
                sendNeoKey(heldKey, false);
                heldKeys.remove(vk);
            }
        } else {
            // layer 1 and 2 keys that are not stored as held
            // (probably because we ate them when composing or we switched down to this layer and already released the keys)
            if (!(vk in heldKeys)) {
                eat = true;
            }
        }
    }

    return eat;
}