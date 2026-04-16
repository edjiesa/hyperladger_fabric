#!/usr/bin/env bash

# =============================================================================
# network.sh - Hyperledger Fabric 2-Org Production-Like Network Manager
# Compatible with Fabric 2.5.x on WSL2 Ubuntu (Windows) / Linux / macOS
# =============================================================================

# Ensure common Linux bin paths are available (needed when called via wsl -d)
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

export FABRIC_CFG_PATH="${PWD}/configtx"
export VERBOSE=false

# Always ensure we run from the script's own directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}" || exit 1
NETWORK_ROOT_DIR="${SCRIPT_DIR}"

# =============================================================================
# Color helpers
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

infoln() { echo -e "${BLUE}[INFO]${NC} $@"; }
successln() { echo -e "${GREEN}[OK]${NC} $@"; }
warnln() { echo -e "${YELLOW}[WARN]${NC} $@"; }
fatalln() { echo -e "${RED}[ERROR]${NC} $@"; exit 1; }

# =============================================================================
# Prerequisites Check
# =============================================================================
function checkPrereqs() {
  infoln "Checking prerequisites..."

  # Check Docker — search common paths
  if ! command -v docker &>/dev/null && ! [ -x /usr/bin/docker ] && ! [ -x /usr/local/bin/docker ]; then
    fatalln "Docker is not installed. Please install Docker Desktop (WSL2 enabled)."
  fi
  # Use full path if needed
  DOCKER_BIN=$(command -v docker 2>/dev/null || echo /usr/bin/docker)
  # Use 'docker ps' as a more reliable daemon check than 'docker info'
  if ! ${DOCKER_BIN} ps &>/dev/null; then
    fatalln "Docker daemon is not running or not accessible. Please start Docker Desktop and ensure WSL integration is enabled."
  fi
  successln "Docker is running."

  # Prefer 'docker compose' plugin (works in WSL) over legacy 'docker-compose' binary
  # The 'docker-compose' binary may resolve to a Windows path with spaces (broken in WSL)
  if ${DOCKER_BIN} compose version &>/dev/null 2>&1; then
    DOCKER_COMPOSE="${DOCKER_BIN} compose"
  elif command -v docker-compose &>/dev/null && docker-compose version &>/dev/null 2>&1; then
    DOCKER_COMPOSE="docker-compose"
  else
    fatalln "Docker Compose not found. Please enable WSL integration in Docker Desktop Settings > Resources > WSL Integration."
  fi
  successln "Docker Compose found: ${DOCKER_COMPOSE}"

  # Add local bin to PATH so fabric binaries are found
  export PATH="${NETWORK_ROOT_DIR}/bin:$PATH"

  # Check fabric binaries
  if ! command -v fabric-ca-client &>/dev/null; then
    warnln "fabric-ca-client not found in PATH."
    fatalln "Run: ./network.sh installBinaries  to download Fabric 2.5 binaries."
  fi
  if ! command -v configtxgen &>/dev/null; then
    fatalln "configtxgen binary not found. Run: ./network.sh installBinaries"
  fi
  if ! command -v osnadmin &>/dev/null; then
    fatalln "osnadmin binary not found. Run: ./network.sh installBinaries"
  fi
  successln "All Fabric binaries found."
}

# =============================================================================
# Download & Install Fabric Binaries (2.5.4 + CA 1.5.7)
# =============================================================================
function installBinaries() {
  infoln "Downloading Hyperledger Fabric 2.5.4 binaries and Docker images..."
  infoln "This may take 5-15 minutes depending on your internet connection..."

  mkdir -p "${NETWORK_ROOT_DIR}/bin"

  # Use the official bootstrap script
  curl -sSLO https://raw.githubusercontent.com/hyperledger/fabric/main/scripts/install-fabric.sh
  chmod +x install-fabric.sh
  ./install-fabric.sh --fabric-version 2.5.4 --ca-version 1.5.7 binary
  rm -f install-fabric.sh

  # Add bin to PATH
  export PATH="${NETWORK_ROOT_DIR}/bin:$PATH"
  successln "Fabric binaries installed to ./bin"
  infoln "  >> Add this to your .bashrc / .zshrc to persist:"
  echo "     export PATH=\"${NETWORK_ROOT_DIR}/bin:\$PATH\""
}

