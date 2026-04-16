#!/bin/bash
# =============================================================================
# registerEnroll.sh
# Registers and enrolls all identities using Fabric CA
# Usage: ./registerEnroll.sh <NETWORK_ROOT_DIR>
# =============================================================================

NETWORK_ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"

# Fabric CA client binary must already be in PATH
if ! command -v fabric-ca-client &>/dev/null; then
  echo "[ERROR] fabric-ca-client not found in PATH"
  exit 1
fi

# Helper function — waits for a CA to be ready
function waitForCA() {
  local CA_URL=$1
  local CA_CERT=$2
  local MAX=10
  local i=0
  echo "  Waiting for CA at ${CA_URL}..."
  while [ $i -lt $MAX ]; do
    fabric-ca-client getcainfo -u "$CA_URL" --tls.certfiles "$CA_CERT" &>/dev/null && return 0
    sleep 2
    i=$((i + 1))
  done
  echo "[ERROR] CA at ${CA_URL} did not become ready in time."
  exit 1
}

# =============================================================================
# Org1
# =============================================================================
function createOrg1() {
  echo ""
  echo "============ Creating Org1 identities ============"
  local ORG1_DIR="${NETWORK_ROOT}/organizations/peerOrganizations/org1.example.com"
  local CA_CERT="${NETWORK_ROOT}/organizations/fabric-ca/org1/ca-cert.pem"
  local CA_URL="https://localhost:7054"

  mkdir -p "${ORG1_DIR}"
  export FABRIC_CA_CLIENT_HOME="${ORG1_DIR}"

  # Wait for CA to be ready
  waitForCA "${CA_URL}" "${CA_CERT}"

  echo " -> Enrolling CA admin for Org1"
  fabric-ca-client enroll \
    -u "https://admin:adminpw@localhost:7054" \
    --caname ca-org1 \
    --tls.certfiles "${CA_CERT}"

  # Write NodeOU config
  mkdir -p "${ORG1_DIR}/msp"
  cat > "${ORG1_DIR}/msp/config.yaml" <<EOF
NodeOUs:
  Enable: true
  ClientOUIdentifier:
    Certificate: cacerts/localhost-7054-ca-org1.pem
    OrganizationalUnitIdentifier: client
  PeerOUIdentifier:
    Certificate: cacerts/localhost-7054-ca-org1.pem
    OrganizationalUnitIdentifier: peer
  AdminOUIdentifier:
    Certificate: cacerts/localhost-7054-ca-org1.pem
    OrganizationalUnitIdentifier: admin
  OrdererOUIdentifier:
    Certificate: cacerts/localhost-7054-ca-org1.pem
    OrganizationalUnitIdentifier: orderer
EOF

  echo " -> Registering peer0 for Org1"
  fabric-ca-client register --caname ca-org1 \
    --id.name peer0 --id.secret peer0pw --id.type peer \
    --tls.certfiles "${CA_CERT}"

  echo " -> Registering admin for Org1"
  fabric-ca-client register --caname ca-org1 \
    --id.name org1admin --id.secret org1adminpw --id.type admin \
    --tls.certfiles "${CA_CERT}"

  echo " -> Enrolling peer0 MSP for Org1"
  fabric-ca-client enroll \
    -u "https://peer0:peer0pw@localhost:7054" \
    --caname ca-org1 \
    -M "${ORG1_DIR}/peers/peer0.org1.example.com/msp" \
    --csr.hosts peer0.org1.example.com \
    --tls.certfiles "${CA_CERT}"

  cp "${ORG1_DIR}/msp/config.yaml" \
     "${ORG1_DIR}/peers/peer0.org1.example.com/msp/config.yaml"

  echo " -> Enrolling peer0 TLS for Org1"
  fabric-ca-client enroll \
    -u "https://peer0:peer0pw@localhost:7054" \
    --caname ca-org1 \
    -M "${ORG1_DIR}/peers/peer0.org1.example.com/tls" \
    --enrollment.profile tls \
    --csr.hosts peer0.org1.example.com \
    --csr.hosts localhost \
    --tls.certfiles "${CA_CERT}"

  local PEER_TLS="${ORG1_DIR}/peers/peer0.org1.example.com/tls"
  cp "${PEER_TLS}/tlscacerts/"*   "${PEER_TLS}/ca.crt"
  cp "${PEER_TLS}/signcerts/"*    "${PEER_TLS}/server.crt"
  cp "${PEER_TLS}/keystore/"*     "${PEER_TLS}/server.key"

  mkdir -p "${ORG1_DIR}/msp/tlscacerts"
  cp "${PEER_TLS}/tlscacerts/"* "${ORG1_DIR}/msp/tlscacerts/ca.crt"

  mkdir -p "${ORG1_DIR}/tlsca"
  cp "${PEER_TLS}/tlscacerts/"* "${ORG1_DIR}/tlsca/tlsca.org1.example.com-cert.pem"

  mkdir -p "${ORG1_DIR}/ca"
  cp "${ORG1_DIR}/peers/peer0.org1.example.com/msp/cacerts/"* \
     "${ORG1_DIR}/ca/ca.org1.example.com-cert.pem"

  echo " -> Enrolling Org1 admin MSP"
  fabric-ca-client enroll \
    -u "https://org1admin:org1adminpw@localhost:7054" \
    --caname ca-org1 \
    -M "${ORG1_DIR}/users/Admin@org1.example.com/msp" \
    --tls.certfiles "${CA_CERT}"

  cp "${ORG1_DIR}/msp/config.yaml" \
     "${ORG1_DIR}/users/Admin@org1.example.com/msp/config.yaml"

  echo "   Org1 done."
}

