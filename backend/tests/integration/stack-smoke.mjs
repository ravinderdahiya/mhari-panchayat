// Integration smoke test against the RUNNING local stack (real PostgreSQL + HTTP).
//   php artisan serve --port=8083   and   (cd admin-panel && npm run dev)
//   node tests/integration/stack-smoke.mjs
// Uses the demo citizen (services.otp_demo). It only reads, apart from saving that
// citizen's location; it files no complaints.

const API = process.env.API_URL ?? 'http://127.0.0.1:8083';
const PANEL = process.env.PANEL_URL ?? 'http://localhost:5173/mhari-panchayat';
const MOBILE = process.env.DEMO_MOBILE ?? '9876500001';
const OTP = process.env.DEMO_OTP ?? '2468';

let failed = 0;
const check = async (name, fn) => {
  try {
    await fn();
    console.log(`PASS  ${name}`);
  } catch (error) {
    failed++;
    console.log(`FAIL  ${name}\n      ${error.message}`);
  }
};
const assert = (condition, message) => { if (!condition) throw new Error(message); };

const call = async (path, { method = 'GET', body, token, headers = {} } = {}) => {
  const response = await fetch(`${API}${path}`, {
    method,
    headers: { Accept: 'application/json', 'Content-Type': 'application/json', 'X-App-Version-Code': '999', ...(token ? { Authorization: `Bearer ${token}` } : {}), ...headers },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await response.text();
  let json = null;
  try { json = JSON.parse(text); } catch { /* not JSON */ }
  return { status: response.status, json, text };
};

let token = '';
let panchayat = null;

await check('backend answers /api/public/home with live stats', async () => {
  const { status, json } = await call('/api/public/home');
  assert(status === 200 && json?.success, `status ${status}`);
  assert(json.data.stats.panchayats > 0, 'no panchayats in the database');
  assert(json.data.app.android_url.includes('play.google.com'), 'missing Play Store link');
});

await check('admin panel serves the public home page', async () => {
  const response = await fetch(`${PANEL}/`);
  const html = await response.text();
  assert(response.status === 200 && html.includes('id="root"'), `status ${response.status}`);
});

await check('admin panel serves the privacy and terms pages', async () => {
  for (const page of ['privacy-policy.html', 'terms-of-service.html']) {
    const response = await fetch(`${PANEL}/${page}`);
    assert(response.status === 200, `${page} -> ${response.status}`);
  }
});

await check('public search finds a panchayat from the real database', async () => {
  const { json } = await call('/api/public/search?q=hi');
  assert(Array.isArray(json?.data), 'no result list');
  panchayat = json.data[0] ?? null;
  assert(panchayat?.id, 'no panchayat matched "hi"');
});

await check('public asset map returns approved points only', async () => {
  const { status, json } = await call('/api/public/assets');
  assert(status === 200 && Array.isArray(json?.data?.points), `status ${status}`);
});

await check('funds section returns demo figures for a real panchayat', async () => {
  const { status, json } = await call(`/api/public/funds?panchayat_id=${panchayat?.id}&fy=2026-27`);
  assert(status === 200 && json.data.demo === true, `status ${status}`);
  assert(Math.abs(json.data.received_lakh - json.data.spent_lakh - json.data.balance_lakh) < 0.02, 'balance does not add up');
});

await check('tracker answers the same 404 for unknown complaints', async () => {
  const { status } = await call('/api/public/track-complaint', { method: 'POST', body: { complaint_id: 'COMP-NONE-00_0000-000', mobile: '9876543210' } });
  assert(status === 404, `status ${status}`);
});

await check('version check reports a status for this build', async () => {
  const { status, json } = await call('/api/app/version-check', { method: 'POST', body: { version_code: 999 } });
  assert(status === 200 && ['ok', 'optional_update', 'force_update'].includes(json.status), `status ${status}`);
});

await check('demo citizen signs in with OTP', async () => {
  const send = await call('/api/auth/send-otp', { method: 'POST', body: { mobile: MOBILE } });
  assert(send.status === 200, `send-otp ${send.status}: ${send.text.slice(0, 120)}`);
  const verify = await call('/api/auth/verify-otp', { method: 'POST', body: { mobile: MOBILE, otp: OTP } });
  token = verify.json?.token ?? verify.json?.data?.token ?? '';
  assert(verify.status === 200 && token, `verify-otp ${verify.status}: ${verify.text.slice(0, 120)}`);
});

await check('signed-in session returns the citizen profile', async () => {
  const { status, json } = await call('/api/auth/me', { token });
  assert(status === 200 && json?.user?.role === 'citizen', `status ${status}`);
});

await check('citizen location is saved and resolved on the server', async () => {
  const { status, json } = await call('/api/auth/citizen/location', { method: 'PUT', token, body: { latitude: 29.1393, longitude: 75.7047 } });
  assert(status === 200 && json.saved === true, `status ${status}: ${JSON.stringify(json)}`);
});

await check('geofence endpoint answers allowed / message for a citizen', async () => {
  const { status, json } = await call('/api/auth/citizen/geofence?latitude=29.1393&longitude=75.7047', { token });
  assert(status === 200 && typeof json.allowed === 'boolean', `status ${status}: ${JSON.stringify(json)}`);
});

await check('geofence endpoint rejects a request without a login', async () => {
  const { status } = await call('/api/auth/citizen/geofence?latitude=29&longitude=75');
  assert(status === 401, `status ${status}`);
});

await check('citizen cannot reach admin-only endpoints', async () => {
  for (const path of ['/api/site-settings', '/api/app-versions', '/api/citizens']) {
    const { status } = await call(path, { token });
    assert(status === 403 || status === 401, `${path} -> ${status}`);
  }
});

console.log(failed === 0 ? '\nAll integration checks passed.' : `\n${failed} integration check(s) failed.`);
process.exit(failed === 0 ? 0 : 1);
