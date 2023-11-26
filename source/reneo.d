module reneo;

import std.stdio;
import std.utf;
import std.regex;
import std.conv;
import std.path;
import std.format;
import std.array;
import std.datetime.systime;
import std.algorithm.mutation : remove;

import core.sys.windows.windows;

import mapping;
import composer;
import osk : updateOSKTransparency;
import app : configAutoNumlock, configEnableMod4Lock, configFilterNeoModifiers, configOneHandedModeMirrorKey, configOneHandedModeMirrorMap, updateOSKAsync, toggleOSK, toggleOneHandedMode, lastInputLocale;

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

void debugWriteln(T...)(T args) nothrow {
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

uint[string] keysymsByName;
uint[uint] keysymsByCodepoint;
uint[uint] codepointsByKeysym;
const KEYSYM_CODEPOINT_OFFSET = 0x01000000;

// Initializes list of keysyms by a given keysymdef.h from X.org project,
// see https://cgit.freedesktop.org/xorg/proto/x11proto/tree/keysymdef.h
void initKeysyms(string exeDir) {
    auto keysymfile = buildPath(exeDir, "keysymdef.h");
    debugWriteln("Initializing keysyms from ", keysymfile);
    // group 1: name, group 2: hex, group 3: unicode codepoint
    auto unicodePattern = r"^\#define XK_([a-zA-Z_0-9]+)\s+0x([0-9a-fA-F]+)\s*\/\*[ \(]U\+([0-9a-fA-F]{4,6}) (.*)[ \)]\*\/\s*$";
    // group 1: name, group 2: hex, group 3 and 4: comment stuff
    auto noUnicodePattern = r"^\#define XK_([a-zA-Z_0-9]+)\s+0x([0-9a-fA-F]+)\s*(\/\*\s*(.*)\s*\*\/)?\s*$";
    keysymsByName.clear();
    keysymsByCodepoint.clear();
    codepointsByKeysym.clear();

    File f = File(keysymfile, "r");
	while(!f.eof()) {
		string l = f.readln();
        try {
            if (auto m = matchFirst(l, unicodePattern)) {
                string keysymName = m[1];
                uint keyCode = to!uint(m[2], 16);
                uint codepoint = to!uint(m[3], 16);
                keysymsByName[keysymName] = keyCode;
                keysymsByCodepoint[codepoint] = keyCode;
                // for quick reverse search
                codepointsByKeysym[keyCode] = codepoint;
            } else if (auto m = matchFirst(l, noUnicodePattern)) {
                string keysymName = m[1];
                uint keyCode = to!uint(m[2], 16);
                keysymsByName[keysymName] = keyCode;
            }
        } catch (Exception e) {
            debugWriteln("Could not parse line '", l, "', skipping. Error: ", e.msg);
        }
	}
}

auto UNICODE_REGEX = regex(r"^U([0-9a-fA-F]+)$");

// Parse a string by a lookup in the initialized keysym tables, either by name
// or by codepoint. The latter works also for algorithmically defined strings
// in the form "U00A0" to "U10FFFF" which represent any possible Unicode
// character as hex value.
uint parseKeysym(string keysymStr) {
    if (uint *keysym = keysymStr in keysymsByName) {
        // The corresponding keysym is explicitly defined by the given name
        return *keysym;
    } else if (auto m = matchFirst(keysymStr, UNICODE_REGEX)) {
        uint codepoint = to!uint(m[1], 16);

        // Legacy keysyms for some Unicode values between 0x0100 and 0x30FF
        if (codepoint <= 0x30FF) {
            if (uint *keysym = codepoint in keysymsByCodepoint) {
                // If defined, return the legacy keysym value
                return *keysym;
            }
        }

        // Otherwise just return the keysym matching the codepoint with an offset
        return codepoint + KEYSYM_CODEPOINT_OFFSET;
    }

    debugWriteln("Keysym ", keysymStr, " not found.");

    return KEYSYM_VOID;
}

void sendVK(uint vk, Scancode scan, bool down) nothrow {
    // for some reason we must set the 'extended' flag for these keys, otherwise they won't work correctly in combination with Shift (?)
    scan.extended |= vk == VK_INSERT || vk == VK_DELETE || vk == VK_HOME || vk == VK_END || vk == VK_PRIOR || vk == VK_NEXT || vk == VK_UP || vk == VK_DOWN || vk == VK_LEFT || vk == VK_RIGHT || vk == VK_DIVIDE;
    auto inputStruct = buildInputStruct(vk, scan, down);

    SendInput(1, &inputStruct, INPUT.sizeof);
}

void sendUTF16(wchar unicodeChar, bool down) nothrow {
    INPUT inputStruct;
    inputStruct.type = INPUT_KEYBOARD;
    inputStruct.ki.wVk = 0;
    inputStruct.ki.wScan = unicodeChar;
    if (down) {
        inputStruct.ki.dwFlags = KEYEVENTF_UNICODE;
    } else {
        inputStruct.ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP;
    }

    SendInput(1, &inputStruct, INPUT.sizeof);
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

void sendUTF16OrKeyCombo(wchar unicodeChar, bool down) nothrow {
    /// Send a native key combo if there is one in the current layout, otherwise send unicode directly
    debug {
        try {
            debugWriteln(format("Trying to send %s (0x%04X) ...", unicodeChar, to!int(unicodeChar)));
        }
        catch (Exception e) {}
    }

    short result = VkKeyScanEx(unicodeChar, lastInputLocale);
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
        debugWriteln("No standard key combination found, sending VK packet instead.");
        sendUTF16(unicodeChar, down);
        return;
    }

    debug {
        try {
            auto shiftText = shift ? "(Shift) " : "        ";
            auto ctrlText  = ctrl  ? "(Ctrl)  " : "        ";
            auto altText   = alt   ? "(Alt)   " : "        ";
            auto kanaText  = kana  ? "(Kana)  " : "        ";
            auto mod5Text  = mod5  ? "(Mod5)  " : "        ";
            auto mod6Text  = mod6  ? "(Mod6)  " : "        ";
            debugWriteln("Key combination is " ~ to!string(cast(VKEY) vk) ~ " "
                ~ shiftText ~ ctrlText ~ altText ~ kanaText ~ mod5Text ~ mod6Text);
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
        debugWriteln("Standard key combination results in a dead key, sending VK packet instead.");
        // The same dead key needs to be queried again, because ToUnicode() inserts the dead key (state)
        // into the queue, while anothèr call consumes the dead key.
        // See https://github.com/Lexikos/AutoHotkey_L/blob/master/source/hook.cpp#L2597
        ToUnicodeEx(vk, 0, kb.ptr, buf.ptr, 4, 0, lastInputLocale);
        sendUTF16(unicodeChar, down);
        return;
    } else if (unicodeTranslationResult == 0) {
        debugWriteln("Key combination does not exist natively, sending VK packet instead.");
        sendUTF16(unicodeChar, down);
        return;
    } else if (buf[0] != unicodeChar) {
        debugWriteln("Key combination does not produce desired character, sending VK packet instead.");
        sendUTF16(unicodeChar, down);
        return;
    }

    // The native capslockable state can be queried indirectly by reversely generating the Unicode char with a given
    // keyboard state. If the result of toUnicode() is different from the expected char (and capslock
    // is active), the key is capslockable.
    // The other way round, if a key is not capslockable, the Capslock state must not be considered.

    // This flag is set to false if Capslock is not active. This is because the capslockable state
    // can only be checked when Capslock is active (and only then has any influence).
    bool nativeCapslockable = (buf[0] != unicodeChar) && capslock;

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
    INPUT inputStruct;
    inputStruct.type = INPUT_KEYBOARD;
    inputStruct.ki.wVk = cast(ushort) vk;
    inputStruct.ki.wScan = cast(ushort) scan.scan;
    if (!down) {
        inputStruct.ki.dwFlags = KEYEVENTF_KEYUP;
    }
    if (scan.extended) {
        inputStruct.ki.dwFlags |= KEYEVENTF_EXTENDEDKEY;
    }
    return inputStruct;
}

void sendNeoKey(NeoKey nk, Scancode realScan, bool down) nothrow {
    if (down) {
        lastNeoKey = nk;
    }

    // Special cases for weird mappings
    if (nk.keysym == KEYSYM_VOID && nk.vkCode == VKEY.VK_LBUTTON) {
        sendMouseClick(down);
        return;
    }

    if (nk.keytype == NeoKeyType.VKEY) {
        Scancode scan = realScan;
        auto mapResult = MapVirtualKeyEx(nk.vkCode, MAPVK_VK_TO_VSC, lastInputLocale);
        if (mapResult) {
            // vk does exist in native layout, use the fake native scan code
            scan.extended = false;
            scan.scan = mapResult;
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
        sendVKWithModifiers(nk.vkCode, scan, newForcedModifiers, down);
    } else {
        if (standaloneModeActive) {
            sendUTF16OrKeyCombo(nk.charCode, down);
        } else {
            sendUTF16(nk.charCode, down);
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

    INPUT inputStruct;
    inputStruct.type = INPUT_MOUSE;
    inputStruct.mi.dx = 0;
    inputStruct.mi.dy = 0;
    // If primary mouse button is swapped, use rightdown/rightup flags.
    DWORD dwFlags = down ? MOUSEEVENTF_LEFTDOWN : MOUSEEVENTF_LEFTUP;
    if (GetSystemMetrics(SM_SWAPBUTTON)) {
        dwFlags = dwFlags << 2;
    }
    inputStruct.mi.dwFlags = dwFlags;
    SendInput(1, &inputStruct, INPUT.sizeof);
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

// is one handed mode enabled?
bool oneHandedModeActive;
// is the mirror key (typically spacebar) currently being held?
bool mirrorKeyHeld;
// were any keys mirrored (pressed *and* released) while the mirror key was held?
bool eatMirrorKey;
// list of *original* scancodes of keys pressed while mirror key was held
Scancode[] primedOneHandedKeys;

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
    heldKeys.clear();
    currentForcedModifiers.clear();

    capslock = false;
    mod4Lock = false;

    setCapslockState(false);
    setKanaState(false);

    mirrorKeyHeld = false;
}


bool handleKeyEvent(Scancode scan, bool down) nothrow {
    // Called from the main keyboard hook. Sends key events depending on the current mode, layer and compose state,
    // updates modifier and layer states, and returns whether the original event should be eaten.

    // All Numpad keys including KP_Enter and Numlock
    bool isNumpadKey = (!scan.extended && scan.scan >= 0x47 && scan.scan <= 0x53) || scan == Scancode(0x35, true) || scan == Scancode(0x37, false) || scan == Scancode(0x1C, true) || scan == Scancode(0x45, true);

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
                if (configEnableMod4Lock || mod4Lock)  // always allow lock to be disabled
                    mod4Lock = !mod4Lock;
            }
        }

        if (!(mod in naturalHeldModifiers)) {
            naturalHeldModifiers[mod] = null;
        }

        // In standalone mode or one handed mode, fully replace every modifier event
        // In extension mode, only eat neo modifiers (and only if "filterNeoModifiers" is enabled), let
        // all other modifier events pass
        shouldEatModifier = standaloneModeActive || oneHandedModeActive || (isNeoModifier && configFilterNeoModifiers);
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
            // - Eat every key in standalone mode and one handed mode
            // - Eat every numpad key (because they are not mapped according to spec in kbdneo)
            // - For the extension mode, it depends on the config option "filterNeoModifiers"
            //   - if true, eat every key on layers 3 and above
            //   - if false, don't eat keys and instead leave the translation of those layers to kbdneo
            //     except the navigation keys on layer 4 that are missing in kbdneo
            //   - also eat every key if mod 4 lock is active, because that isn't handled in kbdneo
            if (standaloneModeActive || oneHandedModeActive || isNumpadKey || (configFilterNeoModifiers && layer >= 3) || isLayer4NavKey || (mod4Lock && !mod4Down)) {
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
        if (standaloneModeActive || oneHandedModeActive || isNumpadKey || (configFilterNeoModifiers && layer >= 3) || isLayer4NavKey || (mod4Lock && !mod4Down)) {
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


bool keyboardHook(WPARAM msgType, KBDLLHOOKSTRUCT msgStruct) nothrow {
    auto vk = cast(VKEY) msgStruct.vkCode;
    bool down = msgType == WM_KEYDOWN || msgType == WM_SYSKEYDOWN;
    auto scan = Scancode(cast(uint) msgStruct.scanCode, (msgStruct.flags & LLKHF_EXTENDED) > 0);
    bool altdown = (msgStruct.flags & LLKHF_ALTDOWN) > 0;
    bool injected = (msgStruct.flags & LLKHF_INJECTED) > 0;

    debug {
        auto injectedText = injected      ? "(injected) " : "           ";
        auto downText     = down          ? "(down) " : " (up)  ";
        auto altText      = altdown       ? "(Alt) " : "      ";
        auto extendedText = scan.extended ? "(Ext) " : "      ";

        try {
            debugWriteln(injectedText ~ downText ~ altText ~ extendedText ~ format("| Scan 0x%04X | %s (0x%02X)", scan.scan, to!string(vk), vk));
        } catch(Exception e) {}
    }

    // ignore all simulated keypresses
    if (vk == VKEY.VK_PACKET || injected) {
        return false;
    }

    // Numpad 0-9 and separator are dual-state Numpad keys:
    // scancode range 0x47–0x53 (without 0x4A and 0x4E), no extended scancode
    bool isDualStateNumpadKey = (!scan.extended && scan.scan >= 0x47 && scan.scan <= 0x53 && scan.scan != 0x4A && scan.scan != 0x4E);

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

    // Toggle OSK on M3+F1
    if (vk == VK_F1 && down && (isModifierHeld(Modifier.LMOD3) || isModifierHeld(Modifier.RMOD3))) {
        toggleOSK();
        return true;  // Eat F1
    }
    // Increase transparency of OSK on M3+F2
    if (vk == VK_F2 && down && (isModifierHeld(Modifier.LMOD3) || isModifierHeld(Modifier.RMOD3))) {
        updateOSKTransparency(-10);
        updateOSKAsync();
        return true;  // Eat F2
    }
    // Decrease transparency of OSK on M3+F2
    if (vk == VK_F3 && down && (isModifierHeld(Modifier.LMOD3) || isModifierHeld(Modifier.RMOD3))) {
        updateOSKTransparency(10);
        updateOSKAsync();
        return true;  // Eat F3
    }

    // Toggle one handed mode on M3+F10
    if (vk == VK_F10 && down && (isModifierHeld(Modifier.LMOD3) || isModifierHeld(Modifier.RMOD3))) {
        toggleOneHandedMode();
        return true;  // Eat F10
    }

    // Handle Numlock key, which would otherwise toggle Numlock state without changing the LED.
    // For more information see AutoHotkey: https://github.com/Lexikos/AutoHotkey_L/blob/master/source/hook.cpp#L2027
    // If key is not mapped in layout, let it pass unaffected
    if (vk == VKEY.VK_NUMLOCK && down && scan in activeLayout.map) {
        sendVK(VK_NUMLOCK, scanNumlock, false);
        sendVK(VK_NUMLOCK, scanNumlock, true);
        sendVK(VK_NUMLOCK, scanNumlock, false);
        sendVK(VK_NUMLOCK, scanNumlock, true);
    }

    // ---- One handed mode ----
    // The point of this whole state machine is to produce the following behaviour:
    // M - mirror key | A, B, ... - other keys | A' - key A mirrored | U - up | D - down
    
    // Case 1:   MD         MU                               ("unused" mirror key creates events on up)
    // Result 1:            MD MU

    // Case 2:   AD     MD     AU     MU                     (keys pressed before mirror key don't get mirrored)
    // Result 2: AD            AU     MD MU

    // Case 3:   MD    AD    AU         MU                   (keys pressed *and released* while mirror key is held are mirrored)
    // Result 3:             A'D A'U                         (also, mirror key does not create its own event)

    // Case 4:   MD    AD   BD    MU              AU   BU    (keys pressed but not released while mirror key is held create down 
    // Result 4:                  MD MU AD BD     AU   BU     events in correct order after mirror key up)
    
    if (oneHandedModeActive) {
        if (scan == configOneHandedModeMirrorKey) {
            mirrorKeyHeld = down;

            if (!down) {  // on mirror key up
                if (!eatMirrorKey) {
                    // mirror key wasn't "used" to mirror keys, so send its normal up and down events
                    handleKeyEvent(scan, true);
                    handleKeyEvent(scan, false);
                }

                eatMirrorKey = false;

                if (primedOneHandedKeys) {
                    // Some keys are still held, send those as unmirrored down events now (in order)
                    foreach (Scancode heldKey; primedOneHandedKeys) {
                        handleKeyEvent(heldKey, true);
                    }

                    primedOneHandedKeys = [];
                }
            }

            return true;
        } else if (mirrorKeyHeld && scan in configOneHandedModeMirrorMap) {
            int primedKeyIndex = -1;  // default: key not in primed list
            foreach (i, primedKey; primedOneHandedKeys) {  // find key in primed list
                if (primedKey == scan) {
                    primedKeyIndex = cast(int) i;
                    break;
                }
            }

            if (down) {
                if (primedKeyIndex == -1) {  // key not primed yet
                    primedOneHandedKeys ~= scan; // on down, only prime this key but don't send any events yet
                }

                return true;
            } else {
                if (primedKeyIndex >= 0) {  // key was primed
                    primedOneHandedKeys = primedOneHandedKeys.remove(primedKeyIndex);
                    // on up, send the mirrored down and up event
                    auto mirroredScan = configOneHandedModeMirrorMap[scan];
                    handleKeyEvent(mirroredScan, true);
                    handleKeyEvent(mirroredScan, false);

                    // mirror key was "used" while held, so don't send its original key later when it's released
                    eatMirrorKey = true;

                    return true;
                }
            }
        }
    }

    return handleKeyEvent(scan, down);
}
