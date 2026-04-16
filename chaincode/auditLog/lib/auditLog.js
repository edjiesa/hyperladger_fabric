'use strict';

const { Contract } = require('fabric-contract-api');

class AuditLog extends Contract {

    async InitLedger(ctx) {
        console.info('============= START : Initialize Ledger ===========');
        // Initial test entry
        const audits = [
            {
                id: 'audit-0',
                timestamp: new Date().toISOString(),
                dbUser: 'system',
                operation: 'INIT',
                statement: 'Ledger Initialized Database Audit',
            },
        ];

        for (const audit of audits) {
            audit.docType = 'audit';
            await ctx.stub.putState(audit.id, Buffer.from(JSON.stringify(audit)));
            console.info(`Asset ${audit.id} initialized`);
        }
        console.info('============= END : Initialize Ledger ===========');
    }

    async RecordAudit(ctx, id, timestamp, dbUser, operation, statement) {
        console.info('============= START : Record Audit ===========');

        const audit = {
            id,
            docType: 'audit',
            timestamp,
            dbUser,
            operation,
            statement,
        };

        await ctx.stub.putState(id, Buffer.from(JSON.stringify(audit)));
        console.info('============= END : Record Audit ===========');
        return JSON.stringify(audit);
    }

    async QueryAudit(ctx, id) {
        const auditAsBytes = await ctx.stub.getState(id);
        if (!auditAsBytes || auditAsBytes.length === 0) {
            throw new Error(`Audit log ${id} does not exist`);
        }
        return auditAsBytes.toString();
    }

    async GetAllAudits(ctx) {
        const allResults = [];
        // selector for rich query (CouchDB)
        const iterator = await ctx.stub.getQueryResult(JSON.stringify({
            selector: {
                docType: 'audit'
            }
        }));
        
        let result = await iterator.next();
        while (!result.done) {
            const strValue = Buffer.from(result.value.value.toString('utf8')).toString('utf8');
            let record;
            try {
                record = JSON.parse(strValue);
            } catch (err) {
                console.log(err);
                record = strValue;
            }
            allResults.push(record);
            result = await iterator.next();
        }
        return JSON.stringify(allResults);
    }
}

module.exports = AuditLog;
