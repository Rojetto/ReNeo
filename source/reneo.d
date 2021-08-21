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
import app : configSendKeyMode, configAutoNumlock, configFilterNeoModifiers, updateOSKAsync, toggleOSK, lastInputLocale;

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
    string label;
}

uint[string] keysyms_by_name;
uint[uint] keysyms_by_codepoint;
uint[uint] codepoints_by_keysym;
const KEYSYM_CODEPOINT_OFFSET = 0x01000000;

// Initializes list of keysyms by a given keysymdef.h from X.org project,
// see https://cgit.freedesktop.org/xorg/proto/x11proto/tree/keysymdef.h
void initKeysyms(string exeDir) {
    auto keysymfile = buildPath(exeDir, "keysymdef.h");
    debug_writeln("Initializing keysyms from ", keysymfile);
    // group 1: name, group 2: hex, group 3: unicode codepoint
    auto unicode_pattern = r"^\#define XK_([a-zA-Z_0-9]+)\s+0x([0-9a-fA-F]+)\s*\/\*[ \(]U\+([0-9a-fA-F]{4,6}) (.*)[ \)]\*\/\s*$";
    // group 1: name, group 2: hex, group 3 and 4: comment stuff
    auto no_unicode_pattern = r"^\#define XK_([a-zA-Z_0-9]+)\s+0x([0-9a-fA-F]+)\s*(\/\*\s*(.*)\s*\*\/)?\s*$";
    keysyms_by_name.clear();
    keysyms_by_codepoint.clear();
    codepoints_by_keysym.clear();

    File f = File(keysymfile, "r");
	while(!f.eof()) {
		string l = f.readln();
        try {
            if (auto m = matchFirst(l, unicode_pattern)) {
                string keysym_name = m[1];
                uint key_code = to!uint(m[2], 16);
                uint codepoint = to!uint(m[3], 16);
                keysyms_by_name[keysym_name] = key_code;
                keysyms_by_codepoint[codepoint] = key_code;
                // for quick reverse search
                codepoints_by_keysym[key_code] = codepoint;
            } else if (auto m = matchFirst(l, no_unicode_pattern)) {
                string keysym_name = m[1];
                uint key_code = to!uint(m[2], 16);
                keysyms_by_name[keysym_name] = key_code;
            }
        } catch (Exception e) {
            debug_writeln("Could not parse line '", l, "', skipping. Error: ", e.msg);
        }
	}
}

auto UNICODE_REGEX = regex(r"^U([0-9a-fA-F]+)$");

// Parse a string by a lookup in the initialized keysym tables, either by name
// or by codepoint. The latter works also for algorithmically defined strings
// in the form "U00A0" to "U10FFFF" which represent any possible Unicode
// character as hex value.
uint parseKeysym(string keysym_str) {
    if (uint *keysym = keysym_str in keysyms_by_name) {
        // The corresponding keysym is explicitly defined by the given name
        return *keysym;
    } else if (auto m = matchFirst(keysym_str, UNICODE_REGEX)) {
        uint codepoint = to!uint(m[1], 16);

        // Legacy keysyms for some Unicode values between 0x0100 and 0x30FF
        if (codepoint <= 0x30FF) {
            if (uint *keysym = codepoint in keysyms_by_codepoint) {
                // If defined, return the legacy keysym value
                return *keysym;
            }
        }

        // Otherwise just return the keysym matching the codepoint with an offset
        return codepoint + KEYSYM_CODEPOINT_OFFSET;
    }

    debug_writeln("Keysym ", keysym_str, " not found.");

    return KEYSYM_VOID;
}

