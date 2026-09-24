// Calls every connector operation on the Data Connect emulator, as the app will.
// Run via dataconnect/test/run.sh (which starts Postgres + the emulator first).
import assert from 'node:assert/strict';

const BASE = process.env.FDC_URL ?? 'http://127.0.0.1:9399';
const PATH = '/v1/projects/demo-v2/locations/europe-west2/services/door-scheduler/connectors/door-scheduler';
const HARVEY = 'harvey.dove@matrixhardware.co.uk';
const SAM = 'sam.estimator@matrixhardware.co.uk';

const b64 = s => Buffer.from(s).toString('base64url');
// The emulator accepts unsigned ID tokens, like the Auth emulator issues.
function token(email) {
  const now = Math.floor(Date.now() / 1000);
  const uid = `uid-${email.split('@')[0]}`;
  return `${b64(JSON.stringify({ alg: 'none', typ: 'JWT' }))}.${b64(JSON.stringify({
    iss: 'https://securetoken.google.com/demo-v2', aud: 'demo-v2', auth_time: now, user_id: uid, sub: uid,
    iat: now, exp: now + 3600, email, email_verified: false, firebase: { sign_in_provider: 'password', identities: {} },
  }))}.`;
}

async function call(kind, operationName, variables = {}, email = HARVEY) {
  const headers = { 'Content-Type': 'application/json' };
  if (email) headers['X-Firebase-Auth-Token'] = token(email);
  const res = await fetch(`${BASE}${PATH}:execute${kind}`, { method: 'POST', headers, body: JSON.stringify({ operationName, variables }) });
  return res.json();
}
const query = (...a) => call('Query', ...a);
const mutation = (...a) => call('Mutation', ...a);
const ok = r => { assert.ok(!r.code && !(r.errors?.length), `unexpected error: ${JSON.stringify(r).slice(0, 500)}`); return r.data; };
/** SetMatCode / SetPrice return one array per table; the saved row is in the one that matched. */
const savedRow = data => Object.values(data).flat().filter(Boolean)[0] ?? null;

let passed = 0;
async function test(name, fn) {
  await fn();
  passed++;
  console.log(`   ok - ${name}`);
}

const ALL = { kind: null, onlyMissing: false, search: null, includeInactive: false };

await test('signed-out requests are refused', async () => {
  const r = await query('GetSettings', {}, null);
  assert.ok(r.code || r.errors?.length);
});

await test('non-Matrix accounts are refused', async () => {
  const r = await query('GetSettings', {}, 'someone@gmail.com');
  assert.equal(r.code, 7);
  assert.match(JSON.stringify(r), /@auth rejected/);
});

await test('EnsureMe creates the signed-in user from the token', async () => {
  const me = ok(await mutation('EnsureMe'))._executeReturningFirst;
  assert.deepEqual(me, { uid: 'uid-harvey.dove', email: HARVEY, display_name: 'Harvey Dove', role: 'estimator' });
  ok(await mutation('EnsureMe', {}, SAM));
});

await test('GetSettings: lining threshold 150mm, markup 22%', async () => {
  const rows = ok(await query('GetSettings'))._select;
  const get = k => rows.find(r => r.key === k)?.value;
  assert.equal(get('lining_depth_threshold_mm'), 150);
  assert.equal(get('default_markup_pct'), 0.22);
});

await test('ListCategories: 16 hardware categories', async () => {
  assert.equal(ok(await query('ListCategories'))._select.length, 16);
});

await test('MatCodeTable lists all 88 priced items, missing codes first', async () => {
  const rows = ok(await query('MatCodeTable', ALL))._select;
  assert.equal(rows.length, 88);
  assert.ok(rows.every(r => r.mat_code === null));
  const doors = ok(await query('MatCodeTable', { ...ALL, kind: 'door', search: 'sasl fd30' }))._select;
  assert.ok(doors.length > 0 && doors.every(r => r.kind === 'door'));
});

