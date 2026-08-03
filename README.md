# Zoom98 Control for macOS

An unofficial, native SwiftUI configuration utility for the Zoom98 keyboard. It communicates directly with the keyboard's 32-byte VIA HID interface through macOS IOKit and does not require a background service.

> This project is not affiliated with, endorsed by, or authorized by Meletrix or Wuque Studio. Export a backup before making changes, and use keymap, lighting, and macro features at your own risk.

<img width="2480" height="1430" alt="image" src="https://github.com/user-attachments/assets/ea18bce7-dc37-49c1-92c1-57bcf8d18c48" />


## Features

- Detects a Zoom98 connected over USB (VID `0x1EA7`, PID `0xCD68`)
- Reads and configures the per-key RGB Matrix color, brightness, speed, and recognized effects
- Displays a layout modeled after the physical Zoom98 keyboard
- Reads and edits the primary and Fn layers
- Supports standard keys, macOS-compatible media keys, and 16 firmware text macros
- Reads settings back after writing for verification and can undo the most recent keymap change
- Imports and exports JSON configurations, with rollback when an import fails
- Connects to `Zoom98 Screen` over BLE to read firmware information and send verified screen commands
- Attempts to read keyboard battery level from the keyboard's separate BLE HID battery service

## Known Limitations

- The current Zoom98 firmware stores QMK combination keycodes but does not execute them in testing, so the app no longer offers combination-key assignments
- Windows consumer-control keys such as `KC_CALC`, Mail, and Browser do not have equivalent system actions on macOS
- Text macros are limited by the keyboard firmware's storage capacity and ASCII character support
- The screen and keyboard controller appear as two separate BLE devices; connecting to the screen does not provide keyboard battery information
- The keyboard does not expose a writable Bluetooth `Device Name (2A00)` characteristic, so its advertised name cannot currently be changed reliably
- The side light bar (Bottom Light) can be controlled independently with firmware shortcuts, but a working software-control protocol has not yet been identified

## Requirements

- macOS 14 or later
- Apple Silicon Mac (the current release build is arm64)
- A USB connection to the Zoom98 for configuration features
- Input Monitoring permission may be required the first time the app accesses the HID interface

## Build

Create a double-clickable app bundle:

```sh
./scripts/build-app.sh
```

The result is written to `dist/Zoom98 Control.app`.

Run directly for development:

```sh
swift run
```

Release builds use local ad-hoc code signing and are not notarized with an Apple Developer ID. On first launch, another Mac may require approval under **System Settings → Privacy & Security**.

## Side Light Research

The official firmware controls the Bottom Light separately from the per-key RGB Matrix. However, the VIA commands tested so far—and the vendor-specific `ReadFirmwareLightEffect` command—only return the per-key lighting state. Scanning the private command fields did not reveal a second set of lighting values.

For that reason, Zoom98 Control only presents firmware shortcuts that have been verified. It does not expose an unresponsive VIA `RGB Light` field as if it were functional. True software control of the side light will require further protocol research or a custom firmware command.

## Repository Contents

This repository contains only the macOS application source, build scripts, and design-review materials. It does not include the vendor APK, Windows drivers, firmware images, or reverse-engineering databases. Download the runnable ZIP from [GitHub Releases](https://github.com/pengzhou60/zoom98-control-mac/releases).
