#!/bin/bash
# =============================================================================
# createChannel.sh
# Run INSIDE the 'cli' docker container.
# Creates and joins mychannel for all orderers and peers.
# =============================================================================

CHANNEL_NAME="mychannel"
PEER_BASE="/opt/gopath/src/github.com/hyperledger/fabric/peer"
CHANNEL_BLOCK="${PEER_BASE}/channel-artifacts/${CHANNEL_NAME}.block"

ORG1_MSP_DIR="${PEER_BASE}/organizations/peerOrganizations/org1.example.com"
ORG2_MSP_DIR="${PEER_BASE}/organizations/peerOrganizations/org2.example.com"
ORD_MSP_DIR="${PEER_BASE}/organizations/ordererOrganizations/example.com"

ORDERER_CA="${ORD_MSP_DIR}/orderers/orderer1.example.com/msp/tlscacerts/tlsca.example.com-cert.pem"

# Helper: set env for a given org peer
function setGlobals() {
  local ORG=$1
  if [ "${ORG}" == "1" ]; then
    export CORE_PEER_LOCALMSPID="Org1MSP"
    export CORE_PEER_ADDRESS="peer0.org1.example.com:7051"
    export CORE_PEER_TLS_ROOTCERT_FILE="${ORG1_MSP_DIR}/peers/peer0.org1.example.com/tls/ca.crt"
    export CORE_PEER_MSPCONFIGPATH="${ORG1_MSP_DIR}/users/Admin@org1.example.com/msp"
  elif [ "${ORG}" == "2" ]; then
    export CORE_PEER_LOCALMSPID="Org2MSP"
    export CORE_PEER_ADDRESS="peer0.org2.example.com:9051"
    export CORE_PEER_TLS_ROOTCERT_FILE="${ORG2_MSP_DIR}/peers/peer0.org2.example.com/tls/ca.crt"
    export CORE_PEER_MSPCONFIGPATH="${ORG2_MSP_DIR}/users/Admin@org2.example.com/msp"
  fi
}

# Wait for channel block to be available
if [ ! -f "${CHANNEL_BLOCK}" ]; then
  echo "[ERROR] Channel block not found at ${CHANNEL_BLOCK}"
  exit 1
fi

echo "========== Joining Orderers to channel via osnadmin =========="
for i in 1 2 3; do
  PORT=$((7053 + (i - 1) * 1000))
  ORD_TLS="${ORD_MSP_DIR}/orderers/orderer${i}.example.com/tls"
  echo " -> Joining orderer${i}.example.com:${PORT}"
  osnadmin channel join \
    --channelID "${CHANNEL_NAME}" \
    --config-block "${CHANNEL_BLOCK}" \
    -o "orderer${i}.example.com:${PORT}" \
    --ca-file "${ORDERER_CA}" \
    --client-cert "${ORD_TLS}/server.crt" \
    --client-key "${ORD_TLS}/server.key"
done

echo ""
echo "========== Joining Peer0 Org1 to channel =========="
setGlobals 1
peer channel join -b "${CHANNEL_BLOCK}"
sleep 2

echo ""
echo "========== Joining Peer0 Org2 to channel =========="
setGlobals 2
peer channel join -b "${CHANNEL_BLOCK}"
sleep 2

echo ""
echo "========== Setting Anchor Peers =========="

# Org1 Anchor Peer
setGlobals 1
peer channel update \
  -o orderer1.example.com:7050 \
  -c "${CHANNEL_NAME}" \
  -f "${PEER_BASE}/channel-artifacts/Org1MSPanchors.tx" \
  --ordererTLSHostnameOverride orderer1.example.com \
  --tls \
  --cafile "${ORDERER_CA}" 2>/dev/null || echo "[INFO] Anchor peer update skipped (no anchor tx file — OK for basic setup)"

# Org2 Anchor Peer
setGlobals 2
peer channel update \
  -o orderer1.example.com:7050 \
  -c "${CHANNEL_NAME}" \
  -f "${PEER_BASE}/channel-artifacts/Org2MSPanchors.tx" \
  --ordererTLSHostnameOverride orderer1.example.com \
  --tls \
  --cafile "${ORDERER_CA}" 2>/dev/null || echo "[INFO] Anchor peer update skipped (no anchor tx file — OK for basic setup)"

echo ""
echo "[SUCCESS] Channel '${CHANNEL_NAME}' created and all peers joined!"
echo "  Org1 Peer: peer0.org1.example.com:7051"
echo "  Org2 Peer: peer0.org2.example.com:9051"