# =============================================================================
# Create required CA directory placeholders
# =============================================================================
function createCaDirectories() {
  infoln "Creating CA server data directories..."
  mkdir -p "${NETWORK_ROOT_DIR}/organizations/fabric-ca/org1"
  mkdir -p "${NETWORK_ROOT_DIR}/organizations/fabric-ca/org2"
  mkdir -p "${NETWORK_ROOT_DIR}/organizations/fabric-ca/ordererOrg"
  successln "CA directories created."
}

# =============================================================================
# Stop and remove containers
# =============================================================================
function clearContainers() {
  infoln "Removing stopped chaincode containers..."
  docker rm -f $(docker ps -aq --filter label=service=hyperledger-fabric) 2>/dev/null || true
  docker rm -f $(docker ps -aq --filter name='dev-peer*') 2>/dev/null || true
}

function removeUnwantedImages() {
  infoln "Removing chaincode docker images..."
  docker rmi $(docker images | grep 'dev-peer' | awk '{print $3}') 2>/dev/null || true
}

# =============================================================================
# Network Up
# =============================================================================
function networkUp() {
  checkPrereqs
  createCaDirectories

  infoln "Starting Fabric Certificate Authorities..."
  ${DOCKER_COMPOSE} --env-file "${NETWORK_ROOT_DIR}/.env" \
    -f "${NETWORK_ROOT_DIR}/docker/docker-compose-ca.yaml" \
    up -d 2>&1

  infoln "Waiting for CAs to fully initialize (8s)..."
  sleep 8

  infoln "Generating crypto materials via Fabric CA..."
  # Temporarily add bin to PATH for the register/enroll script
  export PATH="${NETWORK_ROOT_DIR}/bin:$PATH"
  export FABRIC_CA_CLIENT_HOME_BASE="${NETWORK_ROOT_DIR}/organizations"

  # Run registerEnroll from network root so paths resolve correctly
  bash "${NETWORK_ROOT_DIR}/scripts/registerEnroll.sh" "${NETWORK_ROOT_DIR}"

  # Rename the admin private key for easy access by Explorer
  infoln "Renaming admin private keys to 'priv_sk'..."
  for org in org1 org2; do
    KEY_DIR="${NETWORK_ROOT_DIR}/organizations/peerOrganizations/${org}.example.com/users/Admin@${org}.example.com/msp/keystore"
    if [ -d "${KEY_DIR}" ]; then
      KEY_FILE=$(ls "${KEY_DIR}" | grep "_sk" | head -n 1)
      if [ -n "${KEY_FILE}" ]; then
        cp "${KEY_DIR}/${KEY_FILE}" "${KEY_DIR}/priv_sk"
      fi
    fi
  done

  if [ $? -ne 0 ]; then
    fatalln "Crypto material generation failed. Check CA logs: docker logs ca_org1"
  fi
  successln "Crypto materials generated."

  infoln "Generating channel genesis block (mychannel.block)..."
  mkdir -p "${NETWORK_ROOT_DIR}/channel-artifacts"
  configtxgen \
    -profile TwoOrgsApplicationGenesis \
    -outputBlock "${NETWORK_ROOT_DIR}/channel-artifacts/mychannel.block" \
    -channelID mychannel 2>&1

  if [ $? -ne 0 ]; then
    fatalln "configtxgen failed. Check configtx/configtx.yaml"
  fi
  successln "Genesis block created: channel-artifacts/mychannel.block"

  infoln "Starting Orderers, Peers, and CouchDB containers..."
  ${DOCKER_COMPOSE} --env-file "${NETWORK_ROOT_DIR}/.env" \
    -f "${NETWORK_ROOT_DIR}/docker/docker-compose-test-net.yaml" \
    up -d 2>&1

  infoln "Waiting for nodes to fully start (12s)..."
  sleep 12

  successln "============================================================"
  successln " Network is UP! Containers:"
  docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "peer|orderer|couch|ca"
  successln "============================================================"
  infoln "Next step: ./network.sh createChannel"
}

# =============================================================================
# Create Channel
# =============================================================================
function createChannel() {
  checkPrereqs
  infoln "Creating channel 'mychannel' and joining peers..."

  # Ensure CLI is running.
  CLI_STATUS=$(docker inspect cli --format '{{.State.Status}}' 2>/dev/null || echo "missing")
  if [ "${CLI_STATUS}" != "running" ]; then
    infoln "CLI container status is '${CLI_STATUS}', attempting to start..."
    docker start cli 2>/dev/null || true
    sleep 5
  fi


  docker exec cli bash /opt/gopath/src/github.com/hyperledger/fabric/peer/scripts/createChannel.sh
  if [ $? -ne 0 ]; then
    fatalln "Channel creation failed. Check CLI container logs: docker logs cli"
  fi
  successln "Channel 'mychannel' created and peers joined!"
}