# =============================================================================
# Org2
# =============================================================================
function createOrg2() {
  echo ""
  echo "============ Creating Org2 identities ============"
  local ORG2_DIR="${NETWORK_ROOT}/organizations/peerOrganizations/org2.example.com"
  local CA_CERT="${NETWORK_ROOT}/organizations/fabric-ca/org2/ca-cert.pem"

  mkdir -p "${ORG2_DIR}"
  export FABRIC_CA_CLIENT_HOME="${ORG2_DIR}"

  waitForCA "https://localhost:8054" "${CA_CERT}"

  echo " -> Enrolling CA admin for Org2"
  fabric-ca-client enroll \
    -u "https://admin:adminpw@localhost:8054" \
    --caname ca-org2 \
    --tls.certfiles "${CA_CERT}"

  mkdir -p "${ORG2_DIR}/msp"
  cat > "${ORG2_DIR}/msp/config.yaml" <<EOF
NodeOUs:
  Enable: true
  ClientOUIdentifier:
    Certificate: cacerts/localhost-8054-ca-org2.pem
    OrganizationalUnitIdentifier: client
  PeerOUIdentifier:
    Certificate: cacerts/localhost-8054-ca-org2.pem
    OrganizationalUnitIdentifier: peer
  AdminOUIdentifier:
    Certificate: cacerts/localhost-8054-ca-org2.pem
    OrganizationalUnitIdentifier: admin
  OrdererOUIdentifier:
    Certificate: cacerts/localhost-8054-ca-org2.pem
    OrganizationalUnitIdentifier: orderer
EOF

  echo " -> Registering peer0 for Org2"
  fabric-ca-client register --caname ca-org2 \
    --id.name peer0 --id.secret peer0pw --id.type peer \
    --tls.certfiles "${CA_CERT}"

  echo " -> Registering admin for Org2"
  fabric-ca-client register --caname ca-org2 \
    --id.name org2admin --id.secret org2adminpw --id.type admin \
    --tls.certfiles "${CA_CERT}"

  echo " -> Enrolling peer0 MSP for Org2"
  fabric-ca-client enroll \
    -u "https://peer0:peer0pw@localhost:8054" \
    --caname ca-org2 \
    -M "${ORG2_DIR}/peers/peer0.org2.example.com/msp" \
    --csr.hosts peer0.org2.example.com \
    --tls.certfiles "${CA_CERT}"

  cp "${ORG2_DIR}/msp/config.yaml" \
     "${ORG2_DIR}/peers/peer0.org2.example.com/msp/config.yaml"

  echo " -> Enrolling peer0 TLS for Org2"
  fabric-ca-client enroll \
    -u "https://peer0:peer0pw@localhost:8054" \
    --caname ca-org2 \
    -M "${ORG2_DIR}/peers/peer0.org2.example.com/tls" \
    --enrollment.profile tls \
    --csr.hosts peer0.org2.example.com \
    --csr.hosts localhost \
    --tls.certfiles "${CA_CERT}"

  local PEER_TLS="${ORG2_DIR}/peers/peer0.org2.example.com/tls"
  cp "${PEER_TLS}/tlscacerts/"*   "${PEER_TLS}/ca.crt"
  cp "${PEER_TLS}/signcerts/"*    "${PEER_TLS}/server.crt"
  cp "${PEER_TLS}/keystore/"*     "${PEER_TLS}/server.key"

  mkdir -p "${ORG2_DIR}/msp/tlscacerts"
  cp "${PEER_TLS}/tlscacerts/"* "${ORG2_DIR}/msp/tlscacerts/ca.crt"

  mkdir -p "${ORG2_DIR}/tlsca"
  cp "${PEER_TLS}/tlscacerts/"* "${ORG2_DIR}/tlsca/tlsca.org2.example.com-cert.pem"

  mkdir -p "${ORG2_DIR}/ca"
  cp "${ORG2_DIR}/peers/peer0.org2.example.com/msp/cacerts/"* \
     "${ORG2_DIR}/ca/ca.org2.example.com-cert.pem"

  echo " -> Enrolling Org2 admin MSP"
  fabric-ca-client enroll \
    -u "https://org2admin:org2adminpw@localhost:8054" \
    --caname ca-org2 \
    -M "${ORG2_DIR}/users/Admin@org2.example.com/msp" \
    --tls.certfiles "${CA_CERT}"

  cp "${ORG2_DIR}/msp/config.yaml" \
     "${ORG2_DIR}/users/Admin@org2.example.com/msp/config.yaml"

  echo "   Org2 done."
}

