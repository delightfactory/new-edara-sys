import fs from 'fs';
import path from 'path';

const migrationsDir = path.join(process.cwd(), 'supabase', 'migrations');
const outputFile = path.join(migrationsDir, '09c_auth_guard.sql');

// ──────────────────────────────────────────────────────────────────
// CRITICAL EXCLUSIONS:
// 1. 09c_auth_guard.sql → this is the output file itself
// 2. 09d_atomic_fixes.sql → functions there ALREADY have guards built-in natively, 
//    including them would cause DOUBLE GUARD injection
// 3. seed files → not relevant
// ──────────────────────────────────────────────────────────────────
const EXCLUDED_FILES = ['09c_auth_guard.sql', '09d_atomic_fixes.sql'];

const files = fs.readdirSync(migrationsDir)
  .filter(f => f.endsWith('.sql') && !EXCLUDED_FILES.includes(f) && !f.includes('seed'))
  .sort();

const GUARD_STMT_PLPGSQL = `\n  -- [SECURITY GUARD] Verify user identity to prevent spoofing
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;\n`;

let totalInjected = 0;

// ──────────────────────────────────────────────────────────────────
// Phase 1: Build a Map of ALL functions that take p_user_id
//          Key = normalized function name
//          Value = { sourceFile, rawChunk, language }
//          Later entries OVERWRITE earlier ones → latest version wins
// ──────────────────────────────────────────────────────────────────
const functionsMap = new Map();

for (const file of files) {
  const content = fs.readFileSync(path.join(migrationsDir, file), 'utf-8');
  
  // Split on CREATE OR REPLACE FUNCTION
  const chunks = content.split(/(?=CREATE\s+OR\s+REPLACE\s+FUNCTION\s+)/i);
  
  for (const chunk of chunks) {
    if (!/^CREATE\s+OR\s+REPLACE\s+FUNCTION\s+/i.test(chunk)) continue;
    
    // Extract function name
    const nameMatch = chunk.match(/CREATE\s+OR\s+REPLACE\s+FUNCTION\s+([\w.]+)\s*\(/i);
    if (!nameMatch) continue;
    
    let funcName = nameMatch[1].toLowerCase();
    if (funcName.startsWith('public.')) funcName = funcName.substring(7);
    
    // Check if this function takes p_user_id
    // We need to parse the parameter list (from first '(' to its matching ')')
    const firstParenIdx = chunk.indexOf('(');
    let depth = 0;
    let lastParenIdx = -1;
    for (let i = firstParenIdx; i < chunk.length; i++) {
      if (chunk[i] === '(') depth++;
      if (chunk[i] === ')') { depth--; if (depth === 0) { lastParenIdx = i; break; } }
    }
    if (lastParenIdx === -1) continue;
    
    const params = chunk.substring(firstParenIdx + 1, lastParenIdx);
    if (!/p_user_id\s+uuid/i.test(params)) continue;
    
    // Detect language
    const langMatch = chunk.match(/LANGUAGE\s+(plpgsql|sql)/i);
    if (!langMatch) continue;
    const language = langMatch[1].toLowerCase();
    
    // Find the end of the function definition
    // For plpgsql: ends with $$ ... LANGUAGE plpgsql ... ;
    // For sql: ends with $$ ... LANGUAGE sql ... ;
    const endPattern = /\$\$\s*;/g;
    let lastDollarEnd = -1;
    let m;
    // Find the SECOND $$ (end of function body)
    const dollarPositions = [];
    let searchFrom = 0;
    while (true) {
      const idx = chunk.indexOf('$$', searchFrom);
      if (idx === -1) break;
      dollarPositions.push(idx);
      searchFrom = idx + 2;
    }
    
    if (dollarPositions.length < 2) continue;
    
    // The function block ends after the second $$, plus any trailing LANGUAGE/SECURITY/; 
    // Find the semicolon after the last $$
    const afterLastDollar = chunk.indexOf(';', dollarPositions[dollarPositions.length - 1]);
    const funcBlock = chunk.substring(0, afterLastDollar !== -1 ? afterLastDollar + 1 : chunk.length).trim();
    
    // Store: latest version wins (Map overwrites)
    functionsMap.set(funcName, {
      originalName: nameMatch[1],
      sourceFile: file,
      funcBlock: funcBlock,
      language: language,
    });
  }
}

console.log(`Found ${functionsMap.size} unique functions with p_user_id parameter.`);

// ──────────────────────────────────────────────────────────────────
// Phase 2: Generate output, handling each language type correctly
// ──────────────────────────────────────────────────────────────────
let outputSql = `-- =========================================================================\n`;
outputSql += `-- 09c_auth_guard.sql\n`;
outputSql += `-- التحقق من هوية المستخدم في جميع دوال RPC لضمان عدم تمرير p_user_id مزيف\n`;
outputSql += `-- =========================================================================\n`;
outputSql += `-- Generated: ${new Date().toISOString()}\n`;
outputSql += `-- Excluded sources: ${EXCLUDED_FILES.join(', ')} (already contain guards)\n\n`;

for (const [funcName, data] of functionsMap.entries()) {
  const { sourceFile, funcBlock, language } = data;
  
  if (language === 'sql') {
    // ─────────────────────────────────────────────────────────────
    // LANGUAGE sql functions (like check_permission from 08_*)
    // These CANNOT have IF/BEGIN/END statements.
    // Strategy: Convert to plpgsql wrapper that calls the original SQL logic
    // BUT WAIT: Converting to plpgsql would DESTROY the inlining optimization!
    // 
    // CORRECT STRATEGY: Do NOT inject guard into LANGUAGE sql functions.
    // The p_user_id in check_permission is always auth.uid() from the RLS policy,
    // not from user input. It's called INTERNALLY by RLS, not via RPC.
    // ─────────────────────────────────────────────────────────────
    console.log(`⚠️  SKIPPING ${funcName} (${sourceFile}) — LANGUAGE sql, inlinable, called by RLS not RPC. Guard injection would destroy performance optimization.`);
    continue;
  }
  
  // LANGUAGE plpgsql — inject guard after BEGIN
  const beginMatch = funcBlock.match(/\bBEGIN\b/i);
  if (!beginMatch) {
    console.log(`⚠️  SKIPPING ${funcName} — no BEGIN found`);
    continue;
  }
  
  // Check if guard already exists (from functions that were manually hardened)
  if (funcBlock.includes('SECURITY GUARD') || funcBlock.includes('User ID mismatch')) {
    console.log(`⚠️  SKIPPING ${funcName} (${sourceFile}) — already contains security guard`);
    continue;
  }
  
  const beginIdx = beginMatch.index + beginMatch[0].length;
  const newBlock = funcBlock.substring(0, beginIdx) + GUARD_STMT_PLPGSQL + funcBlock.substring(beginIdx);
  
  outputSql += `-- Source: ${sourceFile} -> Function: ${data.originalName}\n`;
  outputSql += newBlock + '\n\n';
  totalInjected++;
  console.log(`✅ Injected: ${funcName} (latest from ${sourceFile})`);
}

fs.writeFileSync(outputFile, outputSql);
console.log(`\n══════════════════════════════════════════════`);
console.log(`Total unique functions processed: ${functionsMap.size}`);
console.log(`Guards injected: ${totalInjected}`);
console.log(`Skipped (LANGUAGE sql / already guarded): ${functionsMap.size - totalInjected}`);
console.log(`Saved to: 09c_auth_guard.sql`);
