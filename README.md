# SmartClicker

A port of [Smart AutoClicker](https://github.com/Nain57/Smart-AutoClicker) by Nain57 and other amazing contributors!!!

You're given an overlay that can automate tasks when set up properly, such as daily quests in a game!

## Requirements

- Jailbroken iOS 15 or later (rootless, rootful, & roothide jailbreaks should work. Support past 17.x is not guaranteed)
- ElleKit (supplied in Dopamine jailbreaks)

Tested on an iPhone 6S Plus, iOS 15.8.3, iPad 7th Gen, iPadOS 17.5.1, & iPhone SE (2020), iOS 17.6.1. All on Dopamine

## Install

Download the proper `.deb` for your jailbreak from Releases and open it in your preferred package manager.

## Use

1. Open the SmartClicker app, create a scenario, then tap it and you'll see the overlay pop up
2. Tap the list button w/ a pointing index finger to then add events & conditions.
3. Then, tap Play or hold Play for debug mode

Backups use the same `.zip` format as the Android app, so scenarios can move between the two.

## Triggers (Triggr, RemoteCompanion, Shortcuts, etc.)

Scenarios can be started and stopped without the floating overlay

From anything that runs a command:

    smartclicker play "Daily quests"    # quotation marks are not needed
    smartclicker stop
    smartclicker toggle                 # play/stop action
    smartclicker show / hide            # shows/hides the overlay
    smartclicker list                   # scenario names and numbers

From anything that opens a link:

    smartclicker://play?scenario=Daily%20quests
    smartclicker://stop
    smartclicker://toggle

Links open in SmartClicker. Commands will not.

## Build

Linux is just fine. Check out the header of `build-linux-clang21.sh` for the toolchain.

    SDK=/path/to/iPhoneOS16.5.sdk TOOLBIN=/path/to/cctools/bin bash build-linux-clang21.sh

## License

GPL-3.0. See `LICENSE`.
