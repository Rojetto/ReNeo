module reneo;

import std.stdio;
import std.utf;
import std.regex;
import std.conv;
import std.path;
import std.format;

import core.sys.windows.windows;

import mapping;
import composer;

const SC_FAKE_LSHIFT = 0x22A;
const SC_FAKE_RSHIFT = 0x236;
const SC_FAKE_LCTRL = 0x21D;

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
        VKEY vk_code;
        wchar char_code;
    }
}


struct KeySymEntry {
    uint key_code;
    wchar unicode_char;
}

KeySymEntry[string] keysymdefs;

void initKeysyms(string exeDir) {
    auto keysymfile = buildPath(exeDir, "keysymdef.h");
    debug_writeln("Initializing keysyms from ", keysymfile);
    // group 1: name, group 2: hex, group 3: unicode codepoint
    auto unicode_pattern = r"^\#define XK_([a-zA-Z_0-9]+)\s+0x([0-9a-f]+)\s*\/\* U\+([0-9A-F]{4,6}) (.*) \*\/\s*$";
    auto unicode_pattern_with_parens = r"^\#define XK_([a-zA-Z_0-9]+)\s+0x([0-9a-f]+)\s*\/\*\(U\+([0-9A-F]{4,6}) (.*)\)\*\/\s*$";
    // group 1: name, group 2: hex, group 3 and 4: comment stuff
    auto no_unicode_pattern = r"^\#define XK_([a-zA-Z_0-9]+)\s+0x([0-9a-f]+)\s*(\/\*\s*(.*)\s*\*\/)?\s*$";
    keysymdefs.clear();

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
        // Special cases for weird mappings
        if (nk.vk_code == VKEY.VK_LBUTTON) {
            sendMouseClick(down);
        } else if (nk.vk_code == VKEY.VK_UNDO) {
            if (down) {
                sendVK(VK_CONTROL, true);
                sendVK('Z', true);
            } else {
                sendVK('Z', false);
                sendVK(VK_CONTROL, false);
            }
        } else {
            return;
        }
    }

    if (nk.keytype == NeoKeyType.VKEY) {
        sendVK(nk.vk_code, down);
    } else {
        sendUTF16(nk.char_code, down);
    }
}

NeoKey mapToNeo(Scancode scan, uint layer) nothrow {
    if (scan in activeLayout.map) {
        return activeLayout.map[scan][layer - 1];
    }

    return VOID_KEY;
}

void sendMouseClick(bool down) nothrow {
    // Always returns state of logical primary mouse button (contrary to documentation in GetAsyncKeyState)
    bool mousedown = (GetKeyState(VK_LBUTTON) >> 16) != 0;
    if (mousedown == down) return;

    INPUT input_struct;
    input_struct.type = INPUT_MOUSE;
    input_struct.mi.dx = 0;
    input_struct.mi.dy = 0;
    // If primary mouse button is swapped, use rightdown/rightup flags.
    DWORD dwFlags = down ? MOUSEEVENTF_LEFTDOWN : MOUSEEVENTF_LEFTUP;
    if (GetSystemMetrics(SM_SWAPBUTTON)) {
        dwFlags = dwFlags << 2;
    }
    input_struct.mi.dwFlags = dwFlags;
    SendInput(1, &input_struct, INPUT.sizeof);
}

bool getKanaState() nothrow {
    bool state = GetKeyState(VK_KANA) & 0x0001;
    return state;
}

void setKanaState(bool state) nothrow {
    if (getKanaState() != state) {
        sendVK(VK_KANA, true);
        sendVK(VK_KANA, false);
    }
}

bool getNumlockState() nothrow {
    bool state = GetKeyState(VK_NUMLOCK) & 0x0001;
    return state;
}

