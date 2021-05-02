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
import app : configSendKeyMode;

const SC_FAKE_LSHIFT = 0x22A;
const SC_FAKE_RSHIFT = 0x236;
const SC_FAKE_LCTRL = 0x21D;

Scancode scanCapslock = Scancode(0x3A, false);
Scancode scanLShift = Scancode(0x2A, false);
Scancode scanRShift = Scancode(0x36, true);
Scancode scanLAlt  = Scancode(0x38, false);
Scancode scanAltGr = Scancode(0x38, true);
Scancode scanLCtrl = Scancode(0x1D, false);
Scancode scanRCtrl = Scancode(0x1D, true);
Scancode scanNumlock = Scancode(0x45, true);

void debug_writeln(T...)(T args) {
    debug {
        writeln(args);
    }
}

enum SendKeyMode {
    HONEST,      // send scancode of physically pressed keys and "char" entries as unicode
    FAKE_NATIVE  // send scancode of equivalent key in native layout and replace "char" entries with native key combos if possible
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

auto UNICODE_REGEX = regex(r"^U([0-9a-fA-F]+)$");

uint parseKeysym(string keysym) {
    if (keysym in keysymdefs) {
        return keysymdefs[keysym].key_code;
    } else if (auto m = matchFirst(keysym, UNICODE_REGEX)) {
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

void sendVK(uint vk, Scancode scan, bool down) nothrow {
    INPUT[] inputs;

    // for some reason we must set the 'extended' flag for these keys, otherwise they won't work correctly in combination with Shift (?)
    scan.extended |= vk == VK_INSERT || vk == VK_DELETE || vk == VK_HOME || vk == VK_END || vk == VK_PRIOR || vk == VK_NEXT || vk == VK_UP || vk == VK_DOWN || vk == VK_LEFT || vk == VK_RIGHT || vk == VK_DIVIDE;
    appendInput(inputs, vk, scan, down);

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

void sendUTF16OrKeyCombo(wchar unicode_char, bool down) nothrow {
    /// Send a native key combo if there is one in the current layout, otherwise send unicode directly
    debug {
        try {
            writeln(format("Trying to send %s (0x%04X) ...", unicode_char, to!int(unicode_char)));
        }
        catch (Exception e) {}
    }

    short result = VkKeyScan(unicode_char);
    ubyte low = cast(ubyte) result;
    ubyte high = cast(ubyte) (result >> 8);

    ushort vk = low;
    bool shift = (high & 1) != 0;
    bool ctrl = (high & 2) != 0;
    bool alt = (high & 4) != 0;
    bool kana = (high & 8) != 0;
    bool mod5 = (high & 16) != 0;
    bool mod6 = (high & 32) != 0;

    if (low == 0xFF || kana || mod5 || mod6) {
        // char does not exist in native layout or requires exotic modifiers
        debug_writeln("No standard key combination found, sending via VK packet");
        sendUTF16(unicode_char, down);
        return;
    }

    debug {
        try {
            auto shift_text = shift ? "(Shift) " : "        ";
            auto ctrl_text  = ctrl  ? "(Ctrl)  " : "        ";
            auto alt_text   = alt   ? "(Alt)   " : "        ";
            auto kana_text  = kana  ? "(Kana)  " : "        ";
            auto mod5_text  = mod5  ? "(Mod5)  " : "        ";
            auto mod6_text  = mod6  ? "(Mod6)  " : "        ";
            debug_writeln("Key combination is " ~ to!string(cast(VKEY) vk) ~ " "
                ~ shift_text ~ ctrl_text ~ alt_text ~ kana_text ~ mod5_text ~ mod6_text);
        } catch (Exception ex) {}
    }

    INPUT[] inputs;

    // If Shift modifier is not used: unpress Shift key(s) if already pressed (only for down event).
    // For Qwertz necessary only for Euro key (AltGr+E) by pressing Shift+7 in Neo layout.
    bool unpressShift = false;
    if ((leftShiftDown || rightShiftDown) && !shift && down) {
        if (leftShiftDown) { appendInput(inputs, VK_LSHIFT, scanLShift, false); }
        if (rightShiftDown) { appendInput(inputs, VK_RSHIFT, scanRShift, false); }
        unpressShift = true;
    }

    // For up events, release the main key before the modifiers
    if (!down) {
        appendInput(inputs, vk, Scancode(MapVirtualKey(vk, MAPVK_VK_TO_VSC), false), down);
    }

    // modifiers
    // pay attention to current capslock state
    // warning: this is only an approximation. whether capslock affects this key is dependent on the native layout
    // this means sometimes we need to invert capslock with shift, sometimes not... as of yet this is an open issue.
    //
    // Only add Shift in two cases:
    // (1) Capslock is disabled. If the virtual key combination needs Shift, it will be injected.
    // (2) Capslock is enabled. Only if the virtual key combination needs no modifiers (Shift/Alt/Ctrl),
    //     it will be injected. The shift state and the capslock state will cancel each other out.
    // (2.1) If the key combination requires only Shift, the capslock state works as active Shift key.
    // (2.2) If higher modifiers Ctrl or Alt are involved, the capslock state has no effect.
    // So for cases 2.1 and 2.2, no additional Shift is sent.
    if ((shift && !capslock) || (high == 0 && capslock)) {
        appendInput(inputs, VKEY.VK_SHIFT, scanLShift, down);
    }
    if (ctrl) {
        appendInput(inputs, VKEY.VK_CONTROL, scanLCtrl, down);
    }
    if (alt) {
        appendInput(inputs, VKEY.VK_MENU, scanLAlt, down);
    }

    // For down events, set the main key after the modifiers
    if (down) {
        appendInput(inputs, vk, Scancode(MapVirtualKey(vk, MAPVK_VK_TO_VSC), false), down);
    }

    // Re-press Shift key(s)
    if (unpressShift) {
        if (leftShiftDown) { appendInput(inputs, VK_LSHIFT, scanLShift, true); }
        if (rightShiftDown) { appendInput(inputs, VK_RSHIFT, scanRShift, true); }
    }

    SendInput(cast(uint) inputs.length, inputs.ptr, INPUT.sizeof);
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

void appendInput(ref INPUT[] inputs, uint vk, Scancode scan, bool down) nothrow {
    INPUT input_struct;
    input_struct.type = INPUT_KEYBOARD;
    input_struct.ki.wVk = cast(ushort) vk;
    input_struct.ki.wScan = cast(ushort) scan.scan;
    if (!down) {
        input_struct.ki.dwFlags = KEYEVENTF_KEYUP;
    }
    if (scan.extended) {
        input_struct.ki.dwFlags |= KEYEVENTF_EXTENDEDKEY;
    }
    inputs ~= input_struct;
}

void sendNeoKey(NeoKey nk, Scancode realScan, bool down) nothrow {
    if (nk.keysym == KEYSYM_VOID) {
        // Special cases for weird mappings
        if (nk.vk_code == VKEY.VK_LBUTTON) {
            sendMouseClick(down);
        } else if (nk.vk_code == VKEY.VK_UNDO) {
            if (down) {
                // TODO: fix scancodes
                sendVK(VK_CONTROL, scanLCtrl, true);
                sendVK('Z', Scancode(MapVirtualKey(VKEY.VK_KEY_Z, MAPVK_VK_TO_VSC), false), true);
            } else {
                sendVK('Z', Scancode(MapVirtualKey(VKEY.VK_KEY_Z, MAPVK_VK_TO_VSC), false), false);
                sendVK(VK_CONTROL, scanLCtrl, false);
            }
        } else {
            return;
        }
    }

    if (nk.keytype == NeoKeyType.VKEY) {
        Scancode scan = realScan;
        switch (configSendKeyMode) {
            case SendKeyMode.HONEST: break; // leave the real scan code
            case SendKeyMode.FAKE_NATIVE:
            auto map_result = MapVirtualKey(nk.vk_code, MAPVK_VK_TO_VSC);
            if (map_result) {
                // vk does exist in native layout, use the fake native scan code
                scan.extended = false;
                scan.scan = map_result;
            }
            break;
            default: break;
        }
        sendVK(nk.vk_code, scan, down);
    } else {
        switch (configSendKeyMode) {
            case SendKeyMode.HONEST:
            sendUTF16(nk.char_code, down);
            break;
            case SendKeyMode.FAKE_NATIVE:
            sendUTF16OrKeyCombo(nk.char_code, down);
            break;
            default: break;
        }
    }
}

NeoKey mapToNeo(Scancode scan, uint layer) nothrow {
    if (scan in activeLayout.map) {
        return activeLayout.map[scan].layers[layer - 1];
    }

    return VOID_KEY;
}

bool isCapslockable(Scancode scan) nothrow {
    if (scan in activeLayout.map) {
        return activeLayout.map[scan].capslockable;
    }

    return false;
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
        sendVK(VK_KANA, Scancode(0, false), true);
        sendVK(VK_KANA, Scancode(0, false), false);
    }
}

bool getNumlockState() nothrow {
    bool state = GetKeyState(VK_NUMLOCK) & 0x0001;
    return state;
}

void setNumlockState(bool state) nothrow {
    if (getNumlockState() != state) {
        sendVK(VK_NUMLOCK, scanNumlock, true);
        sendVK(VK_NUMLOCK, scanNumlock, false);
    }
}


bool leftShiftDown;
bool rightShiftDown;
bool leftMod3Down;
bool rightMod3Down;
bool leftMod4Down;
bool rightMod4Down;

bool capslock;
bool mod4Lock;

uint previousLayer = 1;

// when we press a VK, store what NeoKey we send so that we can release it correctly later
NeoKey[Scancode] heldKeys;

NeoLayout *activeLayout;

// should we take over all layers? activated when standaloneMode is true in the config file and the currently selected native layout is not Neo related
bool standaloneModeActive;


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
    auto scan = Scancode(cast(uint) msg_struct.scanCode, (msg_struct.flags & LLKHF_EXTENDED) > 0);
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

    // Disable fake LCTRL on AltGr as we use that for Mod4
    if (scan.scan == SC_FAKE_LCTRL) {
        return true;
    }

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
            sendVK(VK_CAPITAL, scanCapslock, true);
            sendVK(VK_CAPITAL, scanCapslock, false);
        }

        leftShiftDown = down;
    } else if (scan == activeLayout.modifiers.shiftRight && scan.scan != SC_FAKE_RSHIFT) {
        if (!rightShiftDown && down && leftShiftDown) {
            sendVK(VK_CAPITAL, scanCapslock, true);
            sendVK(VK_CAPITAL, scanCapslock, false);
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

    // is capslock active?
    capslock = GetKeyState(VKEY.VK_CAPITAL) & 0x0001;

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
    }  else if (shiftDown || (capslock && isCapslockable(scan))) {
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
            sendNeoKey(entry.value, entry.key, false);
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
        sendVK(VK_NUMLOCK, scanNumlock, false);
        sendVK(VK_NUMLOCK, scanNumlock, true);
        sendVK(VK_NUMLOCK, scanNumlock, false);
        sendVK(VK_NUMLOCK, scanNumlock, true);
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
            if (layer >= 3 || isNumpadKey || standaloneModeActive) {
                eat = true;
                sendNeoKey(nk, scan, true);
            }
        } else {
            eat = true;

            if (composeResult.type == ComposeResultType.FINISH || composeResult.type == ComposeResultType.ABORT) {
                sendString(composeResult.result);
            }
        }
    } else {
        if (layer >= 3 || isNumpadKey || standaloneModeActive) {
            eat = true;

            // release the key that is held for this vk
            // don't send a keyup if no key is stored as held
            if (scan in heldKeys) {
                auto heldKey = heldKeys[scan];
                sendNeoKey(heldKey, scan, false);
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
