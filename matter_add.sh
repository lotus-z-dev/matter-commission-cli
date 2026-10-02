#!/usr/bin/env bash
# ============================================================
# matter_add.sh – Commissionnement d'un appareil Matter
# Appel direct de Python + websocket-client depuis le store Nix.
# Connexion directe au WebSocket du Matter Server dans la VM.
#
# Usage : matter_add.sh <CODE_MATTER>
#
# Formats acceptés :
#   - 11 chiffres (avec ou sans tirets) : 3676-785-5563 ou 36767855563
#   - QR code Matter                    : MT:XXXXXXXXXX
# ============================================================
set -euo pipefail

MATTER_WS_URL="ws://99.99.99.999:5580/ws"
MATTER_CODE="${1:-}"

# ---- Validation de l'argument ----
if [[ -z "$MATTER_CODE" ]]; then
  echo "Usage: $0 <CODE_MATTER>"
  echo ""
  echo "Formats acceptés :"
  echo "  11 chiffres (avec ou sans tirets) : 3094-735-5723 ou 30947355723"
  echo "  QR code Matter                    : MT:XXXXXXXXXX"
  exit 1
fi

# Retirer les tirets éventuels pour les codes manuels numériques
CLEANED_CODE="${MATTER_CODE//-/}"

# ---- Validation du format ----
if [[ "$CLEANED_CODE" =~ ^MT:[A-Z0-9.+/*-]{8,256}$ ]]; then
  SEND_CODE="$CLEANED_CODE"
elif [[ "$CLEANED_CODE" =~ ^[0-9]{11}$ ]]; then
  SEND_CODE="$CLEANED_CODE"
else
  echo "[ERREUR] Format de code Matter invalide."
  echo "  Reçu    : '$MATTER_CODE'"
  echo "  Nettoyé : '$CLEANED_CODE'"
  echo ""
  echo "  Formats valides :"
  echo "    - 11 chiffres consécutifs (ex: 30947355723)"
  echo "    - Code QR Matter (ex: MT:Y3JH...)"
  exit 1
fi

# ---- Localisation de Python et websocket-client dans le store Nix ----
# On cherche directement dans le store pour éviter nix-shell (trop lent).
PYTHON_BIN=$(find /nix/store -maxdepth 3 -path '*/bin/python3.13' -type f 2>/dev/null | head -n1)
WEBSOCKET_LIB=$(find /nix/store -maxdepth 1 -name '*python3.13-websocket-client*' -not -name '*.drv' 2>/dev/null | head -n1)

if [[ -z "$PYTHON_BIN" || ! -x "$PYTHON_BIN" ]]; then
  echo "[ERREUR] Python 3.13 introuvable dans le store Nix."
  exit 1
fi

if [[ -z "$WEBSOCKET_LIB" ]]; then
  echo "[ERREUR] websocket-client introuvable dans le store Nix."
  exit 1
fi

# PYTHONPATH vers le répertoire site-packages de websocket-client
WEBSOCKET_SITEPKGS="${WEBSOCKET_LIB}/lib/python3.13/site-packages"

if [[ ! -d "$WEBSOCKET_SITEPKGS" ]]; then
  echo "[ERREUR] site-packages de websocket-client introuvable : $WEBSOCKET_SITEPKGS"
  exit 1
fi

# ---- Exécution du commissionnement ----
echo "Commissionnement de l'appareil Matter '$SEND_CODE' …"
echo "WebSocket : $MATTER_WS_URL"
echo "(patientez, durée maximale 5 minutes…)"
echo ""

RESPONSE=$(PYTHONPATH="$WEBSOCKET_SITEPKGS" "$PYTHON_BIN" - <<PYEOF
import json, re, sys, time
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
            print("[SUCCÈS] Matter.js confirme la réussite de la commission.")
            sys.exit(0)
        print("[ÉCHEC] Matter.js a retourné une erreur : " + json.dumps(msg))
        sys.exit(2)
    print("[ÉCHEC] Aucune réponse de commissionnement après 5 minutes.")
    sys.exit(3)
except WebSocketException as e:
    print("[ÉCHEC] Connexion WebSocket indisponible : " + str(e))
    sys.exit(4)
finally:
    try:
        ws.close()
    except Exception:
        pass
PYEOF
) || EXIT_CODE=$?

echo "=== Réponse du serveur ==="
echo "$RESPONSE"

# ---- Interprétation du résultat ----
if echo "$RESPONSE" | grep -q "\[SUCCÈS\]"; then
  echo ""
  echo "✅ Commission réussie ! L'appareil devrait apparaître dans Home Assistant."
  exit 0
elif echo "$RESPONSE" | grep -q "\[ÉCHEC\]"; then
  echo ""
  echo "❌ Échec du commissionnement."
  echo "   Cause probable : code expiré/fictif, appareil pas en mode pairing, ou BLE proxy inactif."
  exit 2
else
  echo ""
  echo "⚠️  Réponse inattendue."
  exit 3
fi
