# matter-commission-cli

> CLI tool to commission Matter devices via the Matter Server WebSocket API — without the Home Assistant UI.

[![Shell](https://img.shields.io/badge/shell-bash-green)](https://www.gnu.org/software/bash/)
[![NixOS](https://img.shields.io/badge/NixOS-25.x%2Funstable-blue)](https://nixos.org/)
[![Matter](https://img.shields.io/badge/Matter-1.x-purple)](https://buildwithmatter.com/)

🇫🇷 [Version française](README.fr.md)

---

## Overview

`matter_add.sh` is a small Bash script that commissions a Matter device directly from the command line. It connects to the [Matter Server (matter.js)](https://github.com/home-assistant-libs/python-matter-server) WebSocket API and sends a `commission_with_code` command, bypassing the Home Assistant / Google Home pairing flow entirely.

```
matter_add.sh <CODE>
      │
      ▼
Python + websocket-client (Nix store, ~2s startup)
      │
      ▼
ws://<matter-server>:5580/ws
      │
      ▼
BLE proxy (Home Assistant → ESPHome ESP32)
      │  BLE
      ▼
Matter device → commissioned ✅ → visible in Home Assistant
```

---

## Requirements

| Component | Version |
|-----------|---------|
| NixOS | 25.x / unstable |
| [Matter Server](https://github.com/home-assistant-libs/python-matter-server) | ≥ 2026.6 |
| Home Assistant | ≥ 2026.6 |
| ESPHome | ≥ 2026.5 (BLE proxy) |
| Python 3.13 + `websocket-client` | Present in Nix store |

The script uses **Python 3.13 and `websocket-client` already present in the Nix store** — no `nix-shell`, no extra install, ~2s startup.

Ensure your NixOS configuration includes:

```nix
environment.systemPackages = with pkgs; [
  python3
  python3Packages.websocket-client
];
```

---

## Setup

### 1. Clone the repository

```bash
git clone https://github.com/lotus-z-dev/matter-commission-cli.git
cd matter-commission-cli
chmod +x matter_add.sh
```

### 2. Configure the Matter Server address

Edit `matter_add.sh` and set `MATTER_WS_URL` to match your setup:

```bash
MATTER_WS_URL="${MATTER_WS_URL:-ws://<YOUR_MATTER_SERVER_IP>:5580/ws}"
```

Or pass it as an environment variable at runtime:

```bash
MATTER_WS_URL="ws://192.168.1.42:5580/ws" bash matter_add.sh <CODE>
```

### 3. Enable BLE proxy on the Matter Server

Add `--ble-proxy` to your Matter Server arguments (NixOS example):

```nix
extraArgs = [
  # your existing args…
  "--ble-proxy"
];
```

Then rebuild:

```bash
sudo nixos-rebuild switch
```

### 4. Configure your ESP32 as a BLE proxy (ESPHome)

```yaml
bluetooth_proxy:
  active: true
```

---

## Usage

Put the device into pairing/commissioning mode (factory reset or pairing button), then run:

```bash
bash matter_add.sh <MATTER_CODE>
```

**Accepted code formats:**

| Format | Example |
|--------|---------|
| 11-digit manual code (dashes optional) | `3094-735-5723` or `30947355723` |
| QR pairing code | `MT:Y3JH12AB34CD` |

**Example output:**

```
Commissioning Matter device '30947355723' …
WebSocket : ws://10.50.41.165:5580/ws
(Please wait — up to 5 minutes…)

=== Server response ===
[SUCCESS] Matter.js confirmed commissioning.

✅ Commissioning successful! The device should appear in Home Assistant.
```

The commissioned device automatically appears in Home Assistant — no additional pairing step required.

---

## How it works

1. The script validates and cleans the pairing code (strips dashes from numeric codes).
2. It locates `python3.13` and `websocket-client` directly in the Nix store — **no `nix-shell` invocation** (avoids ~25s startup overhead).
3. It opens a WebSocket connection to the Matter Server and sends `commission_with_code` with `network_only: false`.
4. The Matter Server uses the **BLE proxy** (Home Assistant → ESPHome ESP32) to discover and commission the device over Bluetooth.
5. The device receives Wi-Fi credentials during commissioning — **no password is ever passed on the command line**.
6. On success, the script exits `0` and the device is immediately visible in Home Assistant.

---

## Security notes

- The Matter Server WebSocket (`tcp/5580`) has **no built-in authentication**. Restrict access to trusted networks only (admin VLAN, local bridge).
- Wi-Fi credentials are **never passed** as command-line arguments — the Matter Server holds them internally.
- The script runs as a regular user (not root).

---

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `discovery of node with discriminator X failed` | Device not in pairing mode, or BLE proxy inactive | Put device in pairing mode; verify `--ble-proxy` flag |
| `WebSocket connection unavailable` | Matter Server unreachable at `MATTER_WS_URL` | Check IP, port 5580, firewall rules |
| `python3.13 not found in Nix store` | `python3` missing from NixOS config | Add `python3` + `python3Packages.websocket-client` to `environment.systemPackages` |
| `BLE proxy WebSocket connection ended` (HA log) | ESP32 BLE proxy dropped during CASE handshake | Move ESP32 closer to device; retry |

---

## Architecture (NixOS context)

```
workstation
    │  ssh
    ▼
nixcenter (NixOS server)
    │  matter_add.sh → WebSocket ws://<matter-vm>:5580/ws
    ▼
matter-js VM (libvirt/QEMU)
    │  --ble-proxy → WebSocket /ble
    ▼
Home Assistant (Podman rootless)
    │  ESPHome BLE proxy integration
    ▼
ESP32 (bluetooth_proxy: active: true)
    │  BLE
    ▼
Matter device → node commissioned ✅
```

---

*All rights reserved — © 2026 lotus-z-dev*
