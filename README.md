# VibeAutoHotkey

Delphi 12 VCL application for controlling ChatGPT, ChatGPT Classic, and Claude with global keyboard shortcuts from a Ulanzi Vibe Key or a regular keyboard.

## Features

- Finds running app windows and lets you choose an instance.
- Registers configurable `Ctrl+Alt+F1` through `Ctrl+Alt+F12` shortcuts, with a free-key fallback on conflicts.
- Activates the target window, locates its prompt with Windows UI Automation, and moves the caret to the end.
- Optionally invokes a supported microphone or voice button through UI Automation.
- Saves actions and shortcuts in `VibeAutoHotkey.json` in the user's home directory.
- Minimizes to the system tray; double-click the tray icon to restore, or use its menu to exit.

## Build

Open `VibeAutoHotkey.dpr` with Delphi 12 and build for Win64. From a configured Delphi command prompt, `dcc64 -B VibeAutoHotkey.dpr` also builds the program. The icon resource is generated from `VibeAutoHotkey.rc` and `VibeAutoHotkey.ico` with `cgrc VibeAutoHotkey.rc` before the first command-line build.

UI Automation element names vary by app version and locale. Check the in-app log if prompt focus or microphone activation is unavailable. The microphone button is invoked only when a matching enabled control supports InvokePattern.
