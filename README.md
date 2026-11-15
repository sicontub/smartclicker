# SmartClicker

An auto clicker with image detection for jailbroken iOS. It is a port of
[Smart AutoClicker](https://github.com/Nain57/Smart-AutoClicker) for Android by Nain57.

A floating menu sits over any app. Scenarios are lists of events; each event has image
conditions ("when this picture is on screen") and actions (click, swipe, wait, open app).

## Requirements

- Jailbroken iOS 15 or later (rootless or rootful), arm64 or arm64e
- ElleKit or Substrate

Developed and tested on an iPhone SE (2020), iOS 17.6.1, Dopamine. Other setups are untested.

## Install

Download the `.deb` from Releases and open it in Sileo or Zebra:

- `iphoneos-arm64` for rootless jailbreaks (Dopamine, palera1n rootless)
- `iphoneos-arm` for rootful jailbreaks

## Use

1. Open the SmartClicker app, create a scenario and tap it. The floating menu appears.
2. Tap the list button to add events, conditions and actions.
3. Tap play. Long-press play for debug mode.

Backups use the same `.zip` format as the Android app, so scenarios can move between the two.

## Triggers (Triggr, RemoteCompanion, Shortcuts)

Scenarios can be started and stopped without the floating menu.

From anything that runs a command (Triggr, RemoteCompanion, a terminal):

    smartclicker play "Daily quests"    # start a scenario by name (or number)
    smartclicker stop
    smartclicker toggle                 # start or stop the last used scenario
    smartclicker show / hide            # show or hide the floating menu
    smartclicker list                   # scenario names and numbers

From anything that opens a link (Triggr, the Shortcuts app):

    smartclicker://play?scenario=Daily%20quests
    smartclicker://stop
    smartclicker://toggle

Links briefly open the SmartClicker app; the command doesn't.

## Build

Linux, no Theos needed. See the header of `build-linux-clang21.sh` for the toolchain.

    SDK=/path/to/iPhoneOS16.5.sdk TOOLBIN=/path/to/cctools/bin bash build-linux-clang21.sh

## License

GPL-3.0, the same license as Smart AutoClicker. See `LICENSE`.