void setNumlockState(bool state) nothrow {
    if (getNumlockState() != state) {
        sendVK(VK_NUMLOCK, true);
        sendVK(VK_NUMLOCK, false);
    }
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
NeoKey[Scancode] heldKeys;

NeoLayout *activeLayout;


bool setActiveLayout(NeoLayout *newLayout) nothrow @nogc {
    bool changed = newLayout != activeLayout;
    activeLayout = newLayout;
    return changed;
}


bool keyboardHook(WPARAM msg_type, KBDLLHOOKSTRUCT msg_struct) nothrow {
    auto vk = cast(VKEY) msg_struct.vkCode;
    bool down = msg_type == WM_KEYDOWN || msg_type == WM_SYSKEYDOWN;
    // TODO: do we need to use this somewhere?
    bool sys = msg_type == WM_SYSKEYDOWN || msg_type == WM_SYSKEYUP;
    auto scan = Scancode(cast(byte) msg_struct.scanCode, (msg_struct.flags & LLKHF_EXTENDED) > 0);
    bool altdown = (msg_struct.flags & LLKHF_ALTDOWN) > 0;
    bool injected = (msg_struct.flags & LLKHF_INJECTED) > 0;

    debug {
        auto injected_text = injected      ? "(injected) " : "           ";
        auto down_text     = down          ? "(down) " : " (up)  ";
        auto alt_text      = altdown       ? "(Alt) " : "      ";
        auto extended_text = scan.extended ? "(Ext) " : "      ";

        try {
            writeln(injected_text ~ down_text ~ alt_text ~ extended_text ~ format("| Scan 0x%04X | %s (0x%02X)", scan.scan, to!string(vk), vk));
        } catch(Exception e) {}
    }

    // ignore all simulated keypresses
    if (vk == VKEY.VK_PACKET || injected) {
        return false;
    }

    // Numpad 0-9 and separator are dual-state Numpad keys:
    // scancode range 0x47–0x53 (without 0x4A and 0x4E), no extended scancode
    bool isDualStateNumpadKey = (!scan.extended && scan.scan >= 0x47 && scan.scan <= 0x53 && scan.scan != 0x4A && scan.scan != 0x4E);
    // All Numpad keys including KP_Enter
    bool isNumpadKey = isDualStateNumpadKey || vk == VKEY.VK_NUMLOCK || (scan.extended && vk == VKEY.VK_RETURN) || 
                       vk == VKEY.VK_ADD || vk == VKEY.VK_SUBTRACT || vk == VKEY.VK_MULTIPLY || vk == VKEY.VK_DIVIDE;
                       
    // Deactivate Kana lock if necessary because Kana permanently activates layer 4 in kbdneo
    setKanaState(false);
    // We want Numlock to be always off so that we don't get fake shift events on layer 2
    setNumlockState(false);

    // was the pressed key a NEO modifier (M3 or M4)? Because we don't want to send those to applications.
    bool isNeoModifier;

    // update stored modifier key states
    // GetAsyncKeyState didn't seem to work for multiple simultaneous keys

    // Do not recognize fake shift events.
    // For more information see https://github.com/Lexikos/AutoHotkey_L/blob/master/source/keyboard_mouse.h#L139
    if (scan == activeLayout.modifiers.shiftLeft && scan.scan != SC_FAKE_LSHIFT) {
        // CAPSLOCK by pressing both Shift keys
        // leftShiftDown contains previous state
        if (!leftShiftDown && down && rightShiftDown) {
            sendVK(VK_CAPITAL, true);
            sendVK(VK_CAPITAL, false);
        }

        leftShiftDown = down;
    } else if (scan == activeLayout.modifiers.shiftRight && scan.scan != SC_FAKE_RSHIFT) {
        if (!rightShiftDown && down && leftShiftDown) {
            sendVK(VK_CAPITAL, true);
            sendVK(VK_CAPITAL, false);
        }

        rightShiftDown = down;
    } else if (scan == activeLayout.modifiers.mod3Left) {
        leftMod3Down = down;
        isNeoModifier = true;
    } else if (scan == activeLayout.modifiers.mod3Right) {
        rightMod3Down = down;
        isNeoModifier = true;
    } else if (scan == activeLayout.modifiers.mod4Left) {
        leftMod4Down = down;
        isNeoModifier = true;

        if (down && rightMod4Down) {
            mod4Lock = !mod4Lock;
        }
    } else if (scan == activeLayout.modifiers.mod4Right) {
        rightMod4Down = down;
        isNeoModifier = true;

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
        if (mod4Down) {
            // switch back to layer 1 while holding mod 4
            layer = 1;
        } else {
            layer = 4;
        }
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

    // immediately eat M3 and M4 keys
    if (isNeoModifier) {
        return true;
    }

    // Handle Numlock key, which would otherwise toggle Numlock state without changing the LED.
    // For more information see AutoHotkey: https://github.com/Lexikos/AutoHotkey_L/blob/master/source/hook.cpp#L2027
    if (vk == VKEY.VK_NUMLOCK && down) {
        sendVK(VK_NUMLOCK, false);
        sendVK(VK_NUMLOCK, true);
        sendVK(VK_NUMLOCK, false);
        sendVK(VK_NUMLOCK, true);
    }

    // early exit if key is not in map
    if (!(scan in activeLayout.map)) {
        return false;
    }

    // setting eat = true stops the keypress from propagating further
    bool eat = false;

    // translate keypress to NEO layout factoring in the current layer
    NeoKey nk = mapToNeo(scan, layer);

    if (down) {
        auto composeResult = compose(nk);

        if (composeResult.type == ComposeResultType.PASS) {
            heldKeys[scan] = nk;

            // Translate all layers for Numpad keys
            if (layer >= 3 || isNumpadKey) {
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
        if (layer >= 3 || isNumpadKey) {
            eat = true;

            // release the key that is held for this vk
            // don't send a keyup if no key is stored as held
            if (scan in heldKeys) {
                auto heldKey = heldKeys[scan];
                sendNeoKey(heldKey, false);
            }
        } else {
            // layer 1 and 2 keys that are not stored as held
            // (probably because we ate them when composing or we switched down to this layer and already released the keys)
            if (!(scan in heldKeys)) {
                eat = true;
            }
        }

        heldKeys.remove(scan);
    }

    return eat;
}
