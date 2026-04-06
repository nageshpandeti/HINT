#!/bin/bash

# =============================================================
#  Vault Reset + Reinitialize + Unseal Script
#  Usage: sudo ./reset_vault.sh
# =============================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()   { echo -e "${GREEN}[INFO]${NC}  $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

export VAULT_ADDR='http://127.0.0.1:8200'

# =============================================================
# STEP 1: Stop Vault & Clean Data
# =============================================================
log "Step 1: Stopping Vault and cleaning old data..."
systemctl stop vault
rm -rf /var/vault/data/*
log "Old Vault data cleared."

# =============================================================
# STEP 2: Start Vault Fresh
# =============================================================
log "Step 2: Starting Vault fresh..."
systemctl start vault
sleep 5
log "Vault started."

# =============================================================
# STEP 3: Initialize Vault & Save Keys
# =============================================================
log "Step 3: Initializing Vault..."
INIT_OUTPUT=$(vault operator init 2>&1)

if echo "$INIT_OUTPUT" | grep -q "Unseal Key 1"; then
  log "Vault initialized successfully!"
else
  echo "$INIT_OUTPUT"
  error "Vault initialization failed!"
fi

# ── Parse Keys from init output ───────────────────────────────
KEY1=$(echo "$INIT_OUTPUT" | grep "Unseal Key 1" | awk '{print $NF}' | tr -d '[:space:]')
KEY2=$(echo "$INIT_OUTPUT" | grep "Unseal Key 2" | awk '{print $NF}' | tr -d '[:space:]')
KEY3=$(echo "$INIT_OUTPUT" | grep "Unseal Key 3" | awk '{print $NF}' | tr -d '[:space:]')
KEY4=$(echo "$INIT_OUTPUT" | grep "Unseal Key 4" | awk '{print $NF}' | tr -d '[:space:]')
KEY5=$(echo "$INIT_OUTPUT" | grep "Unseal Key 5" | awk '{print $NF}' | tr -d '[:space:]')
TOKEN=$(echo "$INIT_OUTPUT" | grep "Initial Root Token" | awk '{print $NF}' | tr -d '[:space:]')

# ── Save Keys to File ─────────────────────────────────────────
rm -f /home/ubuntu/key.txt
printf "Key1: %s\n" "$KEY1" >> /home/ubuntu/key.txt
printf "Key2: %s\n" "$KEY2" >> /home/ubuntu/key.txt
printf "Key3: %s\n" "$KEY3" >> /home/ubuntu/key.txt
printf "Key4: %s\n" "$KEY4" >> /home/ubuntu/key.txt
printf "Key5: %s\n" "$KEY5" >> /home/ubuntu/key.txt
printf "Token: %s\n" "$TOKEN" >> /home/ubuntu/key.txt

log "Keys saved to /home/ubuntu/key.txt"
echo ""
echo "=============================="
echo "  YOUR VAULT KEYS (SAVE NOW!)"
echo "=============================="
cat /home/ubuntu/key.txt
echo "=============================="

# =============================================================
# STEP 4: Unseal Vault with 3 Keys
# =============================================================
log "Step 4: Unsealing Vault..."

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
  error "Vault is still sealed! Something went wrong."
fi

# =============================================================
# STEP 5: Login
# =============================================================
log "Step 5: Logging into Vault..."
vault login "$TOKEN"

# =============================================================
# STEP 6: Get VM IP & Show UI URL
# =============================================================
VM_IP=$(ip a | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | cut -d'/' -f1 | head -1)

echo ""
echo "================================================"
echo -e "  ${GREEN}Vault is Ready! ✅${NC}"
echo "================================================"
echo ""
echo "  Vault Status  : UNSEALED ✅"
echo "  Vault Version : $(vault version)"
echo ""
echo "  Vault UI URL  : http://${VM_IP}:8200/ui"
echo "  Local URL     : http://127.0.0.1:8200/ui"
echo ""
echo "  Login Method  : Token"
echo "  Root Token    : $TOKEN"
echo ""
echo "================================================"
echo "  Keys saved at : /home/ubuntu/key.txt"
echo "  Open browser  : http://${VM_IP}:8200/ui"
echo "================================================"
