import fs from 'fs';
import path from 'path';

const migrationsDir = path.join(process.cwd(), 'supabase', 'migrations');
const cGuardPath = path.join(migrationsDir, '09c_auth_guard.sql');
const EXCLUDED_FILES = ['09c_auth_guard.sql', '09d_atomic_fixes.sql'];

const cGuardContent = fs.readFileSync(cGuardPath, 'utf-8');

const GUARD_STMT = `\n  -- [SECURITY GUARD] Verify user identity to prevent spoofing
  IF p_user_id IS NOT NULL AND auth.uid() IS NOT NULL AND p_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: User ID mismatch';
  END IF;\n`;

// Phase 1: Count functions in 09c
const funcCount = (cGuardContent.match(/CREATE\s+OR\s+REPLACE\s+FUNCTION/gi) || []).length;
console.log(`Functions in 09c_auth_guard.sql: ${funcCount}`);

// Phase 2: Check for DOUBLE guards (the Gemini bug #3)
const doubleGuardPattern = /SECURITY GUARD.*?END IF;.*?SECURITY GUARD/gs;
const doubleGuards = cGuardContent.match(doubleGuardPattern);
if (doubleGuards) {
  console.log(`❌ DOUBLE GUARD DETECTED! Found ${doubleGuards.length} instances.`);
} else {
  console.log(`✅ No double guards found.`);
}

// Phase 3: Check that check_permission is NOT in the file (Gemini bug #1)
if (/check_permission/i.test(cGuardContent)) {
  console.log(`❌ CRITICAL: check_permission is still in the file! This will DESTROY RLS performance.`);
} else {
  console.log(`✅ check_permission correctly excluded (LANGUAGE sql, inlinable).`);
}

// Phase 4: Check that NO functions from 09d are in the file (Gemini bug #3)
const d09Functions = ['save_product_units_atomic', 'update_bundle_atomic', 'set_user_roles_atomic', 'update_role_atomic'];
let foundFrom09d = false;
for (const fn of d09Functions) {
  if (cGuardContent.includes(fn)) {
    console.log(`❌ CRITICAL: ${fn} from 09d is duplicated in 09c!`);
    foundFrom09d = true;
  }
}
if (!foundFrom09d) {
  console.log(`✅ No 09d functions duplicated in 09c.`);
}

// Phase 5: Byte-for-byte validation — strip guard and match against source
const sourceCommentPattern = /-- Source: (.*?) -> Function: (.*?)\n/g;
let match;
let matchedCount = 0;
let mismatchCount = 0;
const allMatches = [];

while ((match = sourceCommentPattern.exec(cGuardContent)) !== null) {
  allMatches.push({ sourceFile: match[1].trim(), funcName: match[2].trim(), index: match.index + match[0].length });
}

for (let i = 0; i < allMatches.length; i++) {
  const { sourceFile, funcName, index } = allMatches[i];
  const nextIndex = i + 1 < allMatches.length 
    ? cGuardContent.lastIndexOf('-- Source:', allMatches[i+1].index)
    : cGuardContent.length;
  
  const injectedBlock = cGuardContent.substring(index, nextIndex).trim();
  const revertedBlock = injectedBlock.replace(GUARD_STMT, '');
  
  // Read source file
  const sourceContent = fs.readFileSync(path.join(migrationsDir, sourceFile), 'utf-8');
  
  if (sourceContent.includes(revertedBlock)) {
    console.log(`✅ MATCH: ${funcName} (from ${sourceFile})`);
    matchedCount++;
  } else {
    console.log(`❌ MISMATCH: ${funcName} (from ${sourceFile})`);
    mismatchCount++;
  }
}

console.log(`\n══════════════════════════════════════════════`);
console.log(`Total functions: ${funcCount}`);
console.log(`Byte-for-byte matched: ${matchedCount}`);
console.log(`Mismatched: ${mismatchCount}`);
console.log(`Double guards: ${doubleGuards ? doubleGuards.length : 0}`);
console.log(`check_permission leak: ${/check_permission/i.test(cGuardContent) ? 'YES ❌' : 'NO ✅'}`);
console.log(`09d leak: ${foundFrom09d ? 'YES ❌' : 'NO ✅'}`);

if (mismatchCount === 0 && !doubleGuards && !/check_permission/i.test(cGuardContent) && !foundFrom09d) {
  console.log(`\n🎉 PERFECT: 09c_auth_guard.sql passes ALL validation checks!`);
} else {
  console.log(`\n🚨 FAILURES DETECTED. File needs further fixing.`);
}