void sendVK(uint vk, Scancode scan, bool down) nothrow {
    INPUT[] inputs;

    // check virtual modifier keys currently held down and release them if necessary
    if (virtualShiftDown) {
        appendInput(inputs, VKEY.VK_SHIFT, scanLShift, false);
        virtualShiftDown = false;
    }
    if (virtualAltDown) {
        // Release virtual AltGr key, which consists of RAlt and LCtrl.
        appendInput(inputs, VKEY.VK_MENU, scanAltGr, false);
        appendInput(inputs, VKEY.VK_CONTROL, scanLCtrl, false);
        virtualAltDown = false;
    }

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

// Persistent state of virtually pressed standard modifiers
bool virtualShiftDown;
bool virtualAltDown;

void sendUTF16OrKeyCombo(wchar unicode_char, bool down) nothrow {
    /// Send a native key combo if there is one in the current layout, otherwise send unicode directly
    debug {
        try {
            writeln(format("Trying to send %s (0x%04X) ...", unicode_char, to!int(unicode_char)));
        }
        catch (Exception e) {}
    }

    short result = VkKeyScanEx(unicode_char, lastInputLocale);
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
        debug_writeln("No standard key combination found, sending VK packet instead.");
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

    // The found key combination might send a dead key (like ^ or ~), which we want to avoid. MapVirtualKey()
    // is only able to recognize a dead key if no modifier keys are involved. Instead ToUnicode() is used.
    // Generally it would be necessary to get the current (physical) keyboard state first. But as we need
    // to check a hypothetical keyboard state, we can just set flags for Shift, Control and Menu keys
    // in an otherwise zero-initialized array.
    ubyte[256] kb;
    wchar[4] buf;
    if (shift) { kb[VK_SHIFT] |= 128; }
    if (ctrl) { kb[VK_CONTROL] |= 128; }
    if (alt) { kb[VK_MENU] |= 128; }
    if (capslock) { kb[VK_CAPITAL] = 1; } // Set toggle state of capslock
    
    if (ToUnicodeEx(vk, 0, kb.ptr, buf.ptr, 4, 0, lastInputLocale) == -1) {
        debug_writeln("Standard key combination results in a dead key, sending VK packet instead.");
        // The same dead key needs to be queried again, because ToUnicode() inserts the dead key (state)
        // into the queue, while anothèr call consumes the dead key.
        // See https://github.com/Lexikos/AutoHotkey_L/blob/master/source/hook.cpp#L2597
        ToUnicodeEx(vk, 0, kb.ptr, buf.ptr, 4, 0, lastInputLocale);
        sendUTF16(unicode_char, down);
        return;
    }

    INPUT[] inputs;

    // For up events, release the main key before the modifiers
    if (!down) {
        appendInput(inputs, vk, Scancode(MapVirtualKeyEx(vk, MAPVK_VK_TO_VSC, lastInputLocale), false), down);
    }

    // There are three flags that affect the overall result of a current Shift state:
    // (1) a Shift key is physically pressed
    // (2) Capslock is active
    // (3) the key is capslockable

    // The latter can be queried indirectly by reversely generating the Unicode char with a given
    // keyboard state. If the result of toUnicode() is different from the expected char (and capslock
    // is active), the key is capslockable.
    // The other way round, if a key is not capslockable, the Capslock state must not be considered.

    // This flag is set to false if Capslock is not active. This is because the capslockable state
    // can only be checked when Capslock is active (and only then has any influence).
    bool nativeCapslockable = (buf[0] != unicode_char) && capslock;
    // Is any Shift key pressed physically?
    bool physicalShiftDown = leftShiftDown || rightShiftDown;
    // Calculate the overall Shift state from the flags described
    bool overallShift = (!nativeCapslockable && physicalShiftDown)
                      || (nativeCapslockable && (physicalShiftDown ^ capslock));
    bool releasedShift = false;

    // Release virtually pressed modifiers, if they must not be used for the virtual key combination
    if (down) {
        // If the required and the current Shift states are already matching, an additionally pressed
        // virtual Shift key must be released then.
        if (virtualShiftDown && (overallShift == shift)) {
            appendInput(inputs, VK_SHIFT, scanLShift, false);
            virtualShiftDown = false;
        }
        if (virtualAltDown && !alt) {
            // Release virtual AltGr key, which consists of RAlt and LCtrl.
            appendInput(inputs, VKEY.VK_MENU, scanAltGr, false);
            appendInput(inputs, VKEY.VK_CONTROL, scanLCtrl, false);
            virtualAltDown = false;
        }
    }

    // If the required and the current Shift states differ, the current Shift state is changed
    if (overallShift != shift) {
        if (physicalShiftDown) {
            // If any Shift key is already down, changing can only be done by releasing the pressed
            // key. This is executed for key-down events only. For key-up it does not matter and saves
            // two unnecessary key events.
            if (down) {
                if (leftShiftDown) { appendInput(inputs, VK_LSHIFT, scanLShift, false); }
                if (rightShiftDown) { appendInput(inputs, VK_RSHIFT, scanRShift, false); }
                releasedShift = true;
            }
        } else if (virtualShiftDown != down) {
            // At this point an additional virtual Shift key is necessary to reach the correct Shift state.
            // Only if the (virtual) key is still up it will be pressed down.
            appendInput(inputs, VK_SHIFT, scanLShift, down);
            virtualShiftDown = down;
        }
    }
    // The Alt modifier is considered as AltGr, which is equivalent to LCtrl and RAlt. To prevent
    // Windows from inserting a fake LCtrl event (no matter if injected or not), we get there first
    // by injecting both LCtrl and RAlt events.
    // Accordingly, Ctrl will not be handled separately, as it occurs always in combination with Alt.
    if (alt && virtualAltDown != down) {
        // Order matters: for up-events the RAlt key has to come first. Otherwise the LCtrl is not
        // considering "matching" because it would still have LLKHF_ALTDOWN flag set, and a fake LCtrl
        // is then generated.
        if (down) {
            appendInput(inputs, VKEY.VK_CONTROL, scanLCtrl, down);
            appendInput(inputs, VKEY.VK_MENU, scanAltGr, down);
        } else {
            appendInput(inputs, VKEY.VK_MENU, scanAltGr, down);
            appendInput(inputs, VKEY.VK_CONTROL, scanLCtrl, down);
        }
        virtualAltDown = down;
    }

    // For down events, set the main key after the modifiers
    if (down) {
        appendInput(inputs, vk, Scancode(MapVirtualKeyEx(vk, MAPVK_VK_TO_VSC, lastInputLocale), false), down);
    }

    // Re-press Shift key(s)
    if (releasedShift) {
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
                sendVK(VK_CONTROL, scanLCtrl, true);
                sendVK('Z', Scancode(MapVirtualKeyEx(VKEY.VK_KEY_Z, MAPVK_VK_TO_VSC, lastInputLocale), false), true);
            } else {
                sendVK('Z', Scancode(MapVirtualKeyEx(VKEY.VK_KEY_Z, MAPVK_VK_TO_VSC, lastInputLocale), false), false);
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
            auto map_result = MapVirtualKeyEx(nk.vk_code, MAPVK_VK_TO_VSC, lastInputLocale);
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
        if (configSendKeyMode == SendKeyMode.FAKE_NATIVE && standaloneModeActive) {
            sendUTF16OrKeyCombo(nk.char_code, down);
        } else {
            sendUTF16(nk.char_code, down);
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

bool getCapslockState() nothrow {
    bool state = GetKeyState(VK_CAPITAL) & 0x0001;
    return state;
}

void setCapslockState(bool state) nothrow {
    if (getCapslockState() != state) {
        sendVK(VK_CAPITAL, Scancode(0, false), true);
        sendVK(VK_CAPITAL, Scancode(0, false), false);
    }
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

uint previousPatchedLayer = 1;
uint activeLayer = 1;

// when we press a VK, store what NeoKey we send so that we can release it correctly later
NeoKey[Scancode] heldKeys;

NeoLayout *activeLayout;

// should we take over all layers? activated when standaloneMode is true in the config file and the currently selected native layout is not Neo related
bool standaloneModeActive;

// the last event was a dual state numpad key up with held shift key, eat the next shift down
bool expectFakeShiftDown;


bool setActiveLayout(NeoLayout *newLayout) nothrow @nogc {
    bool changed = newLayout != activeLayout;
    activeLayout = newLayout;
    return changed;
}


void resetHookStates() nothrow {
    // Reset all stored states that might lead to unwanted locks
    leftShiftDown = false;
    rightShiftDown = false;
    leftMod3Down = false;
    rightMod3Down = false;
    leftMod4Down = false;
    rightMod4Down = false;

    capslock = false;
    mod4Lock = false;

    setCapslockState(false);
    setKanaState(false);
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

    // We want Numlock to be always on, because some apps (built on WinUI, see #32) misinterpret VK_NUMPADx events if Numlock is disabled
    // However, this means we have to deal with fake shift events on Numpad layer 2 (#15)
    // On some notebooks with a native Numpad layer on the main keyboard we shouldn't do this, because they
    // then always get numbers instead of letters.
    if (configAutoNumlock) {
        setNumlockState(true);
    }

    // When Numlock is enabled, pressing Shift and a "dual state" numpad key generates fake key events to temporarily lift
    // and repress the active shift key. Fake Shift key ups are always marked as such with a special scancode, the
    // corresponding down events sometimes are and sometimes are not (seems to have something to do with whether
    // multiple numpad keys are pressed simultaneously). Here's the strategy:
    // - eat all shift key events marked with the fake scancode
    // - on dual state numpad key up with real held shift key, prime the hook to expect a shift key down as the next event
    // - if we are primed for a shift key down and get one, eat that. otherwise release the primed state
    if (expectFakeShiftDown) {
        if (down && (vk == VKEY.VK_LSHIFT || vk == VKEY.VK_RSHIFT)) {
            return true;
        }
        expectFakeShiftDown = false;
    }

    if (scan.scan == SC_FAKE_LSHIFT || scan.scan == SC_FAKE_RSHIFT) {
        return true;
    }

    if (isDualStateNumpadKey && !down && (leftShiftDown || rightShiftDown)) {
        expectFakeShiftDown = true;
    }

    // Disable fake LCtrl on physical AltGr key, as we use that for Mod4.
    // In case of an injected AltGr, the fake LCtrl is also marked as injected and passed through further above
    if (scan.scan == SC_FAKE_LCTRL) {
        return true;  // Eat event
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
    bool newCapslock = getCapslockState();
    bool capslockChanged = capslock != newCapslock;
    capslock = newCapslock;

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
    }  else if (shiftDown != (capslock && isCapslockable(scan))) {
        // Shift layer is set if EITHER Shift is pressed OR Capslock is enabled (and the char is capslockable).
        // In other cases (no Shift pressed, or both Shift and Capslock) the layer remains at 1.
        layer = 2;
    }

    if (mod4Lock) {
        // switch back to layer 1 while holding mod 4
        // EXCEPT if we are in extension mode and "filterNeoModifiers" is false
        // in that case we stay on layer 4, because the "real" M4 event interferes with layer 1 keys
        if (mod4Down && (configFilterNeoModifiers || standaloneModeActive)) {
            layer = 1;
        } else {
            layer = 4;
        }
    }

    uint oskLayer = layer;
    // Simplify capslock logic for OSK
    if (capslock && (oskLayer == 1 || oskLayer == 2)) {
        if (shiftDown) {
            oskLayer = 2;
        } else {
            oskLayer = 1;
        }
    }

    // Update OSK if necessary
    if (oskLayer != activeLayer || capslockChanged) {
        // Store globally for OSK
        activeLayer = oskLayer;
        updateOSKAsync();
    }

    // Toggle OSK on M3+F1
    if (vk == VK_F1 && down && mod3Down) {
        toggleOSK();
        return true;  // Eat F1
    }

    // We want to treat layers 1 and 2 the same in terms of checking whether we switched
    // This is because pressing or releasing shift should not send a keyup for all held keys
    // (where as it should for keys from all other layers)
    uint patchedLayer = layer;
    if (patchedLayer == 2) {
        patchedLayer = 1;
    }
    bool changedLayer = patchedLayer != previousPatchedLayer;
    previousPatchedLayer = patchedLayer;

    // if we switched layers release all currently held keys
    if (changedLayer) {
        foreach (entry; heldKeys.byKeyValue()) {
            sendNeoKey(entry.value, entry.key, false);
        }
        heldKeys.clear();
    }

    // immediately eat M3 and M4 keys
    // the events are filtered if we are in standalone mode ore filterNeoModifiers is true
    // if we are in extension mode and filterNeoModifiers is false, let these events pass through
    if (isNeoModifier) {
        return standaloneModeActive || configFilterNeoModifiers;
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

    // not very pretty hack: if "filterNeoModifiers" is false, we only want to eat and replace navigation
    // keys on layer 4 that don't work using kbdneo alone. for efficiency's sake we do a hardcoded check
    // against those scancodes.
    bool isLayer4NavKey = layer == 4 && (
        scan == Scancode(0x09, false) ||
        scan == Scancode(0x10, false) || scan == Scancode(0x11, false) || scan == Scancode(0x12, false) || scan == Scancode(0x13, false) || scan == Scancode(0x14, false) ||
        scan == Scancode(0x1E, false) || scan == Scancode(0x1F, false) || scan == Scancode(0x20, false) || scan == Scancode(0x21, false) || scan == Scancode(0x22, false) ||
        scan == Scancode(0x2C, false) || scan == Scancode(0x2D, false) || scan == Scancode(0x2E, false) || scan == Scancode(0x2F, false) || scan == Scancode(0x30, false)
    );


    if (down) {
        auto composeResult = compose(nk);

        if (composeResult.type == ComposeResultType.PASS) {
            heldKeys[scan] = nk;

            // We eat and replace keys under the following conditions:
            // - Eat every key in standalone mode
            // - Eat every numpad key (because they are not mapped according to spec in kbdneo)
            // - For the extension mode, it depends on the config option "filterNeoModifiers"
            //   - if true, eat every key on layers 3 and above
            //   - if false, don't eat keys and instead leave the translation of those layers to kbdneo
            //     except the navigation keys on layer 4 that are missing in kbdneo
            //   - also eat every key if mod 4 lock is active, because that isn't handled in kbdneo
            if (standaloneModeActive || isNumpadKey || (configFilterNeoModifiers && layer >= 3) || isLayer4NavKey || (mod4Lock && !mod4Down)) {
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
        if (standaloneModeActive || isNumpadKey || (configFilterNeoModifiers && layer >= 3) || isLayer4NavKey || (mod4Lock && !mod4Down)) {
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
