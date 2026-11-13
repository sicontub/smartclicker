# SmartClicker

This is a port of version 1.5.2 of [Smart AutoClicker](https://github.com/Nain57/Smart-AutoClicker) for Android by Nain57 & other amazing contributors!!!

An Auto-clicker overlay that can be streamlined to your needs, such as daily quests in a game!

## Requirements

- iOS 15 or later (rootless or rootful, support past iOS 17.x isn't guranteed)
- ElleKit (supplied with Dopamine jailbreaks)

Tested on iPhone SE (2020), iOS 17.6.1 & iPad 7th Gen, iPadOS 17.5.1 all on Dopamine.

## Install

Download the proper `.deb` for your jailbreak from Releases and open it your preferred package manager.

## Use

1. Create a new scenario in the app with the `+` button, click it, and you'll be shown the overlay.
2. Tap the List w/ the pointing finger to add events & conditions.
3. Then, tap Play or hold the Play button for debug mode.

Backups from the 1.5.2 version of Smart AutoClicker should transfer over well. Adjusting the images and click conditions may be required.

## Build

Linux is just fine. Check out the header of `build-linux-clang21.sh` for the toolchain.

    SDK=/path/to/iPhoneOS16.5.sdk TOOLBIN=/path/to/cctools/bin bash build-linux-clang21.sh

## License

GPL-3.0. See `LICENSE`.
