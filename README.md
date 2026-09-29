# matter-commission-cli

> **CLI tool to commission Matter devices via the Matter Server WebSocket API — without the Home Assistant UI.**  
> **Outil CLI pour appairage d'appareils Matter via l'API WebSocket du Matter Server — sans passer par l'interface Home Assistant.**

---

## Overview / Présentation

`matter_add.sh` is a small Bash script that commissions a Matter device directly from the command line. It connects to the [Matter Server (matter.js)](https://github.com/home-assistant-libs/python-matter-server) WebSocket API and sends a `commission_with_code` command, bypassing the Home Assistant / Google Home pairing flow entirely.

`matter_add.sh` est un script Bash minimaliste qui appaire un appareil Matter directement depuis la ligne de commande. Il se connecte à l'API WebSocket du [Matter Server (matter.js)](https://github.com/home-assistant-libs/python-matter-server) et envoie une commande `commission_with_code`, sans passer par le parcours d'ajout de Home Assistant ou Google Home.

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

## Requirements / Prérequis

| Component | Version |
|-----------|---------|
| NixOS | 25.x / unstable |
| [Matter Server](https://github.com/home-assistant-libs/python-matter-server) | ≥ 2026.6 |
| Home Assistant | ≥ 2026.6 |
| ESPHome | ≥ 2026.5 (BLE proxy) |
| Python 3.13 + `websocket-client` | In Nix store |

The script uses **Python 3.13 and `websocket-client` already present in the Nix store** — no `nix-shell`, no extra install.

Le script utilise **Python 3.13 et `websocket-client` déjà présents dans le store Nix** — pas de `nix-shell`, pas d'installation supplémentaire.

Ensure your NixOS configuration includes:

```nix
environment.systemPackages = with pkgs; [
  python3
  python3Packages.websocket-client
];
```

---

## Setup / Configuration

### 1. Clone the repository

```bash
git clone https://github.com/<your-username>/matter-commission-cli.git
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
# In your matter server NixOS module
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

## Usage / Utilisation

Put the device into pairing/commissioning mode (factory reset or pairing button), then run:

Mettez l'appareil en mode pairing (reset usine ou bouton dédié), puis lancez :

```bash
bash matter_add.sh <MATTER_CODE>
```

**Accepted code formats / Formats acceptés :**

| Format | Example / Exemple |
|--------|-------------------|
| 11-digit manual code (dashes optional) | `3094-735-5723` or `30947355723` |
| QR pairing code | `MT:Y3JH12AB34CD` |

**Example output / Exemple de sortie :**

```
Commissioning Matter device '30947355723' …
WebSocket : ws://10.50.41.165:5580/ws
(Please wait — up to 5 minutes…)

=== Server response ===
[SUCCESS] Matter.js confirmed commissioning.

✅ Commissioning successful! The device should appear in Home Assistant.
```

The commissioned device automatically appears in Home Assistant — no additional pairing step required.

L'appareil commissionné apparaît automatiquement dans Home Assistant — aucune étape d'appairage supplémentaire requise.

---

## How it works / Fonctionnement

1. The script validates and cleans the pairing code (strips dashes from numeric codes).
2. It locates `python3.13` and `websocket-client` directly in the Nix store — **no `nix-shell` invocation** (would add ~25s startup delay).
3. It opens a WebSocket connection to the Matter Server and sends `commission_with_code` with `network_only: false`.
4. The Matter Server uses the **BLE proxy** (Home Assistant → ESPHome ESP32) to discover and commission the device over Bluetooth.
5. The device receives the Wi-Fi credentials during commissioning — **no password is ever passed on the command line**.
6. On success, the script exits `0` and the device is immediately visible in Home Assistant.

---

## Security notes / Notes de sécurité

- The Matter Server WebSocket (`tcp/5580`) has **no built-in authentication**. Restrict access to trusted networks only (e.g. admin VLAN, local bridge).
- Wi-Fi credentials are **never passed** as command-line arguments — the Matter Server holds them internally.
- The script runs as a regular user (not root). The Matter Server socket is accessible to the `nixcenter` user only.

---

## Troubleshooting / Dépannage

| Error | Cause | Fix |
|-------|-------|-----|
| `[FAILED] discovery of node with discriminator X failed` | Device not in pairing mode, or BLE proxy not active | Put device in pairing mode; check `--ble-proxy` flag |
| `[FAILED] WebSocket connection unavailable` | Matter Server not reachable at `MATTER_WS_URL` | Check IP, port 5580, firewall rules |
| `[ERROR] python3.13 not found in Nix store` | `python3` not in NixOS config | Add `python3` and `python3Packages.websocket-client` to `environment.systemPackages` |
| `BLE proxy WebSocket connection ended` (HA log) | ESP32 BLE proxy dropped during CASE handshake | Move ESP32 closer to device; retry |

---

## Architecture (NixOS context)

```
crostini-brya (dev workstation)
      │  ssh
      ▼
nixcenter (NixOS server)
      │  matter_add.sh
      │  WebSocket ws://10.50.41.165:5580/ws
      ▼
matter-js VM (libvirt/QEMU, VLAN 41)
      │  --ble-proxy
      │  WebSocket /ble
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

## Contributing / Contribuer

Pull requests and issues welcome.  
Les contributions et rapports de bugs sont les bienvenus.

---

*All rights reserved — © 2026*
