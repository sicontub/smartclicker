# Changelog

## 1.9.3
- Much lighter on games while a scenario with image conditions is running:
  - checks the screen at most 20 times a second, and never spends more than half its time detecting
  - scenarios with only "whole screen" conditions capture the screen at half size when the device supports it
  - "exact position" conditions only copy the part of the screen they need
  - detection runs at a lower priority than the game, and reuses its memory between checks
- Tapping and Pause actions don't slow down detection, so spamming a button is as fast as before

## 1.9.1
- Fixed image conditions missing on Plus phones (6/6s/7/8 Plus), the 12/13 mini and Display Zoom, where the screen is drawn at a different size than the panel

## 1.9.0
- Triggers: start and stop scenarios from Triggr, RemoteCompanion, Shortcuts or a terminal
  - `smartclicker play|stop|toggle|show|hide [scenario name or number]`, `smartclicker list`
  - `smartclicker://play?scenario=Name` URL scheme
- Playing from a trigger doesn't open the menu
