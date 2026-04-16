#!/bin/bash

# Navigate to the correct directory
cd "$(dirname "$0")" || exit

echo "Locating Admin@org1's private key..."
KEY_DIR="../organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp/keystore"

if [ ! -d "$KEY_DIR" ]; then
    echo "ERROR: Keystore directory not found. Is your network up?"
    exit 1
fi

# Find the private key file (excluding the one we might have already named priv_sk)
PRI_KEY=$(find "${KEY_DIR}" -maxdepth 1 -name "*_sk" ! -name "priv_sk" 2>/dev/null | head -1)

if [ -z "$PRI_KEY" ]; then
    # If we only have priv_sk, that's fine too
    if [ -f "${KEY_DIR}/priv_sk" ]; then
        PRI_KEY="${KEY_DIR}/priv_sk"
    else
        echo "ERROR: No private key found in ${KEY_DIR}"
        exit 1
    fi
else
    echo "Found private key: ${PRI_KEY}"
    # Copy to priv_sk only if it's not already named that
    if [ "$(basename "$PRI_KEY")" != "priv_sk" ]; then
        cp "${PRI_KEY}" "${KEY_DIR}/priv_sk"
        echo "Prepared priv_sk for Explorer."
    fi
fi

echo "Starting Hyperledger Explorer Profile..."
COMPOSE_CMD="${DOCKER_COMPOSE_PLUGIN:-docker compose}"
${COMPOSE_CMD} -f docker-compose-explorer.yaml up -d --force-recreate

echo "Explorer starting. It usually takes 15-30 seconds to fully initialize."
echo "Visit: http://localhost:8080"
echo "Login: admin / adminpw"
