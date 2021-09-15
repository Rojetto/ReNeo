module reneo;

import std.stdio;
import std.utf;
import std.regex;
import std.conv;
import std.path;
import std.format;
import std.array;
import std.datetime.systime;

import core.sys.windows.windows;

import mapping;
import composer;
import app : configAutoNumlock, configFilterNeoModifiers, updateOSKAsync, toggleOSK, lastInputLocale;

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

Scancode[Modifier] SCANCODE_BY_MODIFIER;

version(FileLogging) {
    File logFile;
}

static this() {
    SCANCODE_BY_MODIFIER = [
        Modifier.LSHIFT: Scancode(0x2A, false),
        Modifier.RSHIFT: Scancode(0x36, false),
        Modifier.LCTRL: Scancode(0x1D, false),
        Modifier.RCTRL: Scancode(0x1D, true),
        Modifier.LALT: Scancode(0x38, false),
        Modifier.RALT: Scancode(0x38, true)
    ];

    version(FileLogging) {
        logFile = File("reneo_log.txt", "a+");
    }
}

void debug_writeln(T...)(T args) nothrow {
    debug {
        writeln(args);
    }

    version(FileLogging) {
        try {
        auto currTime = Clock.currTime();
        string timeString = format("%04d-%02d-%02d %02d:%02d:%02d.%03d ", currTime.year(), currTime.month(), currTime.day(), currTime.hour(), currTime.minute(), currTime.second(), cast(int) currTime.fracSecs().total!"msecs");
        logFile.writeln(timeString, args);
        logFile.flush();  // flush immediately in case we crash
        } catch (Exception e) {}
    }
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
    // for some reason we must set the 'extended' flag for these keys, otherwise they won't work correctly in combination with Shift (?)
    scan.extended |= vk == VK_INSERT || vk == VK_DELETE || vk == VK_HOME || vk == VK_END || vk == VK_PRIOR || vk == VK_NEXT || vk == VK_UP || vk == VK_DOWN || vk == VK_LEFT || vk == VK_RIGHT || vk == VK_DIVIDE;
    auto inputStruct = buildInputStruct(vk, scan, down);

    SendInput(1, &inputStruct, INPUT.sizeof);
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

const REAL_MODIFIERS = [Modifier.LSHIFT, Modifier.RSHIFT, Modifier.LCTRL, Modifier.RCTRL, Modifier.LALT, Modifier.RALT];

void sendVKWithModifiers(uint vk, Scancode scan, PartialModifierState newForcedModifiers, bool down) nothrow {
    // Send VK and necessary modifiers, so that the forced modifiers ("newForcedModifiers") are in desired state.
    // Also store forced modifier state globally so that we know the "resulting modifier state"
    // and only need to send the minimal modifier difference for the next keypress.

    // Determine the "resulting" modifier states as they appear to applications before and after applying
    // this VKs forced modifiers
    PartialModifierState oldResultingModStates;
    PartialModifierState newResultingModStates;

    foreach (mod; REAL_MODIFIERS) {
        bool modState = isModifierHeld(mod);

        bool oldModState = modState;
        if (mod in currentForcedModifiers) {
            oldModState = currentForcedModifiers[mod];
        }
        oldResultingModStates[mod] = oldModState;

        bool newModState = modState;
        if (mod in newForcedModifiers) {
            newModState = newForcedModifiers[mod];
        }
        newResultingModStates[mod] = newModState;
    }

    // Up and down separately, so that we can easily insert elements at the front and back
    // of both lists. In the end we first send all up events, then all down events.
    INPUT[] upInputs;
    INPUT[] downInputs;

    foreach (mod; oldResultingModStates.byKey) {
        bool oldModState = oldResultingModStates[mod];
        bool newModState = newResultingModStates[mod];

        if (oldModState && !newModState) {
            // up event
            auto inputStruct = buildInputStruct(mod, SCANCODE_BY_MODIFIER[mod], false);

            if (mod == Modifier.RALT) {
                // release RAlt first in case of LCtrl+RAlt combo
                try { upInputs.insertInPlace(0, inputStruct); } catch (Exception e) {}
            } else {
                upInputs ~= inputStruct;
            }
        } else if (!oldModState && newModState) {
            // down event
            auto inputStruct = buildInputStruct(mod, SCANCODE_BY_MODIFIER[mod], true);

            if (mod == Modifier.LCTRL) {
                // press LCtrl first in case of LCtrl+RAlt combo
                try { downInputs.insertInPlace(0, inputStruct); } catch (Exception e) {}
            } else {
                downInputs ~= inputStruct;
            }
        }
    }

    currentForcedModifiers = newForcedModifiers;

    // for some reason we must set the 'extended' flag for these keys, otherwise they won't work correctly in combination with Shift (?)
    scan.extended |= vk == VK_INSERT || vk == VK_DELETE || vk == VK_HOME || vk == VK_END || vk == VK_PRIOR || vk == VK_NEXT || vk == VK_UP || vk == VK_DOWN || vk == VK_LEFT || vk == VK_RIGHT || vk == VK_DIVIDE;
    auto mainKeyStruct = buildInputStruct(vk, scan, down);

    if (down) {
        downInputs ~= mainKeyStruct;
    } else {
        try { upInputs.insertInPlace(0, mainKeyStruct); } catch (Exception e) {}
    }

    upInputs ~= downInputs;
    SendInput(cast(uint) upInputs.length, upInputs.ptr, INPUT.sizeof);
}

void sendUTF16OrKeyCombo(wchar unicode_char, bool down) nothrow {
    /// Send a native key combo if there is one in the current layout, otherwise send unicode directly
    debug {
        try {
            debug_writeln(format("Trying to send %s (0x%04X) ...", unicode_char, to!int(unicode_char)));
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
    
    auto unicodeTranslationResult = ToUnicodeEx(vk, 0, kb.ptr, buf.ptr, 4, 0, lastInputLocale);
    if (unicodeTranslationResult == -1) {
        debug_writeln("Standard key combination results in a dead key, sending VK packet instead.");
        // The same dead key needs to be queried again, because ToUnicode() inserts the dead key (state)
        // into the queue, while anothèr call consumes the dead key.
        // See https://github.com/Lexikos/AutoHotkey_L/blob/master/source/hook.cpp#L2597
        ToUnicodeEx(vk, 0, kb.ptr, buf.ptr, 4, 0, lastInputLocale);
        sendUTF16(unicode_char, down);
        return;
    } else if (unicodeTranslationResult == 0) {
        debug_writeln("Key combination does not exist natively, sending VK packet instead.");
        sendUTF16(unicode_char, down);
        return;
    } else if (buf[0] != unicode_char) {
        debug_writeln("Key combination does not produce desired character, sending VK packet instead.");
        sendUTF16(unicode_char, down);
        return;
    }

    // The native capslockable state can be queried indirectly by reversely generating the Unicode char with a given
    // keyboard state. If the result of toUnicode() is different from the expected char (and capslock
    // is active), the key is capslockable.
    // The other way round, if a key is not capslockable, the Capslock state must not be considered.

    // This flag is set to false if Capslock is not active. This is because the capslockable state
    // can only be checked when Capslock is active (and only then has any influence).
    bool nativeCapslockable = (buf[0] != unicode_char) && capslock;

    if (nativeCapslockable) {
        shift = !shift; // Don't press Shift if Capslock is on or temporarily disable Capslock by pressing Shift
    }

    auto scan = Scancode(MapVirtualKeyEx(vk, MAPVK_VK_TO_VSC, lastInputLocale));
    
    PartialModifierState mods;

    if (down) {
        // Always force Shift to correct value
        if (shift) {
            // If we already physically hold a shift key, use that one to prevent unnecessary key events.
            // Default to left shift.

            if (isModifierHeld(Modifier.RSHIFT)) {
                mods[Modifier.RSHIFT] = true;
            } else {
                mods[Modifier.LSHIFT] = true;
            }
        } else {
            mods[Modifier.LSHIFT] = false;
            mods[Modifier.RSHIFT] = false;
        }

        // Alt is assumed to always be AltGr (RAlt+LCtrl)
        // If character doesn't need AltGr, leave Alt and Ctrl in natural state (pressed or not)
        // so that shortcuts like Ctrl+S work normally
        if (alt) {
            mods[Modifier.LALT] = false;
            mods[Modifier.RALT] = true;
            mods[Modifier.LCTRL] = true;
            mods[Modifier.RCTRL] = false;
        }
    }

    sendVKWithModifiers(vk, scan, mods, down);
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

INPUT buildInputStruct(uint vk, Scancode scan, bool down) nothrow {
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
    return input_struct;
}

void sendNeoKey(NeoKey nk, Scancode realScan, bool down) nothrow {
    if (down) {
        lastNeoKey = nk;
    }

    // Special cases for weird mappings
    if (nk.keysym == KEYSYM_VOID && nk.vk_code == VKEY.VK_LBUTTON) {
        sendMouseClick(down);
        return;
    }

    if (nk.keytype == NeoKeyType.VKEY) {
        Scancode scan = realScan;
        auto map_result = MapVirtualKeyEx(nk.vk_code, MAPVK_VK_TO_VSC, lastInputLocale);
        if (map_result) {
            // vk does exist in native layout, use the fake native scan code
            scan.extended = false;
            scan.scan = map_result;
        }

        PartialModifierState newForcedModifiers;
        if (down) {
            newForcedModifiers = nk.modifiers;
        } else if (nk != lastNeoKey) {
            // this is an up event for a key other than the one that forced the current modifiers
            // so we leave them as is
            newForcedModifiers = currentForcedModifiers;
            // if this *was* an up event for the key that forced the current modifiers, we would
            // want to reset them (which happens with a zero-initialized value for "newForcedModifiers")
        }
        sendVKWithModifiers(nk.vk_code, scan, newForcedModifiers, down);
    } else {
        if (standaloneModeActive) {
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

// For each modifier store the scancodes that are currently holding it down. Because there is no
// built-in set type, we use a void[0][Scancode] type. Add a scancode with a[scan] = []; remove it with a.remove(scan).
// In contrast to bool[Scancode], void[0][Scancode] does not allocate space for the "values" of each element.
void[0][Scancode][Modifier] naturalHeldModifiers;

// Modifier states that are forced down or up by a currently held VK mapping or char mapping
PartialModifierState currentForcedModifiers;

bool capslock;
bool mod4Lock;

uint previousPatchedLayer = 1;
uint activeLayer = 1;

// when we press a VK, store what NeoKey we send so that we can release it correctly later
NeoKey[Scancode] heldKeys;
// last key that was pressed. we only want to release forced modifiers when the key that
// forced them (the one pressed in the last down event) is released.
NeoKey lastNeoKey;

NeoLayout *activeLayout;

// should we take over all layers? activated when standaloneMode is true in the config file and the currently selected native layout is not Neo related
bool standaloneModeActive;

// the last event was a dual state numpad key up with held shift key, eat the next shift down
bool expectFakeShiftDown;


bool isModifierHeld(Modifier mod) nothrow {
    // refers to "natural modifier state"
    return (mod in naturalHeldModifiers) && (naturalHeldModifiers[mod].length > 0);
}


bool setActiveLayout(NeoLayout *newLayout) nothrow @nogc {
    bool changed = newLayout != activeLayout;
    activeLayout = newLayout;
    return changed;
}


void resetHookStates() nothrow {
    // Reset all stored states that might lead to unwanted locks
    naturalHeldModifiers.clear();

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
            debug_writeln(injected_text ~ down_text ~ alt_text ~ extended_text ~ format("| Scan 0x%04X | %s (0x%02X)", scan.scan, to!string(vk), vk));
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

    if (isDualStateNumpadKey && !down && (isModifierHeld(Modifier.LSHIFT) || isModifierHeld(Modifier.RSHIFT))) {
        expectFakeShiftDown = true;
    }

    // Disable fake LCtrl on physical AltGr key, as we use that for Mod4.
    // In case of an injected AltGr, the fake LCtrl is also marked as injected and passed through further above
    if (scan.scan == SC_FAKE_LCTRL) {
        return true;  // Eat event
    }

    // is this key mapped to a modifier?
    bool isModifier;
    // should we eat this modifier key event? We don't return immediately here because we want to
    // update the current layer for the OSK as well as handle Capslock and Mod4-Lock further down
    // the line. Instead we return after all of that is done.
    bool shouldEatModifier;

    // update stored modifier key states and send modifier keys
    if (scan in activeLayout.modifiers) {
        auto mod = activeLayout.modifiers[scan];
        isModifier = true;
        bool isNeoModifier = mod >= 0x100;

        // handle capslock and mod4 lock
        if (down) {
            if (mod == Modifier.LSHIFT && !isModifierHeld(Modifier.LSHIFT) && isModifierHeld(Modifier.RSHIFT) ||
                mod == Modifier.RSHIFT && !isModifierHeld(Modifier.RSHIFT) && isModifierHeld(Modifier.LSHIFT)) {
                sendVK(VK_CAPITAL, scanCapslock, true);
                sendVK(VK_CAPITAL, scanCapslock, false);
            }

            if (mod == Modifier.LMOD4 && !isModifierHeld(Modifier.LMOD4) && isModifierHeld(Modifier.RMOD4) ||
                mod == Modifier.RMOD4 && !isModifierHeld(Modifier.RMOD4) && isModifierHeld(Modifier.LMOD4)) {
                mod4Lock = !mod4Lock;
            }
        }

        if (!(mod in naturalHeldModifiers)) {
            naturalHeldModifiers[mod] = null;
        }

        // In standalone mode, fully replace every modifier event
        // In extension mode, only eat neo modifiers (and only if "filterNeoModifiers" is enabled), let
        // all other modifier events pass
        shouldEatModifier = standaloneModeActive || (isNeoModifier && configFilterNeoModifiers);
        // We should only send our own event if we ate the original and this is a native modifier
        bool shouldSendModifier = shouldEatModifier && !isNeoModifier;
        
        if (down) {
            // Add scancode to set for this modifier
            naturalHeldModifiers[mod][scan] = [];

            if (shouldSendModifier) {
                sendVK(mod, SCANCODE_BY_MODIFIER[mod], true);
            }
        } else {
            // Remove scancode from set
            naturalHeldModifiers[mod].remove(scan);

            // Only send up event if this was the last key holding this modifier and the modifier isn't forced down by some mapping
            if (shouldSendModifier && !(isModifierHeld(mod) || mod in currentForcedModifiers && currentForcedModifiers[mod])) {
                sendVK(mod, SCANCODE_BY_MODIFIER[mod], false);
            }
        }
    }

    // is capslock active?
    bool newCapslock = getCapslockState();
    bool capslockChanged = capslock != newCapslock;
    capslock = newCapslock;


    // determine the layer we are currently on
    uint layer = 1;  // first layer is 1!!

    // test all defined layers and choose first matching
    foreach (i, layerModState; activeLayout.layers) {
        bool allMatch = true;

        foreach (mod; layerModState.byKey) { // we can't do (mod, modState; layerModState) because _aaApply2 is not nothrow 🙄
            bool requiredModState = layerModState[mod];
            // "mod ^ 1" converts left to right variant and vice versa
            if (requiredModState && !(isModifierHeld(mod) || isModifierHeld(cast(Modifier) (mod ^ 1))) ||
                !requiredModState && (isModifierHeld(mod) || isModifierHeld(cast(Modifier) (mod ^ 1)))) {
                allMatch = false;
                break;
            }
        }

        if (allMatch) {
            layer = cast(uint) i + 1;
            break;
        }
    }

    bool shiftDown = isModifierHeld(Modifier.LSHIFT) || isModifierHeld(Modifier.RSHIFT);
    bool mod4Down = isModifierHeld(Modifier.LMOD4) || isModifierHeld(Modifier.RMOD4);

    // handle capslock
    if (capslock && isCapslockable(scan)) {
        if (shiftDown && layer == 2) {
            layer = 1;
        } else if (!shiftDown && layer == 1) {
            layer = 2;
        }
    }

    // handle mod4 lock
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
    if (vk == VK_F1 && down && (isModifierHeld(Modifier.LMOD3) || isModifierHeld(Modifier.RMOD3))) {
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

    if (isModifier) {
        return shouldEatModifier;
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
