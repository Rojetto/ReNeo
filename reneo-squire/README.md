# Building
There are two important build types:
1. Debug build: Run `dub build`. Among debug symbols and stuff this build also opens a console for showing debug output.
2. Release build: Run `dub build --build=release`. Optimizations get applied and there is no console when running the app. 

# Tasks
- [ ] write readme
- [x] map numpad
- [ ] clean up native driver
- [ ] document native driver installation
- [ ] automate installation and uninstallation
- [ ] decide on license
- [x] better handling of bad compose modules and keysym file
- [x] mod 4 lock
- [x] Shift while using layer 4 arrow keys
- [x] work out some conditional compilation thing for opening a console
- [ ] check whether app is already running
- [ ] fix layer 4 insert key
- [x] general code cleanup
- [ ] tray icon

# Possible future features
- [ ] less hardcoded mapping
- [ ] optional layers 3,4,5,6 in native driver
- [ ] some kind of compose UI
- [ ] integrate into main repository
- [x] compatibility with KBDNEO
- [ ] investigate performance
