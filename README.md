# ReNeo – Die Neo-Tastaturlayouts für Windows

[**Click here for English**](README_EN.md)

ReNeo implementiert das [Neo-Tastaturlayout](http://neo-layout.org/) und seine Verwandten für Windows. Dabei kann man sich für eine von zwei Varianten entscheiden:
1. Im *Standalone-Modus* ersetzt ReNeo alle Tastendrücke des nativen Layouts (meistens QWERTZ) durch das gewünschte Neo-Layout. Dafür muss zum Systemstart nur die ReNeo-EXE ausgeführt werden.
2. Im *Erweiterungsmodus* installiert man einen nativen Neo-Treiber wie [kbdneo](https://neo-layout.org/Einrichtung/kbdneo/). ReNeo ergänzt dann alle Funktionen, die nativ nicht umsetzbar sind (Capslock, Steuertasten auf Ebene 4, Compose, ...).

![ReNeo Bildschirmtastatur Ebene 1](docs/osk_screenshot.png "ReNeo Bildschirmtastatur")

## Installation

1. *Optional*: [kbdneo](https://neo-layout.org/Einrichtung/kbdneo/) normal installieren
2. [Neuesten ReNeo-Release](https://github.com/Rojetto/ReNeo/releases/latest) herunterladen und in ein Verzeichnis mit Schreibrechten entpacken (z. B. `C:\Users\[USER]\ReNeo`)
3. `reneo.exe` starten oder [zu Autostart hinzufügen](docs/autostart.md). Über das Trayicon kann das Programm deaktiviert und beendet werden.
4. *Optional*: [`config.json` anpassen](#Allgemeine-Konfiguration) (wird beim ersten Start generiert)

*Update*

Neuen Release herunterladen und vorhandene Dateien mit den neuen überschreiben. Da `config.json` nicht im Release enthalten ist, bleiben Nutzereinstellungen erhalten.

*Deinstallation*

1. *Optional*: kbdneo nach Wiki-Anleitung deinstallieren
2. ReNeo-Verzeichnis löschen und aus Autostart entfernen

## Funktionen

Allgemein:

- Unterstützt die Layouts *Neo*, *Bone*, *NeoQwertz*, *Mine*, *AdNW*, *KOY*, [*VOU*](https://www.maximilian-schillinger.de/vou-layout.html), [*3l*](https://github.com/jackrosenthal/threelayout)
- Im Traymenü kann zwischen Layouts gewechselt werden
- Capslock (beide Shift-Tasten) und Mod4-Lock (beide Mod4-Tasten)
- **Bildschirmtastatur**: Wird über Tray-Menü ein- und ausgeschaltet oder per Shortcut `M3+F1`. Wechselt zwischen Ebenen, wenn Modifier gedrückt werden.
- *Alle* tote Tasten und Compose-Kombinationen. Diese sind auch durch den Nutzer erweiterbar, alle `.module`-Dateien im Verzeichnis `compose/` werden beim Start geladen.
- Spezial-Compose-Sequenzen
    - Unicode-Eingabe: `♫uu[codepoint hex]<space>` fügt Unicode-Zeichen ein. Beispiel: `♫uu1f574<space>` → 🕴
    - Römische Zahlen: `♫rn[zahl]<space>` für kleine Zahlen, `♫RN[zahl]<space>` für große Zahlen zwischen 1 und 3999. Beispiel: `♫rn1970<space>` → ⅿⅽⅿⅼⅹⅹ, `♫RN1970<space>` → ⅯⅭⅯⅬⅩⅩ
- `Shift+Pause` (de)aktiviert die Anwendung
- Einhandmodus: Wenn Modus aktiv ist und Leertaste (Standard) gehalten wird, wird die gesamte Tastatur „gespiegelt“. Umschalten über Tray-Menü oder per Shortcut `M3+F10`.
- Weitere Layouts können in `layouts.json` hinzugefügt und angepasst werden

Als Erweiterung zum nativen Treiber:

- Steuertasten auf Ebene 4
- Wird das native Layout als Neo-verwandt erkannt (`kbdneo.dll`, `kbdbone.dll`, `kbdgr2.dll`), schaltet ReNeo automatisch in den Erweiterungs-Modus. Umschalten zwischen Layouts ist ganz normal möglich.
- Verbesserte Kompatibilität mit Qt- und GTK-Anwendungen. Workaround für [diesen Bug](https://git.neo-layout.org/neo/neo-layout/issues/510).
- Compose-Taste `M3+Tab` sendet keinen Tab mehr an Anwendung. Workaround für [diesen Bug](https://git.neo-layout.org/neo/neo-layout/issues/397).

## Konfiguration

ReNeo kann mit zwei Konfigurationsdateien angepasst werden.

### Allgemeine Konfiguration

`config.json` hat folgende Optionen:

- `"standaloneMode"`:
    - `true` (Standard): Das native Layout (z. B. QWERTZ) wird von ReNeo mit dem ausgewählten Neo-Layout ersetzt. Hinweis: ist das native Layout bereits Neo-verwandt, verändert ReNeo das Layout nicht und schaltet stattdessen automatisch in den Erweiterungsmodus.
    - `false`: Ist das native Layout Neo-verwandt, schaltet ReNeo in den Erweiterungsmodus. Bei allen anderen Layouts deaktiviert sich ReNeo automatisch.
- `"standaloneLayout"`: Layout, das für den Standalone-Modus genutzt werden soll. Auch übers Traymenü auswählbar.
- `"language"`: Programmsprache, `"german"` oder `"english"`.
- `"osk"`:
    - `"numpad"`: Soll Numpad in Bildschirmtastatur angezeigt werden?
    - `"numberRow"`: Soll die Zahlenreihe angezeigt werden?
    - `"theme"`: Farbschema für Bildschirmtastatur. Mögliche Werte: `"Grey"`, `"NeoBlue"`, `"ColorClassic"`, `"ColorGreen"`
    - `"layout"`: `"iso"` oder `"ansi"`
    - `"modifierNames"`: `"standard"` (M3, M4, ...) oder `"three"` (Sym, Cur)
- `"hotkeys"`: Hotkeys für verschiedene Funktionen. Beispiel: `"Ctrl+Alt+F5"` oder `"Shift+Alt+Key_A"`. Erlaubte Modifier sind `Shift`, `Ctrl`, `Alt`, `Win`. Die Haupttaste ist ein beliebiger VK aus [dieser Enum](https://github.com/Rojetto/ReNeo/blob/5bd304a7c42c768ed45813095ab5fbc69103773c/source/mapping.d#L17), die auf der [Win32-Doku](https://docs.microsoft.com/en-us/windows/win32/inputdev/virtual-key-codes) basiert. Ist ein Wert `null`, wird kein globaler Hotkey angelegt.
    - `"toggleActivation"`: ReNeo aktivieren/deaktivieren
    - `"toggleOSK"`: Bildschirmtastatur öffnen/schließen. Zusätzlich zu dem hier konfigurierten Hotkey funktioniert immer `M3+F1`.
    - `"toggleOneHandedMode"`: Einhandmodus (de)aktivieren. Zusätzlich funktioniert immer `M3+F10`.
- `"blacklist"`: Liste von Programmen, für die ReNeo automatisch deaktiviert werden soll (zum Beispiel X-Server, Remote-Clients oder Spiele, bei denen es sonst Konflikte gibt). Momentan wird nach dem Fenstertitel entschieden, für den man eine *RegEx* definieren kann. *Beispiel*: Für Fenster, die "emacs" oder "Virtual Machine Manager" im Titel enthalten, soll ReNeo sich deaktivieren. Die Config enthält dann
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
- `"autoNumlock"`: Soll Numlock automatisch angeschaltet werden? Wenn die Tastatur einen echten Nummernblock besitzt, sollte diese Option für beste Kompatibilität immer auf `true` gesetzt sein. Bei Laptops mit nativer Numpad-Ebene auf dem Hauptfeld kann dieses Verhalten aber mit `false` deaktiviert werden.
- `"enableMod4Lock"`: Soll Mod4-Lock mit `LM4+RM4` aktiviert werden können? Kann abgestellt werden um unabsichtliches Aktivieren zu vermeiden.
- `"filterNeoModifiers"`:
    - `true` (Standard): Die Tastenevents für M3 und M4 werden im Erweiterungsmodus von ReNeo weggefiltert, Anwendungen bekommen von diesen Tasten also nichts mit. Workaround für [diesen Bug](https://git.neo-layout.org/neo/neo-layout/issues/510).
    - `false`: Anwendungen sehen M3/M4. Notwendig, wenn man in den Anwendungen mit diesen Tasten Optionen verknüpfen will.
- `"oneHandedMode"`:
    - "`mirrorKey"`: Scancode der Taste zum Spiegeln, standardmäßig ist die Leertaste (`44`) eingestellt.
    - "`mirrorMap"`: Zuordnung der gespiegelten Tasten nach Scancode in der Form `"[Originaltaste]": "[Spiegeltaste]"`. Muss für ergonomische oder Matrixtastaturen evtl. angepasst werden.

### Layouts anpassen

In `layouts.json` können Layouts angepasst und hinzugefügt werden. Jeder Eintrag besitzt folgende Parameter:

- `"name"`: Name des Layouts, so wie er im Menü angezeigt wird.
- `"dllName"` (Optional): Name der zugehörigen nativen Treiber-DLL. Existiert diese nicht, kann der Parameter weggelassen werden.
- `"modifiers"`: Scancodes aller Modifier, auch alle nativen Modifier müssen hier gemappt werden. Mit `+` am Ende des Scancodes wird das Extended-Bit gesetzt, zum Beispiel `36+` für die rechte Shift-Taste. Mögliche Modifier sind `LShift`, `LCtrl`, `LAlt`, `LMod3`, `LMod4` (jeweils auch rechte Variante) sowie weitere Mod-Tasten `Mod5` bis `Mod9`.
- `"layers"`: Modifier-Kombinationen für jede Ebene. Die Ebenen werden zur Laufzeit nacheinander getestet und die erste Ebene übernommen, deren Modifier die spezifizierten Werte haben.
- `"capslockableKeys"`: Array von Scancodes, die von Capslock beeinflusst werden sollen. Typischerweise sind das alle Buchstaben, inklusive „äöüß“.
- `"map"`: Das tatsächliche Layout in Form von Arrays für jeden Scancode. Jeder Eintrag enthält so viele Einträge, wie Ebenen in `"layers"` definiert wurden, mit folgendem Inhalt:
    - `"keysym"`: X11-Keysym der Taste, entweder aus `keysymdef.h` oder in der Form `U1234` für Unicode-Zeichen. Wird für Compose benutzt.
    - **Entweder** `"vk"`: Windows Virtual Key aus dem Enum `VKEY` in `mapping.d`. Nur genutzt für Steuertasten.
    - **Oder** `"char"`: Unicode-Zeichen, das mit der Taste erzeugt werden soll.
    - `"label"`: (Optional) Beschriftung für Bildschirmtastatur. Als Fallback wird der Wert von `"char"` genutzt.
    - `"mods"`: (Optional, nur für VK-Mappings) Modifier, die gedrückt (`true`) oder losgelassen (`false`) werden sollen. Beispiel: `"mods": {"LCtrl": true, "LAlt": true}`. Mögliche Modifier sind `LShift`, `RShift`, `LCtrl`, `RCtrl`, `LAlt`.

Zum Erstellen neuer Layouts hat sich folgender Arbeitsablauf bewährt:

1. Bestehendes Layout kopieren und neuen Namen eintragen
2. Die Zeilen der Buchstabentasten (also ab Scancode `0C`) neu ordnen, sodass diese auf der Tastatur von oben links nach unten rechts gelesen in der richtigen Reihenfolge sind.
3. Mit Blockauswahl die Scancodes eines bestehenden Layouts kopieren, und die (jetzt falsch geordneten) Scancodes des neuen Layouts überschreiben.
4. Mit Blockauswahl Ebenen 3 und 4 eines bestehenden Layouts kopieren, und Ebenen 3 und 4 des neuen Layouts überschreiben.
5. `modifiers` und `capslockableKeys` ggf. anpassen

So bleiben Ebenen 3 und 4 an der richtigen Stelle, und die anderen Ebenen werden nach der neuen Buchstabenanordnung permutiert.

Folgende Regex kann beim Ausrichten der Spalten helfen: `"[\dA-Fa-f]+\+?": *\[(\{.*?\}, *){5}\{`

# Virtuelle Maschinen und Remote Desktop
Sobald mehrere „ineinander“ laufende Betriebssysteme ins Spiel kommen, wird es mit alternativen Tastaturlayouts fast immer haarig.
Da sich die verschiedenen VM-Programme und Remote Desktop Clients unterschiedlich verhalten, gibt es leider keine universelle Lösung, sondern nur eine grundsätzliche Empfehlung und ein paar erprobte Konfigurationen.

Für beste Kompatibilität sollte im Allgemeinen das *innerste* System das Alternativlayout übernehmen, und in allen äußeren Systeme QWERTZ eingestellt sein.
Bei VMs bedeutet das QWERTZ im Wirt und den passenden Neo-Treiber im Gast.
Im Fall von Remote-Desktop-Verbindungen heißt es QWERTZ lokal und einen Neo-Treiber im Remote-System.

Wenn sich herausstellt, dass es ohne ReNeo besser funktioniert, können die entsprechenden Programme auch auf die *Blacklist* gesetzt werden, sodass sich ReNeo automatisch deaktiviert. Siehe dazu [Konfiguration](#allgemeine-konfiguration).

## WSL mit VcXsrv als X-Server

In Windows QWERTZ (ohne ReNeo), dann das Neo-Layout in X11 einstellen. Für Neo lautet der Befehl `setxkbmap de neo`, für andere Layouts muss eventuell noch eine passende xkbmap installiert werden.

## VirtualBox

Im Wirtsystem QWERTZ einstellen, dann Neo-Treiber (z. B. ReNeo) im Gastsystem installieren.

## [Remote Desktop Manager](https://remotedesktopmanager.com/)

Es geht offenbar auch ReNeo im Standalone-Modus auf dem lokalen System mit QWERTZ auf dem Remote-System. Zumindest Buchstaben und (nicht-Unicode)-Sonderzeichen werden dann auf die Remote-Systeme korrekt weitergeleitet.

# Für Entwickler
## Kompilieren
ReNeo ist in D geschrieben und nutzt `dub` für Projektkonfiguration und Kompilation.
Es gibt drei wichtige Kompilationsvarianten:

1. Debug mit `dub build`: Neben Debuggingsymbolen öffnet die generierte EXE eine Konsole um Informationen ausgeben zu können.
2. Debug und Log mit `dub build --build=debug-log`: Wie debug, nur dass zusätzlich in `reneo_log.txt` alle Konsolenausgaben abgespeichert werden. Achtung: Hier können potentiell sensible Daten landen.
3. Release mit `dub build --build=release`: Optimierungen sind aktiviert und es wird keine Konsole geöffnet.

Die Ressourcendatei `res/reneo.res` wird mit `rc.exe` aus dem Windows SDK erstellt (x86-Version, die generierte res-Datei funktioniert sonst nicht). Dazu reicht der Befehl `rc.exe reneo.rc`.

Cairo-DLL stammt von https://github.com/preshing/cairo-windows. Die zugehörigen D-Header wurden mit [DStep](https://github.com/jacob-carlborg/dstep) aus den C-Headern generiert und manuell angepasst.

## Release
Wenn ein Tag nach dem Schema `v*` im Repo ankommt, löst eine GitHub Action den Release aus. Auf Basis der `config.[layout].json` Dateien werden verschiedene vorkonfigurierte ZIP-Archive erstellt und ein Release-Draft angelegt. Der kann dann manuell bearbeitet und freigeschaltet werden.

# Bibliotheken
Nutzt [Cairo](https://www.cairographics.org/), lizensiert unter der GNU Lesser General Public License (LGPL) Version 2.1.