# =============================================================================
# Start PostgreSQL Audit DB
# =============================================================================
function startPostgres() {
  infoln "Starting PostgreSQL + pgAudit container..."
  COMPOSE_CMD="${DOCKER_COMPOSE:-docker compose}"
  ${COMPOSE_CMD} --env-file "${NETWORK_ROOT_DIR}/.env" \
    -f "${NETWORK_ROOT_DIR}/docker/docker-compose-pg.yaml" \
    up -d 2>&1
  successln "PostgreSQL (pgAudit) running on port 5432."
}

# =============================================================================
# Start Hyperledger Explorer
# =============================================================================
function startExplorer() {
  checkPrereqs
  infoln "Preparing Hyperledger Explorer..."
  DOCKER_COMPOSE_PLUGIN="${DOCKER_COMPOSE}" bash "${NETWORK_ROOT_DIR}/explorer/start-explorer.sh"
}

# =============================================================================
# Network Down
# =============================================================================
function networkDown() {
  infoln "Tearing down network..."
  checkPrereqs

  COMPOSE_CMD="${DOCKER_COMPOSE:-docker compose}"

  ${COMPOSE_CMD} --env-file "${NETWORK_ROOT_DIR}/.env" \
    -f "${NETWORK_ROOT_DIR}/docker/docker-compose-test-net.yaml" \
    -f "${NETWORK_ROOT_DIR}/docker/docker-compose-ca.yaml" \
    -f "${NETWORK_ROOT_DIR}/docker/docker-compose-pg.yaml" \
    -f "${NETWORK_ROOT_DIR}/explorer/docker-compose-explorer.yaml" \
    down --volumes --remove-orphans 2>/dev/null || true

  clearContainers
  removeUnwantedImages

  infoln "Removing all generated artifacts and crypto materials..."
  rm -rf "${NETWORK_ROOT_DIR}/organizations"
  rm -rf "${NETWORK_ROOT_DIR}/channel-artifacts"

  infoln "Removing all persistent volumes (if any remain)..."
  # Remove named volumes matching any project prefix (compose, fabric-network, etc.)
  VOLS=$(docker volume ls -q | grep -E '(orderer|peer|couchdb|pgdata|wallet|audit|postgres|explorer)\.(example\.com|instance)')
  VOLS2=$(docker volume ls -q | grep -E '^(compose_|fabric-network_|fabric_)(orderer|peer|couch|explorer|postgres|audit)')
  ALL_VOLS="${VOLS} ${VOLS2}"
  if [ -n "$(echo "${ALL_VOLS}" | tr -d ' ')" ]; then
    docker volume rm ${ALL_VOLS} 2>/dev/null || true
  fi

  # Remove dangling/anonymous volumes created by Fabric Docker image VOLUME directives
  # These persist MSP/ledger state and cause 'malformed creator' errors on redeploy
  infoln "Pruning dangling anonymous volumes..."
  docker volume prune -f 2>/dev/null || true

  successln "Network is DOWN. All artifacts and volumes cleaned."
}

# =============================================================================
# Help
# =============================================================================
function printHelp() {
  echo ""
  echo "Usage: ./network.sh <command>"
  echo ""
  echo "Commands:"
  echo "  installBinaries  - Download Hyperledger Fabric 2.5.4 binaries (run FIRST)"
  echo "  up               - Start CAs, generate certs, start Orderers + Peers + CouchDB"
  echo "  createChannel    - Create 'mychannel' and join all peers"
  echo "  startPostgres    - Start PostgreSQL + pgAudit off-chain DB"
  echo "  startExplorer    - Start Hyperledger Explorer dashboard (port 8080)"
  echo "  down             - Stop and remove all containers and clean artifacts"
  echo ""
  echo "Typical flow:"
  echo "  1. ./network.sh installBinaries"
  echo "  2. ./network.sh up"
  echo "  3. ./network.sh createChannel"
  echo "  4. ./network.sh startPostgres"
  echo "  5. ./network.sh startExplorer"
  echo ""
}

# =============================================================================
# Main
# =============================================================================
case "$1" in
  installBinaries) installBinaries ;;
  up) networkUp ;;
  createChannel) createChannel ;;
  startPostgres) startPostgres ;;
  startExplorer) startExplorer ;;
  down) networkDown ;;
  *) printHelp; exit 1 ;;
esac
