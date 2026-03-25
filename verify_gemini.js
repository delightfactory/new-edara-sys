import fs from 'fs';

const c = fs.readFileSync('supabase/migrations/09c_auth_guard.sql','utf-8');

// Test 1: check_permission as FUNCTION definition (not reference)
const hasCheckPermDef = /CREATE\s+OR\s+REPLACE\s+FUNCTION[^(]*check_permission/i.test(c);
console.log(hasCheckPermDef ? '❌ check_permission DEFINED in 09c' : '✅ check_permission NOT defined (correctly excluded)');

// Test 2: 09d functions
const d09Fns = ['save_product_units_atomic','update_bundle_atomic','set_user_roles_atomic','update_role_atomic'];
let d09Found = false;
d09Fns.forEach(fn => { if (c.includes(fn)) { console.log('❌ '+fn+' from 09d found!'); d09Found=true; }});
if (!d09Found) console.log('✅ No 09d functions duplicated');

// Test 3: Count SECURITY GUARD per function
const blocks = c.split(/(?=CREATE\s+OR\s+REPLACE\s+FUNCTION)/i).filter(b => /^CREATE/i.test(b));
let doubleCount = 0;
blocks.forEach(b => {
  const guardCount = (b.match(/SECURITY GUARD/g) || []).length;
  if (guardCount > 1) {
    const name = (b.match(/FUNCTION\s+([\w.]+)/i) || [])[1];
    console.log('❌ DOUBLE GUARD in: ' + name + ' (' + guardCount + ' times)');
    doubleCount++;
  }
});
if (doubleCount === 0) console.log('✅ No double guards in any function');

console.log('Total functions: ' + blocks.length);

if (!hasCheckPermDef && !d09Found && doubleCount === 0) {
  console.log('🎉 PERFECT: All Gemini-reported issues are resolved!');
} else {
  console.log('🚨 FAILURES DETECTED.');
}
