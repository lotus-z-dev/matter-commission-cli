#!/usr/bin/env bash
# ============================================================
# matter_add.sh – Commission a Matter device via CLI
#                 Commissionnement d'un appareil Matter en CLI
#
# Usage: matter_add.sh <MATTER_CODE>
#
# Accepted formats / Formats acceptés :
#   - 11-digit manual code (with or without dashes): 3094-735-5723 or 30947355723
#   - QR pairing code: MT:XXXXXXXXXX
#
# Requirements / Prérequis :
#   - NixOS with a running Matter Server (matter.js) reachable via WebSocket
#   - python3.13 and python3.13-websocket-client present in the Nix store
#   - BLE proxy active in Matter Server (--ble-proxy) and ESPHome ESP32 proxy
#
# Configure MATTER_WS_URL below to match your Matter Server address.
# Configurez MATTER_WS_URL ci-dessous avec l'adresse de votre Matter Server.
# ============================================================
set -euo pipefail

# ---- Configuration ----
# WebSocket URL of the Matter Server (inside the VM or on the host)
# URL WebSocket du Matter Server (dans la VM ou sur l'hôte)
MATTER_WS_URL="${MATTER_WS_URL:-ws://10.50.41.165:5580/ws}"

MATTER_CODE="${1:-}"

# ---- Argument validation / Validation de l'argument ----
if [[ -z "$MATTER_CODE" ]]; then
  echo "Usage: $0 <MATTER_CODE>"
  echo ""
  echo "Accepted formats:"
  echo "  11-digit manual code (dashes optional): 3094-735-5723 or 30947355723"
  echo "  QR pairing code:                        MT:XXXXXXXXXX"
  exit 1
fi

# Strip dashes from numeric manual codes / Retirer les tirets des codes numériques
CLEANED_CODE="${MATTER_CODE//-/}"

# ---- Format validation / Validation du format ----
if [[ "$CLEANED_CODE" =~ ^MT:[A-Z0-9.+/*-]{8,256}$ ]]; then
  SEND_CODE="$CLEANED_CODE"
elif [[ "$CLEANED_CODE" =~ ^[0-9]{11}$ ]]; then
  SEND_CODE="$CLEANED_CODE"
else
  echo "[ERROR] Invalid Matter code format."
  echo "  Received : '$MATTER_CODE'"
  echo "  Cleaned  : '$CLEANED_CODE'"
  echo ""
  echo "  Valid formats:"
  echo "    - 11 consecutive digits (e.g. 30947355723)"
  echo "    - Matter QR code       (e.g. MT:Y3JH...)"
  exit 1
fi

# ---- Locate Python and websocket-client in the Nix store ----
# Avoid nix-shell (too slow); use already-cached binaries directly.
# Éviter nix-shell (trop lent) ; utiliser directement les binaires en cache.
PYTHON_BIN=$(find /nix/store -maxdepth 3 -path '*/bin/python3.13' -type f 2>/dev/null | head -n1)
WEBSOCKET_LIB=$(find /nix/store -maxdepth 1 -name '*python3.13-websocket-client*' -not -name '*.drv' 2>/dev/null | head -n1)

if [[ -z "$PYTHON_BIN" || ! -x "$PYTHON_BIN" ]]; then
  echo "[ERROR] python3.13 not found in the Nix store."
  echo "  Ensure python3 and python3Packages.websocket-client are in your NixOS configuration."
  exit 1
fi

if [[ -z "$WEBSOCKET_LIB" ]]; then
  echo "[ERROR] websocket-client not found in the Nix store."
  echo "  Ensure python3Packages.websocket-client is in your NixOS configuration."
  exit 1
fi

WEBSOCKET_SITEPKGS="${WEBSOCKET_LIB}/lib/python3.13/site-packages"

if [[ ! -d "$WEBSOCKET_SITEPKGS" ]]; then
  echo "[ERROR] websocket-client site-packages not found: $WEBSOCKET_SITEPKGS"
  exit 1
fi

# ---- Commission the device / Commissionnement ----
echo "Commissioning Matter device '$SEND_CODE' …"
echo "WebSocket : $MATTER_WS_URL"
echo "(Please wait — up to 5 minutes / Patientez — jusqu'à 5 minutes…)"
echo ""

RESPONSE=$(PYTHONPATH="$WEBSOCKET_SITEPKGS" "$PYTHON_BIN" - <<PYEOF
import json, sys, time
from websocket import WebSocketException, WebSocketTimeoutException, create_connection

code = "$SEND_CODE"
request = {
    "message_id": "commission",
    "command": "commission_with_code",
    "args": {"code": code, "network_only": False},
}

try:
    ws = create_connection("$MATTER_WS_URL", timeout=10)
    ws.settimeout(5)
    ws.send(json.dumps(request))
    deadline = time.monotonic() + 300
    while time.monotonic() < deadline:
        try:
            payload = ws.recv()
        except WebSocketTimeoutException:
            continue
        if not payload:
            break
        try:
            msg = json.loads(payload)
        except json.JSONDecodeError:
            continue
        if msg.get("message_id") != "commission":
            continue
        if "result" in msg:
            print("[SUCCESS] Matter.js confirmed commissioning.")
            sys.exit(0)
        print("[FAILED] Matter.js returned an error: " + json.dumps(msg))
        sys.exit(2)
    print("[FAILED] No commissioning response after 5 minutes.")
    sys.exit(3)
except WebSocketException as e:
    print("[FAILED] WebSocket connection unavailable: " + str(e))
    sys.exit(4)
finally:
    try:
        ws.close()
    except Exception:
        pass
PYEOF
) || EXIT_CODE=$?

echo "=== Server response ==="
echo "$RESPONSE"

if echo "$RESPONSE" | grep -q "\[SUCCESS\]"; then
  echo ""
  echo "✅ Commissioning successful! The device should appear in Home Assistant."
  exit 0
elif echo "$RESPONSE" | grep -q "\[FAILED\]"; then
  echo ""
  echo "❌ Commissioning failed."
  echo "   Likely cause: expired/invalid code, device not in pairing mode, or BLE proxy inactive."
  exit 2
else
  echo ""
  echo "⚠️  Unexpected response."
  exit 3
fi
