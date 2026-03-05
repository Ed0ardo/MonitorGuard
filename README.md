# MonitorGuard

MonitorGuard is a Windows utility that turns off all connected monitors using DDC/CI (preferred) or WinAPI fallback, then shuts down the PC. It's designed for quick power-off, like before leaving your desk.

## Features

- Enumerates all physical monitors via Windows APIs.
- Attempts DDC/CI power-off (VCP 0xD6 or DPMS 0x01) with best matching off state (off, suspend, standby).
- Falls back to broadcast `SCMONITORPOWER` if DDC/CI fails or unsupported.
- Logs per-monitor success/warnings (e.g., "DDCCI OK - VCP 0xD6=5 (off)").
- Forces PC shutdown after 2-second delay.

## Installation

Run `setupMonitorGuard.bat` as administrator. The wizard lets you choose:

- Add to Start Menu.
- Create Desktop shortcut.
- Pin to Taskbar (manual steps shown post-install).

It downloads the main script and icon from GitHub, compiles a launcher .exe, and sets up shortcuts with custom icon.

## Files

| File | Purpose |
| --- | --- |
| `MonitorGuard.bat` | Core script: C# compilation + PowerShell execution for monitor off + shutdown. |
| `setupMonitorGuard.bat` | Interactive installer: downloads files, builds .exe launcher, creates shortcuts. |

## Requirements

- Windows (tested on modern versions with dxva2.dll/user32.dll).
- Administrator rights for setup (auto-elevates).
- Internet for initial install (downloads from repo).
- Monitors supporting DDC/CI for optimal results (enable in OSD).

## Troubleshooting

- **DDCCI fails**: Enable DDC/CI in monitor settings; use HDMI/DP cables.
- **No monitors off**: WinAPI fallback should work; check Event Viewer for errors.
- **Install fails**: Run as admin; check internet/URLs in setup script.
- Edit `MonitorGuard.bat` for custom delays or remove shutdown (`# Stop-Computer -Force`).
