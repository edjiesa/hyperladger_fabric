#!/bin/bash

# Navigate to the correct directory
cd "$(dirname "$0")" || exit

echo "Locating Admin@org1's private key..."
KEY_DIR="../organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp/keystore"

if [ ! -d "$KEY_DIR" ]; then
    echo "ERROR: Keystore directory not found. Is your network up?"
    exit 1
fi

# Find the private key file and copy it as priv_sk
PRI_KEY=$(ls -t ${KEY_DIR}/*_sk 2>/dev/null | head -1)

if [ -z "$PRI_KEY" ]; then
    echo "ERROR: No private key found in ${KEY_DIR}"
    exit 1
fi

echo "Found private key: ${PRI_KEY}"
cp "${PRI_KEY}" "${KEY_DIR}/priv_sk"
echo "Prepared priv_sk for Explorer."

echo "Starting Hyperledger Explorer Profile..."
COMPOSE_CMD="${DOCKER_COMPOSE_PLUGIN:-docker compose}"
${COMPOSE_CMD} -f docker-compose-explorer.yaml up -d

echo "Explorer starting. It usually takes 15-30 seconds to fully initialize."
echo "Visit: http://localhost:8080"
echo "Login: admin / adminpw"
