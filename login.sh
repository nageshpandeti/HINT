export VAULT_ADDR='http://127.0.0.1:8200'

# Unseal with 3 keys
echo "j2e08LUmuBDvZYeRENJU3hvUa2eOiRBrDsExHJID5Xz0" | vault operator unseal -
echo "t6WEYi4fSP6mu4u2ve7vMjEzeVB/Xh7Y1SZ2b6Z809Vt" | vault operator unseal -
echo "CJY6LHVJKnARRIevkqxFu/cxgohRS3mdmRrZPQbEo12S" | vault operator unseal -

# Login with Root Token
vault login hvs.BOIlccFZ25g3r3UUgtf1rGoR