# =============================================================================
# Orderer Organization
# =============================================================================
function createOrderer() {
  echo ""
  echo "============ Creating Orderer identities ============"
  local ORD_DIR="${NETWORK_ROOT}/organizations/ordererOrganizations/example.com"
  local CA_CERT="${NETWORK_ROOT}/organizations/fabric-ca/ordererOrg/ca-cert.pem"

  mkdir -p "${ORD_DIR}"
  export FABRIC_CA_CLIENT_HOME="${ORD_DIR}"

  waitForCA "https://localhost:9054" "${CA_CERT}"

  echo " -> Enrolling CA admin for Orderer"
  fabric-ca-client enroll \
    -u "https://admin:adminpw@localhost:9054" \
    --caname ca-orderer \
    --tls.certfiles "${CA_CERT}"

  mkdir -p "${ORD_DIR}/msp"
  cat > "${ORD_DIR}/msp/config.yaml" <<EOF
NodeOUs:
  Enable: true
  ClientOUIdentifier:
    Certificate: cacerts/localhost-9054-ca-orderer.pem
    OrganizationalUnitIdentifier: client
  PeerOUIdentifier:
    Certificate: cacerts/localhost-9054-ca-orderer.pem
    OrganizationalUnitIdentifier: peer
  AdminOUIdentifier:
    Certificate: cacerts/localhost-9054-ca-orderer.pem
    OrganizationalUnitIdentifier: admin
  OrdererOUIdentifier:
    Certificate: cacerts/localhost-9054-ca-orderer.pem
    OrganizationalUnitIdentifier: orderer
EOF

  for i in 1 2 3; do
    echo " -> Registering orderer${i}"
    fabric-ca-client register --caname ca-orderer \
      --id.name "orderer${i}" --id.secret ordererpw --id.type orderer \
      --tls.certfiles "${CA_CERT}"
  done

  echo " -> Registering orderer admin"
  fabric-ca-client register --caname ca-orderer \
    --id.name ordererAdmin --id.secret ordererAdminpw --id.type admin \
    --tls.certfiles "${CA_CERT}"

  for i in 1 2 3; do
    echo " -> Enrolling orderer${i} MSP"
    fabric-ca-client enroll \
      -u "https://orderer${i}:ordererpw@localhost:9054" \
      --caname ca-orderer \
      -M "${ORD_DIR}/orderers/orderer${i}.example.com/msp" \
      --csr.hosts "orderer${i}.example.com" \
      --csr.hosts localhost \
      --tls.certfiles "${CA_CERT}"

    cp "${ORD_DIR}/msp/config.yaml" \
       "${ORD_DIR}/orderers/orderer${i}.example.com/msp/config.yaml"

    echo " -> Enrolling orderer${i} TLS"
    fabric-ca-client enroll \
      -u "https://orderer${i}:ordererpw@localhost:9054" \
      --caname ca-orderer \
      -M "${ORD_DIR}/orderers/orderer${i}.example.com/tls" \
      --enrollment.profile tls \
      --csr.hosts "orderer${i}.example.com" \
      --csr.hosts localhost \
      --tls.certfiles "${CA_CERT}"

    local ORD_TLS="${ORD_DIR}/orderers/orderer${i}.example.com/tls"
    cp "${ORD_TLS}/tlscacerts/"*   "${ORD_TLS}/ca.crt"
    cp "${ORD_TLS}/signcerts/"*    "${ORD_TLS}/server.crt"
    cp "${ORD_TLS}/keystore/"*     "${ORD_TLS}/server.key"

    mkdir -p "${ORD_DIR}/orderers/orderer${i}.example.com/msp/tlscacerts"
    cp "${ORD_TLS}/tlscacerts/"* \
       "${ORD_DIR}/orderers/orderer${i}.example.com/msp/tlscacerts/tlsca.example.com-cert.pem"
  done

  echo " -> Enrolling Orderer admin MSP"
  fabric-ca-client enroll \
    -u "https://ordererAdmin:ordererAdminpw@localhost:9054" \
    --caname ca-orderer \
    -M "${ORD_DIR}/users/Admin@example.com/msp" \
    --tls.certfiles "${CA_CERT}"

  cp "${ORD_DIR}/msp/config.yaml" \
     "${ORD_DIR}/users/Admin@example.com/msp/config.yaml"

  echo "   Orderer done."
}

# =============================================================================
# Main
# =============================================================================
createOrg1
createOrg2
createOrderer

echo ""
echo "[SUCCESS] All crypto materials generated."
