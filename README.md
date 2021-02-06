# ReNeo – Ebene 4, Compose und mehr für kbdneo

## Was ist ReNeo?
ReNeo ist eine Erweiterung für den kbdneo-Treiber, der das [Neo-Layout](http://neo-layout.org/) nativ in Windows integriert.
Funktionen wie Capslock, die Steuertasten auf Ebene 4 und Compose können technisch bedingt nur eingeschränkt im reinen Tastaturtreiber implementiert werden und werden deshalb mit dieser Anwendung nachgerüstet.

## Installation
1. [kbdneo](https://neo-layout.org/Benutzerhandbuch/kbdneo/) normal installieren
2. [Neuesten ReNeo-Release](https://github.com/Rojetto/ReNeo/releases/latest) herunterladen und in beliebiges Verzeichnis entpacken
3. `reneo.exe` starten oder zu Autostart hinzufügen. Dass die Anwendung läuft sieht man momentan nur im Taskmanager.

## Funktionen

- Capslock (beide Shift-Tasten) und Mod4-Lock (beide Mod4-Tasten)
- Steuertasten auf Ebene 4
- *Alle* tote Tasten und Compose-Kombinationen. Diese sind auch durch den Nutzer erweiterbar, alle `.module`-Dateien im Verzeichnis „compose“ werden beim Start geladen.
- Verbesserte Kompatibilität mit Qt- und GTK-Anwendungen. Workaround für [diesen Bug](https://git.neo-layout.org/neo/neo-layout/issues/510).
- Compose-Taste `M3+Tab` sendet keinen Tab mehr an Anwendung. Workaround für [diesen Bug](https://git.neo-layout.org/neo/neo-layout/issues/397).

## Vergleich mit anderen Windows-Treibern
Der Vergleich bezieht sich auf die Kombination kbdneo+ReNeo.

### kbdneo + AHK-Erweiterung
🟢 Alle CoKos, durch Nutzer anpassbar  
🟢 Behebung der o.g. Bugs  
🟠 Keine Bildschirmtastatur für obere Ebenen  
🟠 (noch) keine Unterstützung alternativer Buchstabenanordnungen (Bone etc.)

### NeoVars
🟢 Native Integration in Windows Layoutauflistung  
🟢 Native Bildschirmtastatur für untere Ebenen  
🟢 Grundfunktionen funktionieren auf Anmeldebildschirm, unmittelbar nach Login und in Admin-Anwendungen, ohne dass Skript im Admin-Modus gestartet werden muss  
🟢 CoKos ohne Rekompilation erweiterbar  
🟡 Installation von kbdneo braucht Adminrechte  
🟠 Keine Bildschirmtastatur für obere Ebenen  
🟠 (noch) keine Unterstützung alternativer Buchstabenanordnungen (Bone etc.)  
🟠 Keine Extra-Features (Einhandmodus, ſ-Modus, Taschenrechner…)

## Kompilieren
ReNeo ist in D geschrieben und nutzt `dub` für Projektkonfiguration und Kompilation.
Es gibt zwei wichtige Kompilationsvarianten:
1. Debug mit `dub build`: Neben Debuggingsymbolen öffnet die generierte EXE eine Konsole um Informationen ausgeben zu können.
2. Release mit `dub build --build=release`: Optimierungen sind aktiviert und es wird keine Konsole geöffnet.

## Offene Aufgaben
- [x] Automatisch deaktivieren, wenn anderes Tastaturlayout aktiv
- [ ] Prüfung ob Anwendung bereits läuft
- [ ] Icon für EXE
- [ ] Tray Icon (braucht man das tatsächlich?)
- [ ] „Einfg“ auf Ebene 4 untersuchen (scheint in NeoVars aber auch nicht zu gehen)
- [ ] Latenz messen

## Fernziele
- [ ] Integration in Hauptrepository
- [ ] Flexibleres Mappingformat
- [ ] Kompatibilität mit anderen Neo-verwandten Layouts
- [ ] UI für Compose
