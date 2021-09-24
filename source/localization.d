module localization;

import std.conv : to;
import std.format : format;
import std.utf : toUTF16z;
import std.string : capitalize;

import core.sys.windows.windows : LPCWSTR;
import core.sys.windows.winuser : MOD_WIN, MOD_ALT, MOD_SHIFT, MOD_CONTROL;

import app : HotkeyConfig;
import mapping : VKEY;

enum AppString {
    MENU_DISABLE,
    MENU_ENABLE,
    MENU_RELOAD,
    MENU_CHOOSE_LAYOUT,
    MENU_QUIT,
    MENU_OSK,
    MENU_ONE_HANDED_MODE,

    ERROR_INVALID_HOTKEY_MODIFIER,
    ERROR_BLACKLIST_MUST_CONTAIN_WINDOW_TITLE,
    ERROR_ERROR_OCCURRED_WHILE_STARTING,
    ERROR_WHILE_INITIALIZING,
    ERROR_PATH_DOES_NOT_EXIST,
    ERROR_WHILE_PARSING
}

enum Language {
    ENGLISH,
    GERMAN
}

private Language selectedLanguage;

private string[Language][AppString] stringMap;

void initLocalization(Language lang) {
    stringMap = [
        AppString.MENU_DISABLE: [Language.ENGLISH: "Deactivate\t%s", Language.GERMAN: "Deaktivieren\t%s"],
        AppString.MENU_ENABLE: [Language.ENGLISH: "Activate\t%s", Language.GERMAN: "Aktivieren\t%s"],
        AppString.MENU_RELOAD: [Language.ENGLISH: "Reload", Language.GERMAN: "Neu laden"],
        AppString.MENU_CHOOSE_LAYOUT: [Language.ENGLISH: "Layout", Language.GERMAN: "Tastaturlayout"],
        AppString.MENU_QUIT: [Language.ENGLISH: "Quit", Language.GERMAN: "Beenden"],
        AppString.MENU_OSK: [Language.ENGLISH: "On-Screen Keyboard\t%s", Language.GERMAN: "Bildschirmtastatur\t%s"],
        AppString.MENU_ONE_HANDED_MODE: [Language.ENGLISH: "One-Handed Mode\t%s", Language.GERMAN: "Einhandmodus\t%s"],
        AppString.ERROR_INVALID_HOTKEY_MODIFIER: [
            Language.ENGLISH: "Non-existent hotkey modifier '%s'. Possible values are Shift, Ctrl, Alt, Win.",
            Language.GERMAN: "Nicht existierender Hotkey-Modifier '%s'. Mögliche Werte sind Shift, Ctrl, Alt, Win."
        ],
        AppString.ERROR_BLACKLIST_MUST_CONTAIN_WINDOW_TITLE: [
            Language.ENGLISH: "Blacklist entries must contain \"windowTitle\".",
            Language.GERMAN: "Blacklist-Einträge müssen \"windowTitle\" enthalten."
        ],
        AppString.ERROR_ERROR_OCCURRED_WHILE_STARTING: [
            Language.ENGLISH: "An error occurred while starting ReNeo:\n%s",
            Language.GERMAN: "Beim Starten von ReNeo ist ein Fehler aufgetreten:\n%s"
        ],
        AppString.ERROR_WHILE_INITIALIZING: [
            Language.ENGLISH: "Error during initialization",
            Language.GERMAN: "Fehler beim Initialisieren"
        ],
        AppString.ERROR_PATH_DOES_NOT_EXIST: [
            Language.ENGLISH: "%s does not exist.",
            Language.GERMAN: "%s existiert nicht."
        ],
        AppString.ERROR_WHILE_PARSING: [
            Language.ENGLISH: "Error while parsing %s.\n%s",
            Language.GERMAN: "Fehler beim Parsen von %s.\n%s"
        ],
    ];

    selectedLanguage = lang;
}

string appString(T...)(AppString as, T args) nothrow {
    try {
        if (as in stringMap && selectedLanguage in stringMap[as]) {
            return format(stringMap[as][selectedLanguage], args);
        } else {
            return as.to!string;
        }
    } catch (Exception e) {
        return "";
    }
}

LPCWSTR appStringwz(T...)(AppString as, T args) nothrow {
    try {
        return appString(as, args).toUTF16z;
    } catch (Exception e) {
        return null;
    }
}

string hotkeyString(HotkeyConfig hotkey) {
    string hotkeyString = "";

    if (hotkey.modFlags & MOD_WIN) {
        hotkeyString ~= "Win+";
    }
    if (hotkey.modFlags & MOD_CONTROL) {
        if (selectedLanguage == Language.GERMAN) {
            hotkeyString ~= "Strg+";
        } else {
            hotkeyString ~= "Ctrl+";
        }
    }
    if (hotkey.modFlags & MOD_ALT) {
        hotkeyString ~= "Alt+";
    }
    if (hotkey.modFlags & MOD_SHIFT) {
        hotkeyString ~= "Shift+";
    }

    hotkeyString ~= hotkey.key.to!VKEY.to!string[3..$].capitalize;

    return hotkeyString;
}
