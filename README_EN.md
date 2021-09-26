# ReNeo – The Neo keyboard layout family on Windows

ReNeo implements the [Neo keyboard layout](http://neo-layout.org/) and its relatives on Windows. There are two main modes of operation:
1. *standalone mode*: ReNeo replaces all key events of the native layout (likely QWERTZ or QWERTY) with the desired Neo layout. You only need to run the ReNeo executable on system startup.
2. *extension mode*: First, install a native Neo driver like [kbdneo](https://neo-layout.org/Einrichtung/kbdneo/). ReNeo then supplements all functions that can't be implemented in the native driver (capslock, navigation keys on layer 4, compose, ...).

![ReNeo on-screen keyboard layer 1](docs/osk_screenshot.png "ReNeo On-Screen keyboard")

## Installation

1. *optional*: Install [kbdneo](https://neo-layout.org/Einrichtung/kbdneo/) normally
2. Download [newest release](https://github.com/Rojetto/ReNeo/releases/latest) and unpack in a directory with write permissions, e.g. `C:\Users\[USER]\ReNeo`
3. Start `reneo.exe` oder add it to the autostart list. Use the tray icon to deactivate or quit the program.
4. *optional*: [Tweak `config.json`](#general-configuration) (generated on first start)

*Update*

Download new release and overwrite existing files with package contents. Because `config.json` isn't contained in the release package user settings are preserved.

*Uninstallation*

1. *optional*: Uninstall kbdneo according to Neo wiki tutorial
2. Delete ReNeo directory and remove executable from autostart

## Features

General:

- Supports the layouts *Neo*, *Bone*, *NeoQwertz*, *Mine*, *AdNW*, *KOY*, [*3l*](https://github.com/jackrosenthal/threelayout)
- Use tray menu to switch between layouts
- Capslock (both shift keys) and mod 4 lock (both mod 4 keys)
- **On-screen keyboard**: Toggle using tray menu or with shortcut `M3+F1`. Switches between layers as modifiers are pressed.
- *All* dead keys and compose combinations. These can be extended by users, all `.module` files in the `compose/` directory are loaded on startup.
- Special compose sequences
    - Unicode input: `♫uu[codepoint hex]<space>` inserts unicode characters, e.g. `♫uu1f574<space>` → 🕴
    - Roman numerals: `♫rn[zahl]<space>` for lower case, `♫RN[zahl]<space>` for upper case. Numbers must range between 1 and 3999. Example: `♫rn1970<space>` → ⅿⅽⅿⅼⅹⅹ, `♫RN1970<space>` → ⅯⅭⅯⅬⅩⅩ
- `Shift+Pause` de(activates) the program
- One-handed mode: If mode is enabled and space (default) is held, the whole keyboard is “mirored”. Toggle using tray menu or with shortcut `M3+F10`.
- Additional layouts can be added or modified in `layouts.json`.

As an extension to the native driver:

- Steuertasten auf Ebene 4
- Wird das native Layout als Neo-verwandt erkannt (`kbdneo.dll`, `kbdbone.dll`, `kbdgr2.dll`), schaltet ReNeo automatisch in den Erweiterungs-Modus. Umschalten zwischen Layouts ist ganz normal möglich.
- Verbesserte Kompatibilität mit Qt- und GTK-Anwendungen. Workaround für [diesen Bug](https://git.neo-layout.org/neo/neo-layout/issues/510).
- Compose-Taste `M3+Tab` sendet keinen Tab mehr an Anwendung. Workaround für [diesen Bug](https://git.neo-layout.org/neo/neo-layout/issues/397).

## Configuration

ReNeo can be configured with two files.

### General Configuration

`config.json` contains the following options:

- `"standaloneMode"`:
    - `true` (default): ReNeo replaces the native layout (e.g. QWERTY) with the selected Neo layout. If the native layout is already Neo-related, ReNeo won't change the layout and instead automatically switch to extension mode.
    - `false`: If the native layout is Neo-related, ReNeo will switch to extension mode. For all other layouts ReNeo deactivates automatically.
- `"standaloneLayout"`: Layout used for standalone mode. Can also be selected via the tray menu.
- `"language"`: Program language, `"german"` or `"english"`.
- `"osk"`:
    - `"numpad"`: Should on-screen keyboard show the numpad?
    - `"numberRow"`: Should on-screen keyboard show the number row?
    - `"theme"`: Color scheme for on-screen keyboard. `"Grey"` or `"NeoBlue"`
    - `"layout"`: `"iso"` or `"ansi"`
    - `"modifierNames"`: `"standard"` (M3, M4, ...) or `"three"` (Sym, Cur)
- `"hotkeys"`: Hotkeys various program functions. Examples: `"Ctrl+Alt+F5"`, `"Shift+Alt+Key_A"`. Allowed modifiers are `Shift`, `Ctrl`, `Alt`, `Win`. The main key must be a VK from [this enumeration](https://github.com/Rojetto/ReNeo/blob/5bd304a7c42c768ed45813095ab5fbc69103773c/source/mapping.d#L17) based on [this Win32 documentation](https://docs.microsoft.com/en-us/windows/win32/inputdev/virtual-key-codes). If a value is `null`, no global hotkey will be registered.
    - `"toggleActivation"`: Toggle ReNeo keyboard hook.
    - `"toggleOSK"`: Toggle on-screen keyboard. In addition to this hotkey, `M3+F1` always works.
    - `"toggleOneHandedMode"`: Toggle one-handed mode. Additionally, `M3+F10` always works.
- `"blacklist"`: List of programs for which ReNeo should be deactivated automatically (e.g. X server, remote clients or games). A *RegEx* can be set with which the window title is compared. *Example*: Windows containing "emacs" or "Virtual Machine Manager" in their title should deactivate ReNeo. The config then is
```
"blacklist": [
    {
        "windowTitle": "emacs"
    },
    {
        "windowTitle": "Virtual Machine Manager"
    }
]
```
- `"autoNumlock"`: Activate Numlock automatically? For optimal compatibility this should always be set to `true` if the keyboard has a real number pad. However, this may cause problems for laptops with a native number block located on the letter keys. In that case, disable this feature with `false`.
- `"filterNeoModifiers"`:
    - `true` (false): Key events for M3 and M4 are filtered in extension mode so that other programs won't see these events. Workaround for [this Bug](https://git.neo-layout.org/neo/neo-layout/issues/510).
    - `false`: Programs see M3/M4 events. Necessary if functions need to be bound in these applications.
- `"oneHandedMode"`:
    - "`mirrorKey"`: Scancode of the key used to mirror the keyboard, set to space bar (`44`) by default.
    - "`mirrorMap"`: Map of mirrored keys by scancode in the form of `"[original key]": "[mirrored key]"`. May have to be tweaked for ergonomic or matrix keyboards.

### Modifying layouts

Layouts can be added and modified in `layouts.json`. Every entry containst the following parameters:

- `"name"`: Name of the layout as displayed in the tray menu.
- `"dllName"` (optional): Name of the respective native driver DLL. If there is none, this parameter may be ommitted.
- `"modifiers"`: Scancodes of all modifiers, native modifiers also have to be mapped. A plus `+` character at the end of the scancode sets the extended bit, e.g. `36+` for the right shift key. Possible modifiers are `LShift`, `LCtrl`, `LAlt`, `LMod3`, `LMod4` (right variants as well) and the additional mod keys `Mod5` to `Mod9`.
- `"layers"`: Modifier combinations for each layer. Layers are tested and runtime and the first one where all modifiers fit the set values is chosen.
- `"capslockableKeys"`: Array of scancodes influenced by capslock. These are typically all letter keys.
- `"map"`: The actual layout as an array for each scancode. Every array has as many entries as there are layers containing the following:
    - `"keysym"`: X11 keysym, either from `keysymdef.h` or in the form of `U1234` for unicode characters. Used by compose.
    - **either** `"vk"`: Windows virtual key from the enumeration `VKEY` in `mapping.d`. Only used for navigation keys and special key combos.
    - **or** `"char"`: Unicode character that should be produced by this key.
    - `"label"`: (optional) Label for on-screen keyboard. `"char"` value is used as a fallback.
    - `"mods"`: (optional, exclusive to vk mappings) Modifiers that should be pressed (`true`) or released (`false`). Example: `"mods": {"LCtrl": true, "LAlt": true}`. Possible Modifiers are `LShift`, `RShift`, `LCtrl`, `RCtrl`, `LAlt`.

The following procedure is recommended to create a new layout:

1. Copy an existing layout and change the name
2. Re-order the letter key lines such that they correspond to the order on the keyboard read from the upper left to the lower right.
3. Use block selection to select the scancodes of an existing layouts and copy them over the (now unordered) scancodes of the new layout.
4. Use block selection to copy layers 3 and 4 of an existing layout to overwrite layers 3 and 4 of the new layout.
5. Change `modifiers` und `capslockableKeys` as necessary.

This results in layers 3 and 4 remaining as they were while the other layers permute according to the new letter layout.

# Virtual machines and remote desktop
As soon as several nested operatings systems interoperate things get difficult. Because different VM software and remote desktop clients behave differently there is no universal solution. What follows is some general advice and a few tested configurations.

For optimal compatibility, the *innermost* system should generally implement the alternative layout and all outer systems should be set to QWERTZ/QWERTY.
In the case of virtual machines this means QWERTZ on the host and a Neo driver on the guest system.
For remote desktop machines a local QWERTZ setup and a Neo driver on the remote system are recommended.

If it turns out that programs work better without ReNeo, the offending programs can be added to the *blacklist* for ReNeo to automatically deactivate, see [configuration](#general-configuration).

## WSL using VcXsrv as X server

Set Windows to QWERTZ (without ReNeo), then set the Neo layout in X11 using `setxkbmap`.

## VirtualBox

Set host to QWERTZ, then install Neo driver (e.g. ReNeo) in guest system.

## [Remote Desktop Manager](https://remotedesktopmanager.com/)

Use ReNeo in standalone mode on the local system. Letters and (non-unicode) special characters are transmitted correctely to the remote system.

# For developers
## Compilation
ReNeo is written in D and uses `dub` for project configuration and compilation.
There are three build settings:

1. Debug with `dub build`: In addition to debugging symbols, the generated executable opens instantiates a console to output debugging imformation.
2. Debug and log with `dub build --build=debug-log`: Similar to debug but console output is additionally written to `reneo_log.txt`. Caution: this log file may contain sensitive information!
3. Release with `dub build --build=release`: Optimizations are active and no console is instantiated.

The resource file `res/reneo.res` is built using `rc.exe` from the Windows SDK (x86 version, otherwise the generated res file won't work). The command ist `rc.exe reneo.rc`.

Cairo DLL originates from https://github.com/preshing/cairo-windows. The D header files were generated from the C headers using [DStep](https://github.com/jacob-carlborg/dstep) and manually tweaked.

## Release
A tag of the form `v*` triggers a GitHub action to generate a release draft. Based on the different `config.[layout].json` files, several pre-configured ZIP archives are created.

# Librarys
Uses [Cairo](https://www.cairographics.org/) licensed under the GNU Lesser General Public License (LGPL) version 2.1.
