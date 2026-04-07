const { execSync } = require('child_process');

const CONN = 'postgresql://postgres:HVXvedDhYN2kyoI8@db.ozthzccqudrudicnneuu.supabase.co:5432/postgres';

function runSql(sql) {
    const cmd = `psql "${CONN}" -c "${sql}"`;
    try {
        const out = execSync(cmd, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] });
        return out;
    } catch (e) {
        console.error("FAILED SQL:", sql);
        console.error("STDOUT:", e.stdout);
        console.error("STDERR:", e.stderr);
        throw new Error("Query execution failed");
    }
}

console.log("Getting plan...");
const planOut = runSql("SELECT chunk_num, chunk_start, chunk_end FROM analytics.plan_historical_backfill(current_date - 1825, current_date, 30);");

const lines = planOut.split('\n');
const chunks = [];
for (let line of lines) {
    const parts = line.split('|').map(s => s.trim());
    if (parts.length === 3 && parseInt(parts[0])) {
        chunks.push({ num: parseInt(parts[0]), start: parts[1], end: parts[2] });
    }
}

console.log(`Found ${chunks.length} chunks. Starting execution...`);
if (chunks.length === 0) {
    console.error(planOut);
    process.exit(1);
}

let completedChunks = 0;
let firstChunk = chunks[0];
let lastChunk = null;

for (let chunk of chunks) {
    console.log(`\n--- Executing Chunk ${chunk.num} [${chunk.start} to ${chunk.end}] ---`);
    console.log(new Date().toISOString());
    runSql(`CALL analytics.run_historical_backfill_chunk('${chunk.start}', '${chunk.end}');`);

    const etlOut = runSql("SELECT table_name, status, started_at, completed_at, drift_value FROM analytics.etl_runs ORDER BY started_at DESC LIMIT 10;");
    console.log("ETL Status after chunk:");
    console.log(etlOut);
    
    if (etlOut.includes('FAILED') || etlOut.includes('BLOCKED')) {
         console.error("FATAL: Anomaly detected! Stopping immediately.");
         break;
    }
    completedChunks++;
    lastChunk = chunk;
}

if (completedChunks === chunks.length) {
    console.log("\nAll chunks completed successfully! Running final watermark sweep...");
    runSql("CALL analytics.run_analytics_watermark_sweep(1);");
}

console.log("\nFinal Report Verification:");
const finalEtl = runSql("SELECT table_name, status, started_at, completed_at, drift_value FROM analytics.etl_runs ORDER BY started_at DESC LIMIT 20;");
console.log(finalEtl);

const finalCounts = runSql("SELECT (SELECT COUNT(*) FROM analytics.fact_sales_daily_grain) AS sales_rows, (SELECT COUNT(*) FROM analytics.fact_treasury_cashflow_daily) AS treasury_rows, (SELECT COUNT(*) FROM analytics.fact_ar_collections_attributed_to_origin_sale_date) AS ar_rows, (SELECT COUNT(*) FROM analytics.snapshot_customer_health) AS health_rows;");
console.log(finalCounts);

console.log("=== MISSION REPORT ===");
console.log(`Chunks planned: ${chunks.length}`);
console.log(`Chunks completed: ${completedChunks}`);
console.log(`First executed: ${firstChunk.start} to ${firstChunk.end}`);
if (lastChunk) {
    console.log(`Last executed: ${lastChunk.start} to ${lastChunk.end}`);
}
console.log(`Final Sweep Executed: ${completedChunks === chunks.length ? 'YES' : 'NO'}`);