await test('SetMatCode saves; a stale save by someone else is refused (no silent overwrite)', async () => {
  const [row] = ok(await query('MatCodeTable', { ...ALL, kind: 'vision_panel', search: 'FD30' }))._select;
  const vars = { table: row.table_name, id: row.row_id, version: row.version };
  const saved = savedRow(ok(await mutation('SetMatCode', { ...vars, matCode: ' mat-vp-30 ' })));
  assert.equal(saved.mat_code, 'MAT-VP-30');
  assert.equal(saved.version, row.version + 1);
  // Sam loaded the same row at the old version
  assert.equal(savedRow(ok(await mutation('SetMatCode', { ...vars, matCode: 'MAT-OTHER' }, SAM))), null);
  const [after] = ok(await query('MatCodeTable', { ...ALL, search: 'mat-vp-30' }))._select;
  assert.equal(after.mat_code, 'MAT-VP-30');
});

await test('a duplicate MAT code is refused, and MatCodeOwner says where it is used', async () => {
  const [row] = ok(await query('MatCodeTable', { ...ALL, kind: 'product', search: '9205' }))._select;
  const r = await mutation('SetMatCode', { table: row.table_name, id: row.row_id, version: row.version, matCode: 'MAT-VP-30' });
  assert.ok(r.errors?.length, 'expected an error');
  const owner = ok(await query('MatCodeOwner', { matCode: 'mat-vp-30' }))._selectFirst;
  assert.equal(owner.table_name, 'vp_rates');
  assert.match(owner.item, /^Vision panel FD30/);
});

await test('a table name outside the priced tables changes nothing', async () => {
  const [row] = ok(await query('MatCodeTable', { ...ALL, kind: 'door' }))._select;
  const data = ok(await mutation('SetMatCode', { table: 'app_users', id: row.row_id, version: row.version, matCode: 'X' }));
  assert.equal(savedRow(data), null);
});

await test('SetPrice saves exactly and is versioned', async () => {
  const [row] = ok(await query('MatCodeTable', { ...ALL, kind: 'architrave', search: 'bespoke' }))._select;
  const vars = { table: row.table_name, id: row.row_id, version: row.version };
  const saved = savedRow(ok(await mutation('SetPrice', { ...vars, price: '42.10' })));
  assert.equal(saved.price, 42.1);
  assert.equal(savedRow(ok(await mutation('SetPrice', { ...vars, price: '1.00' }, SAM))), null);
});

await test('SearchProducts finds partial codes', async () => {
  const rows = ok(await query('SearchProducts', { search: '9205', categoryId: null, includeInactive: false, limit: 20 }))._select;
  assert.equal(rows.length, 1);
  assert.equal(rows[0].supplier_code, 'TS.9205');
});

await test('AddProduct + UpdateProduct (versioned), recorded against the signed-in user', async () => {
  const closers = ok(await query('ListCategories'))._select.find(c => c.key === 'closers');
  const added = ok(await mutation('AddProduct', {
    categoryId: closers.id, matCode: 'mat-cl-1', supplierCode: 'DC200', description: 'DC200 closer',
    finish: null, unit: null, cost: '44.00',
  }, SAM))._executeReturningFirst;
  assert.equal(added.version, 1);
  const upd = { id: added.id, version: 1, description: 'DC200 closer SSS', supplierCode: 'DC200', finish: 'SSS', unit: 'each', active: true };
  assert.equal(ok(await mutation('UpdateProduct', upd))._executeReturningFirst.version, 2);
  assert.equal(ok(await mutation('UpdateProduct', { ...upd, description: 'stale' }, SAM))._executeReturningFirst, null);
  const [p] = ok(await query('SearchProducts', { search: 'mat-cl-1', categoryId: closers.id, includeInactive: true, limit: 5 }))._select;
  assert.equal(p.description, 'DC200 closer SSS');
});

console.log(`== ${passed} operation checks passed`);
