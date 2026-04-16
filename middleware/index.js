'use strict';

const fs = require('fs');
const Tail = require('tail').Tail;
const { Gateway, Wallets } = require('fabric-network');
const path = require('path');
const { parse } = require('csv-parse/sync');

// Configuration
const PG_LOG_DIR = path.resolve(__dirname, '../network/docker/pg_log');
const CHANNEL_NAME = 'mychannel';
const CHAINCODE_NAME = 'auditlog';
const ORG_MSP = 'Org1MSP';
const WALLET_PATH = path.join(__dirname, 'wallet');
const USER_ID = 'appUser';

let gateway;
let contract;

async function setupFabricConnection() {
    try {
        const wallet = await Wallets.newFileSystemWallet(WALLET_PATH);

        // This assumes connection profile is created, for thesis purposes we simulate connection logic
        const ccpPath = path.resolve(__dirname, '..', 'network', 'organizations', 'peerOrganizations', 'org1.example.com', 'connection-org1.json');
        
        let ccp;
        if (fs.existsSync(ccpPath)) {
            ccp = JSON.parse(fs.readFileSync(ccpPath, 'utf8'));
        } else {
            console.warn("Connection profile not found. Please ensure the network is running and connection-org1.json is generated.");
            return false;
        }

        const identity = await wallet.get(USER_ID);
        if (!identity) {
            console.warn(`An identity for the user "${USER_ID}" does not exist in the wallet. Please enroll an admin and user first.`);
            return false;
        }

        gateway = new Gateway();
        await gateway.connect(ccp, { wallet, identity: USER_ID, discovery: { enabled: true, asLocalhost: true } });

        const network = await gateway.getNetwork(CHANNEL_NAME);
        contract = network.getContract(CHAINCODE_NAME);

        console.log('Successfully connected to Hyperledger Fabric network');
        return true;
    } catch (error) {
        console.error(`Failed to connect to Fabric network: ${error}`);
        return false;
    }
}

async function submitAuditToFabric(logEntry) {
    if (!contract) return;
    try {
        const auditId = `audit-${Date.now()}-${Math.floor(Math.random() * 1000)}`;
        // Submit transaction to smart contract
        // RecordAudit(id, timestamp, dbUser, operation, statement)
        await contract.submitTransaction('RecordAudit', auditId, logEntry.timestamp, logEntry.user, logEntry.operation, logEntry.statement);
        console.log(`Audit submitted to ledger: ${auditId}`);
    } catch (error) {
        console.error(`Failed to submit transaction: ${error}`);
    }
}

async function watchPgLogs() {
    if (!fs.existsSync(PG_LOG_DIR)) {
        console.warn(`Postgres log directory ${PG_LOG_DIR} does not exist yet. Waiting...`);
        setTimeout(watchPgLogs, 5000);
        return;
    }

    console.log(`Watching Postgres logs in ${PG_LOG_DIR}`);
    
    // Find the latest csv log file
    const files = fs.readdirSync(PG_LOG_DIR)
        .filter(fn => fn.endsWith('.csv'))
        .map(fn => ({ file: fn, mtime: fs.statSync(path.join(PG_LOG_DIR, fn)).mtime }))
        .sort((a, b) => b.mtime.getTime() - a.mtime.getTime());

    if (files.length === 0) {
        console.warn(`No CSV logs found yet. Watching directory...`);
        setTimeout(watchPgLogs, 5000);
        return;
    }

    const latestLogFile = path.join(PG_LOG_DIR, files[0].file);
    console.log(`Tailing file: ${latestLogFile}`);

    const tail = new Tail(latestLogFile);

    tail.on("line", async function(data) {
        // Postgres CSV log format is comma-separated, try to parse
        try {
            const records = parse(data, {
                columns: false,
                skip_empty_lines: true
            });
            const row = records[0];
            if (!row) return;

            // Simple parse of CSV (Postgres 15 csvlog format)
            const timestamp = row[0];
            const user = row[1];
            const detail = row[13]; // Error severity / description

            if (data.includes('AUDIT:')) {
                console.log("Found pgaudit log entry:", detail);
                const logEntry = {
                    timestamp: timestamp,
                    user: user || 'unknown',
                    operation: 'QUERY',
                    statement: detail
                };
                await submitAuditToFabric(logEntry);
            }
        } catch (e) {
            // Ignore parse errors for incomplete lines during tail
        }
    });

    tail.on("error", function(error) {
        console.error('Tail ERROR: ', error);
    });
}

async function main() {
    console.log('Starting Postgres pgAudit Middleware for Hyperledger Fabric');
    await setupFabricConnection();
    watchPgLogs();
    
    process.on('SIGINT', () => {
        if (gateway) {
            gateway.disconnect();
            console.log('Disconnected from Fabric Gateway');
        }
        process.exit();
    });
}

main();
