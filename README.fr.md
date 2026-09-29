# matter-commission-cli

> Outil CLI pour appairage d'appareils Matter via l'API WebSocket du Matter Server — sans passer par l'interface Home Assistant.

[![Shell](https://img.shields.io/badge/shell-bash-green)](https://www.gnu.org/software/bash/)
[![NixOS](https://img.shields.io/badge/NixOS-25.x%2Funstable-blue)](https://nixos.org/)
[![Matter](https://img.shields.io/badge/Matter-1.x-purple)](https://buildwithmatter.com/)

🇬🇧 [English version](README.md)

---

## Présentation

`matter_add.sh` est un script Bash minimaliste qui appaire un appareil Matter directement depuis la ligne de commande. Il se connecte à l'API WebSocket du [Matter Server (matter.js)](https://github.com/home-assistant-libs/python-matter-server) et envoie une commande `commission_with_code`, sans passer par le parcours d'ajout de Home Assistant ou Google Home.

```
matter_add.sh <CODE>
      │
      ▼
Python + websocket-client (store Nix, démarrage ~2s)
      │
      ▼
ws://<matter-server>:5580/ws
      │
      ▼
Proxy BLE (Home Assistant → ESPHome ESP32)
      │  BLE
      ▼
Appareil Matter → commissionné ✅ → visible dans Home Assistant
```

---

## Prérequis

| Composant | Version |
|-----------|---------|
| NixOS | 25.x / unstable |
| [Matter Server](https://github.com/home-assistant-libs/python-matter-server) | ≥ 2026.6 |
| Home Assistant | ≥ 2026.6 |
| ESPHome | ≥ 2026.5 (proxy BLE) |
| Python 3.13 + `websocket-client` | Présent dans le store Nix |

Le script utilise **Python 3.13 et `websocket-client` déjà présents dans le store Nix** — pas de `nix-shell`, pas d'installation supplémentaire, démarrage en ~2s.

Assurez-vous que votre configuration NixOS inclut :

```nix
environment.systemPackages = with pkgs; [
  python3
  python3Packages.websocket-client
];
```

---

## Installation

### 1. Cloner le dépôt

```bash
git clone https://github.com/lotus-z-dev/matter-commission-cli.git
cd matter-commission-cli
chmod +x matter_add.sh
```

### 2. Configurer l'adresse du Matter Server

Éditez `matter_add.sh` et ajustez `MATTER_WS_URL` :

```bash
MATTER_WS_URL="${MATTER_WS_URL:-ws://<VOTRE_IP_MATTER_SERVER>:5580/ws}"
```

Ou passez-la comme variable d'environnement à l'exécution :

```bash
MATTER_WS_URL="ws://192.168.1.42:5580/ws" bash matter_add.sh <CODE>
```

### 3. Activer le proxy BLE sur le Matter Server

Ajoutez `--ble-proxy` aux arguments du Matter Server (exemple NixOS) :

```nix
extraArgs = [
  # vos arguments existants…
  "--ble-proxy"
];
```

Puis reconstruisez :

```bash
sudo nixos-rebuild switch
```

### 4. Configurer l'ESP32 comme proxy BLE (ESPHome)

```yaml
bluetooth_proxy:
  active: true
```

---

## Utilisation

Mettez l'appareil en mode pairing (reset usine ou bouton dédié), puis lancez :

```bash
bash matter_add.sh <CODE_MATTER>
```

**Formats de code acceptés :**

| Format | Exemple |
|--------|---------|
| Code manuel 11 chiffres (tirets optionnels) | `3094-735-5723` ou `30947355723` |
| Code QR Matter | `MT:Y3JH12AB34CD` |

**Exemple de sortie :**

```
Commissioning Matter device '30947355723' …
WebSocket : ws://10.50.41.165:5580/ws
(Please wait — up to 5 minutes…)

=== Server response ===
[SUCCESS] Matter.js confirmed commissioning.

✅ Commissioning successful! The device should appear in Home Assistant.
```

L'appareil commissionné apparaît automatiquement dans Home Assistant — aucune étape supplémentaire requise.

---

## Fonctionnement

1. Le script valide et nettoie le code d'appairage (supprime les tirets des codes numériques).
2. Il localise `python3.13` et `websocket-client` directement dans le store Nix — **sans `nix-shell`** (évite ~25s de délai de démarrage).
3. Il ouvre une connexion WebSocket vers le Matter Server et envoie `commission_with_code` avec `network_only: false`.
4. Le Matter Server utilise le **proxy BLE** (Home Assistant → ESPHome ESP32) pour découvrir et commissionner l'appareil via Bluetooth.
5. L'appareil reçoit les identifiants Wi-Fi pendant le commissionnement — **aucun mot de passe n'est jamais passé en ligne de commande**.
6. En cas de succès, le script retourne le code `0` et l'appareil est immédiatement visible dans Home Assistant.

---

## Sécurité

- Le WebSocket du Matter Server (`tcp/5580`) **n'a pas d'authentification intégrée**. Restreignez l'accès aux réseaux de confiance uniquement (VLAN admin, bridge local).
- Les identifiants Wi-Fi ne sont **jamais transmis** en arguments de ligne de commande — le Matter Server les détient en interne.
- Le script s'exécute en tant qu'utilisateur normal (sans sudo).

---

## Dépannage

| Erreur | Cause | Solution |
|--------|-------|----------|
| `discovery of node with discriminator X failed` | Appareil pas en mode pairing, ou proxy BLE inactif | Mettre l'appareil en mode pairing ; vérifier le flag `--ble-proxy` |
| `WebSocket connection unavailable` | Matter Server inaccessible à `MATTER_WS_URL` | Vérifier l'IP, le port 5580, les règles de pare-feu |
| `python3.13 not found in Nix store` | `python3` absent de la config NixOS | Ajouter `python3` + `python3Packages.websocket-client` à `environment.systemPackages` |
| `BLE proxy WebSocket connection ended` (log HA) | Proxy BLE ESP32 déconnecté pendant le handshake CASE | Rapprocher l'ESP32 de l'appareil ; réessayer |

---

## Architecture (contexte NixOS)

```
poste de travail
    │  ssh
    ▼
nixcenter (serveur NixOS)
    │  matter_add.sh → WebSocket ws://<matter-vm>:5580/ws
    ▼
VM matter-js (libvirt/QEMU)
    │  --ble-proxy → WebSocket /ble
    ▼
Home Assistant (Podman rootless)
    │  intégration proxy BLE ESPHome
    ▼
ESP32 (bluetooth_proxy: active: true)
    │  BLE
    ▼
Appareil Matter → nœud commissionné ✅
```

---

*Tous droits réservés — © 2026 lotus-z-dev*
