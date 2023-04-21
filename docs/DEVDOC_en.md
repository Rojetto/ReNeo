# Nomenclature
- **VK**/**VKEY**: A **Virtual-Key Code** (`uint`), documented [here](https://docs.microsoft.com/en-us/windows/win32/inputdev/virtual-key-codes). For letters and number keys, there are no names in the Microsoft header, which is why our enum has been supplemented with `VK_KEY_A` - `VK_KEY_Z` and `VK_KEY_0` - `VK_KEY_9`
- **Scancode**: Code that indicates the physical position of the key on the keyboard. [Reference here](https://kbdlayout.info/kbdgr/scancodes). Some keys are additionally distinguished by the **Extended Bit**, which we combine with the number in a `Scancode` struct. In `layouts.json`, the Extended Bit is marked with a `+`.
- **Keysym**: Numeric code (`uint`) from `keysymdef.h` that describes the meaning of a key (character or control key). In some cases, the *name* (`str`) of the code is also referred to as Keysym in the code. Used for Compose, as the Compose definitions in XCompose format use these key designations.
- **Neo-Modifier**: Mod3, Mod4, ...
- **NeoKey**: An entry in the keymap in `layouts.json`. Assigns a desired function to a key on a certain level. This can either be a specific character (**Char-Mapping**) or a control key (**VK-Mapping**).

# Basic Principle
The core of the program is the logic in the `keyboardHook` function. Roughly summarized, the following steps are executed in sequence.

## Filter unwanted events
We ignore Unicode events (`VK_PACKET`) as well as all events where the `injected` flag is set. These are probably coming from us anyway and should not end up in a loop.

In addition, we actively filter out fake events inserted by AltGr or the numeric keypad from the keyboard stack.

## Update modifier states
Sending native key combinations for special characters, arbitrarily mappable modifiers, and VK mappings with modifiers on arbitrary levels has made their handling increasingly complex. The current implementation aims to move away from a complex state machine with many individual flags and special cases and is based on the following conceptual model.

Which **modifiers** exist and where they are located on the keyboard is defined in `"modifiers"` in the layout. This covers both the **native modifiers** Shift, Ctrl, and Alt (in left and right variants) as well as the **Neo-Modifiers** Mod3, Mod4 (left and right), and higher (without left/right).

The **natural modifier state** describes which of these modifiers are currently being pressed by physical keys. This is complicated somewhat by the fact that, in principle, multiple physical keys can press the same modifier. If multiple keys hold the same modifier, we want to "release" the modifier only when the last physical key is released.

For each modifier type, it is stored which scancodes currently press this modifier. In a *Modifier-Down-Event*, the corresponding scancode is added to this data structure and the correct modifier event is passed through or sent. In principle, programs should only see *native modifiers*, *Neo-Modifiers* are filtered and their state is only handled internally. In a *Modifier-Up-Event*, the scancode is removed from the data structure again. Only if this key was the last one holding this modifier, an Up-Event for programs is generated (including forced modifiers, see below).

## Determine current level

Based on the **natural modifier state**, the current level is determined. The levels in `"layers"` are tested one after the other, and the first matching one is adopted.

In addition, there is the logic for Capslock and Mod4-Lock. Due to the many special cases, this logic is hardcoded and cannot be adapted in the layout.

With the current level and the pressed scancode, the NeoKey is then derived from the mapping.

## Compose

The entry point to the Compose module is the `compose` function, which is passed the current NeoKey for each key press. The core of the module is the **Compose tree**, whose branches are then followed during a Compose sequence. Depending on the resulting Compose state, the function responds with a Compose state. Thus, the keypress is either passed through unchanged in the Hook function, swallowed (because it is part of a Compose sequence), or replaced by the Compose result at the end of a Compose sequence.

## Sending key events

Depending on the mapping type (VK or Char) and mode, different events are generated.

VK mappings are always implemented as VK events. The scancode is obtained from a lookup in the native layout.

Char mappings are realized as Unicode events in extension mode. In standalone mode, however, a key combination that produces the desired character is searched for in the native layout, and this combination is sent. If the character does not exist natively, a Unicode event is used as a fallback.

VK mappings can force some or all of the *native modifiers* on or off with `"mods"`. The **forced modifier state** describes which modifiers are currently being forced to which value. The unspecified modifiers are not changed. The same mechanism also works for native key combinations for special characters in Char mappings.

The forced state is stored in a global variable between key presses. When a Down event of a key that may force new modifier states occurs, it must be determined with which minimal set of modifier events one can transition from one state to the other.

First, the natural state is combined with the previous (old) forced state to obtain the previous **resulting modifier state**. This is the state as seen by other programs.

```
                        LShift         LCtrl          LAlt
  natural               1              0              0
+ old forced                                          1         (LShift and LCtrl were irrelevant)
= old resulting         1              0              1
```

Equivalently, the new resulting state is obtained with the (new) forced state of the currently pressed key.

```
                        LShift         LCtrl          LAlt
  natural               1              0              0
+ new forced            1              1              0
= new resulting         1              1              0
```

Comparing the two resulting states (old and new) makes it clear which modifier events need to be sent to transition from old to new.

```
                        LShift         LCtrl          LAlt
old resulting           1              0              1
new resulting           1              1              0
-> Necessary events                    Down           Up
```

For an Up event, we generally want to reset the forced modifiers to the natural state. However, this only applies if the Up event belongs to the key that is the originator of the current forced state, otherwise the state is maintained.

# Insights and Workarounds
## Numpad
### Numlock State
In principle, Numlock works similarly to Capslock; the status can be queried and toggled with `VK_NUMLOCK`, and the keyboard LED displays the current status. *Actually*, the Numlock state doesn't matter to us, as Numlock as a concept does not exist in Neo. The numpad is also subject to the normal layer principle.

However, applications behave differently in practice. Most programs generate the corresponding number for a `VK_NUMPADx` event, regardless of the current state of Numlock. [WinUI applications require Numlock to be enabled, otherwise they only move the text cursor](https://github.com/microsoft/microsoft-ui-xaml/issues/5008).

**Workaround**: By default, we automatically enable Numlock.

This is annoying for some laptops that have a number pad *in the main field* activated via Numlock. Specifically, this has occurred on a Dell device. In this case, `"autoNumlock": false` can be used to disable the automatic activation of Numlock (with the expected limitations).

### Numlock Key
Strange things happen when you want to remap the Numlock key by filtering out its events. The LED does not change, but the internal state does.

**Workaround**: [Inspired by AHK](https://github.com/Lexikos/AutoHotkey_L/blob/master/source/hook.cpp#L2027), we internally press Numlock a few times to resolve the strange state.

### Shift and Numpad
When Numlock is enabled, special behavior occurs when pressing Shift *together* with a "**dual state**" numpad key. This specifically affects number keys 0-9 and the comma key. In this case, the driver stack inserts a **Fake-Shift** event to release the currently held Shift key and press it again afterward. These fake events do not have the `injected` flag set and are *sometimes* marked with the fake scancode `0x22A` (LShift) or `0x236` (RShift).

**Workaround**: We generally filter events with fake scancodes. For the affected "dual state" numpad keys, we also internally set a flag for key events to expect a Shift event next and filter it out accordingly. If it doesn't come (because Numlock is disabled or the event has already been filtered out based on the fake scancode), the flag is reset.

## AltGr
Internally, there is no "AltGr" key; instead, it is called "RAlt". In European layouts, however, the driver is configured so that pressing the key also sends an "LCtrl" event in addition to "RAlt" if LCtrl is not already pressed. This **Fake-LCtrl** is marked with the *fake scancode* `0x21D`, but not with the `injected` flag.

If you inject an RAlt yourself, the Windows stack automatically adds a Fake-LCtrl. In this case, *under Windows 10, the Fake-LCtrl is marked with the `injected` flag, while under Windows 7, it is not*.

Most applications generate the desired characters with LCtrl+LAlt. However, some only accept LCtrl+RAlt for special characters (e.g., *PuTTY*).

**Workaround**: For Mod4, we generally filter RAlt, but also all Fake-LCtrl events, identified by the fake scancode.

To generate special characters with native key combinations, we send both RAlt and LCtrl events for AltGr characters. We want to prevent the keyboard stack from automatically injecting Fake-LCtrl events, so the order matters here: LCtrl↓ RAlt↓ Key↓ Key↑ RAlt↑ LCtrl↑.

## Neo-Modifiers
GTK and Qt programs do not like modifiers other than Shift, Ctrl, Alt and behave strangely. The Telegram app is suitable for testing. If you use pure *kbdneo* there, [the next key event is completely swallowed after Mod3](https://git.neo-layout.org/neo/neo-layout/issues/510).

**Workaround**: In extension mode, we completely filter out Neo-Modifier events and instead send the desired keys directly on levels 3 and higher. Characters on these higher levels are then always Unicode packets.

If you actually want to let Neo-Modifier events through to programs, this behavior can be adjusted with `"filterNeoModifiers"` in the config.

## Capslock
### Capslock State
Using `VK_CAPITAL`, the current Capslock state can be read (`GetKeyState`) and set with key events. The current state is always displayed with the Capslock LED.

To ensure the Capslock LED is correct, we always toggle the actual Capslock state with Double-Shift. The letter keys are implemented as VK mapping and are then natively converted to uppercase letters.

### Capslockable

Not all keys should be affected by Capslock. On the Neo side, it's only the letter keys. The keys that should switch to the second level with Capslock are referred to as **capslockable** and are defined in `layouts.json`.

Conversely, not all keys are affected by Capslock in the native layout. The native driver determines which keys are affected.

**Workaround**: In `sendUTF16OrKeyCombo`, we use `ToUnicodeEx` to unlock the native driver with active Capslock, checking whether the next key will be affected by it. Depending on this, Shift must be additionally pressed or released.

## Dead Keys
### Dead Keys in the Native Driver
Native keyboard drivers support arbitrarily long dead key sequences. Typically, programs see these keys as `WM_KEYDOWN` and `WM_KEYUP`, and the window procedure turns them into `WM_DEADCHAR`. Most programs, however, do not process these events but wait for a `WM_CHAR` with the fully combined character to arrive at the end of the sequence.

In *kbdneo*, only a small fraction of the Compose sequences are defined. Also, [the Compose key `M3+Tab` still reaches programs](https://git.neo-layout.org/neo/neo-layout/issues/397).

**Workaround**: As soon as ReNeo recognizes the beginning of a Compose sequence, the corresponding key events are filtered out, and internally the Compose tree is followed until the end of the sequence is reached. Then, only the finished character(s) are sent as (a sequence of) Unicode packets.

### Identifying Dead Keys
In Standalone mode, we try to find the desired characters with `VkKeyScanEx` in the native layout and implement them as native key combinations. However, this is problematic for keys like the backtick "`" or the circumflex "^" on level 3. These keys should immediately generate a character but are often present as dead keys in native layouts. The exception is the DE-CH layout, where the circumflex is not a dead key.

**Workaround**: With `ToUnicodeEx`, it is possible to check whether the found key actually generates a character immediately. If not, the character is realized with a Unicode packet. Calling this function changes the internal state of the Windows driver stack. If we find a dead key, we need to call the function again to reset the state.

## Native Layouts
### Detecting Layout Changes
We want to detect layout changes in Windows in order to automatically switch between Extension mode and Standalone mode, or to (de)activate ReNeo. Unfortunately, there are no direct global events for this.

**Workaround**: We register a hook to listen for window changes. When the window has changed, we check *on the next key press* the current layout with `GetKeyboardLayout`. If you change the layout with Win+Space, Ctrl+Shift, or Alt+Shift, it happens immediately since the popup with the layout selection is considered a window change. If you use Shift+Ctrl or Shift+Alt instead, the hook is not triggered, and you need to manually switch windows for the hook to activate.

### The Console
In certain terminals, such as the classic console, `GetKeyboardLayout` returns `null` for the console thread. Calls like `VkKeyScan` also return incorrect results in these windows, as internally some strange legacy layout is assumed.

**Workaround**: We cache the last seen "meaningful" layout and ignore layout changes when the new layout is `null`. For calls like `VkKeyScan`, we use the `VkKeyScanEx` variant and explicitly pass the cached, meaningful layout.
