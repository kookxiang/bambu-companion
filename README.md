# Bambu Companion

Bambu Companion is a macOS menu bar app for monitoring Bambu Lab printers on a local network.

It connects directly to the printer's LAN MQTT event stream and RTSP video stream, then shows current print status, temperatures, AMS trays, cover images, alerts, and camera preview from the menu bar.

## Features

- Menu bar status with active print progress.
- Popover dashboard for print state, job name, progress, layers, remaining time, nozzle, bed, chamber, fans, and AMS information.
- Dual-nozzle temperature display for machines such as H2D.
- AMS tray display with active slot highlighting, filament color/type, estimated remaining weight when available, humidity/temperature tooltips, and drying status.
- Print cover image loading from the printer over FTPS, with local caching to avoid repeated downloads.
- Native RTSP video preview using AVFoundation, with a floating always-on-top video window.
- macOS notifications for meaningful print activity changes and HMS alerts.
- Localized UI strings for English and Simplified Chinese.
- Settings window for printer name, host/IP, serial number, and LAN access code.

## Requirements

- macOS 14 or newer.
- Xcode 15.4 or newer. Xcode Beta also works if you are running a beta macOS SDK.
- A Bambu Lab printer reachable on the same LAN.
- LAN mode / LAN access enabled on the printer.
- Printer IP or hostname, serial number, and LAN access code.

## Network Access

The app talks directly to the printer:

- MQTT over TLS on port `8883`.
- RTSP / RTSPS video on port `322`.
- FTPS for downloading `.3mf` files used to extract cover images.

No cloud account is required by the app. The LAN access code is stored in the macOS Keychain. Other printer settings are stored in `UserDefaults`.

## Build

Open `BambuCompanion.xcodeproj` in Xcode and run the `BambuCompanion` scheme.

From the command line:

```sh
xcodebuild -scheme BambuCompanion -configuration Debug build
```

When using Xcode Beta:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -scheme BambuCompanion -configuration Debug build
```

## Setup

1. Launch the app.
2. Open Settings from the menu bar popover.
3. Enter the printer IP/host, serial number, and LAN access code.
4. Save or test the connection.

Once connected, updates are pushed through MQTT. The manual reconnect button is only shown when the app is disconnected or failed.

## Project Structure

- `BambuCompanion/` - App source code and resources.
- `BambuCompanion/Assets.xcassets/` - App icon asset catalog.
- `BambuCompanion/HMSResources/` - HMS error catalogs copied from Bambu Studio.
- `BambuCompanionTests/` - Unit tests for MQTT parsing and related behavior.
- `Design/` - Logo concept source images.

## Notes

This is a local-network companion app. It is not affiliated with or endorsed by Bambu Lab.

The app icon is an original design inspired by the idea of a companion cube and 3D printing. It intentionally avoids copying the original Portal Companion Cube artwork or the exact Bambu Lab logo.

## License

The app source code is licensed under the MIT License. See `LICENSE`.

The HMS JSON resources under `BambuCompanion/HMSResources/` are copied from the official Bambu Studio repository and are licensed under the GNU Affero General Public License v3.0. See `BambuCompanion/HMSResources/NOTICE.txt` and `BambuCompanion/HMSResources/LICENSE-BambuStudio-AGPL-3.0.txt`.
