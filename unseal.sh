#!/bin/bash

# =============================================================
#  Vault Unseal Script - Reads keys from key.txt
#  Usage: chmod +x unseal.sh && sudo ./unseal.sh
# =============================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log()   { echo -e "${GREEN}[INFO]${NC}  $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ── Set Vault Address ─────────────────────────────────────────
export VAULT_ADDR='http://127.0.0.1:8200'

# ── Check key.txt exists ──────────────────────────────────────
KEY_FILE="/home/ubuntu/key.txt"

if [ ! -f "$KEY_FILE" ]; then
  error "key.txt not found at $KEY_FILE"
fi

log "Reading keys from $KEY_FILE..."
cat "$KEY_FILE"

# ── Read Keys from key.txt ────────────────────────────────────
KEY1=$(grep "Key1" "$KEY_FILE" | awk '{print $2}' | tr -d '[:space:]')
KEY2=$(grep "Key2" "$KEY_FILE" | awk '{print $2}' | tr -d '[:space:]')
KEY3=$(grep "Key3" "$KEY_FILE" | awk '{print $2}' | tr -d '[:space:]')
TOKEN=$(grep "Token" "$KEY_FILE" | awk '{print $2}' | tr -d '[:space:]')

# ── Validate Keys ─────────────────────────────────────────────
log "Validating keys..."
[ -z "$KEY1" ]  && error "Key1 not found in key.txt"
[ -z "$KEY2" ]  && error "Key2 not found in key.txt"
[ -z "$KEY3" ]  && error "Key3 not found in key.txt"
[ -z "$TOKEN" ] && error "Token not found in key.txt"

log "Keys loaded successfully!"
log "Key1  : $KEY1"
log "Key2  : $KEY2"
log "Key3  : $KEY3"
log "Token : $TOKEN"

# ── Start Vault if not running ────────────────────────────────
log "Checking Vault service..."
if ! systemctl is-active --quiet vault; then
  log "Starting Vault service..."
  sudo systemctl start vault
  sleep 3
fi
log "Vault service is running."

# ── Unseal Vault ──────────────────────────────────────────────
log "Unsealing with Key 1..."
vault operator unseal "$KEY1"

log "Unsealing with Key 2..."
vault operator unseal "$KEY2"

log "Unsealing with Key 3..."
vault operator unseal "$KEY3"

# ── Verify Unseal ─────────────────────────────────────────────
sleep 2
SEALED=$(vault status 2>/dev/null | grep "Sealed" | awk '{print $2}')

if [ "$SEALED" == "false" ]; then
  log "Vault is UNSEALED successfully! ✅"
else
  error "Vault is still sealed! Check keys in key.txt"
fi

# ── Login ─────────────────────────────────────────────────────
log "Logging into Vault..."
vault login "$TOKEN"

# ── Get VM IP ─────────────────────────────────────────────────
VM_IP=$(ip a | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | cut -d'/' -f1 | head -1)

# ── Done ──────────────────────────────────────────────────────
echo ""
echo "=============================================="
echo -e "  ${GREEN}Vault is Ready!${NC} ✅"
echo "=============================================="
echo ""
echo "  Status        : UNSEALED ✅"
echo "  Vault UI      : http://${VM_IP}:8200/ui"
echo "  Local URL     : http://127.0.0.1:8200/ui"
echo ""
echo "  Login Method  : Token"
echo "  Root Token    : $TOKEN"
echo ""
echo "=============================================="
echo "  Open in browser:"
echo "  http://${VM_IP}:8200/ui"
echo "=============================================="
