const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const parser = fs.readFileSync(path.join(root, 'vendor/lee-su-threads/profileParser.js'), 'utf8').replace(/^export \{.*\};/m, '');
const fixture = n => fs.readFileSync(path.join(__dirname, 'fixtures', n), 'utf8');
const ctx = vm.createContext({console: {error() {}}}); vm.runInContext(parser, ctx);
const cases = [
 ['profile-basic-en.txt','January 2024','Taiwan'], ['profile-basic-zh.txt','2024年1月','台灣'],
 ['profile-basic-ja.txt','2023年7月','台湾'], ['profile-verified.txt','July 2023','United States'],
 ['profile-own-verified-zh.txt','2025年11月','台灣'], ['profile-own-verified-ja.txt','2025年11月','台湾'],
 ['profile-verified-ko.txt','2023년 7월','미국'], ['profile-hidden-location-zh.txt','2023年7月','未分享'],
 ['profile-no-location-ja.txt','2024年10月',undefined], ['profile-former-username-ja.txt','2025年12月','日本'],
 ['profile-former-username-zh.txt','2025年12月','台灣'], ['profile-dynamic-bind.txt','July 2023','台灣'],
 ['profile-chinese-labels.txt','2024年1月','台灣'], ['profile-not-shared-zh.txt','2023年7月','未分享']
];
for (const [file, joined, location] of cases) test(file, () => {
 const p = ctx.parseProfileResponse(fixture(file)); assert.equal(p.joined, joined); assert.equal(p.location, location);
});
function bridge(fetch, authenticated = true, host = 'www.threads.com', options = {}) {
 const context = vm.createContext({window: options.window || {}, location:{hostname:host}, URLSearchParams, AbortController, setTimeout, clearTimeout,
   Date: options.now ? class extends Date {static now() {return options.now();}} : Date,
   crypto:require('node:crypto').webcrypto, fetch,
   console:{error(){}}, document:{querySelectorAll: selector => {
    if (selector.startsWith('input')) return [];
    options.onScan?.();
    return [{textContent: options.script ? options.script() : authenticated ? '"DTSGInitialData":{"token":"secret-token"},"USER_ID":"123456789012"' : ''}];
   }}
 });
 vm.runInContext(fs.readFileSync(path.join(root,'layout/Library/Application Support/ThreadsPulse/ThreadsPulse.bundle/LeeSuBridge.js'),'utf8'), context);
 return context.window.TPLeeSu;
}
test('only sends requested ID to same-origin Threads and returns public fields', async () => {
 const api = bridge(async (url, options) => {
  assert.ok(url.startsWith('/async/wbloks/fetch/')); assert.equal(options.credentials,'include');
  assert.equal(JSON.parse(options.body.get('params')).target_user_id,'321');
  assert.equal(options.body.get('fb_dtsg'),'secret-token');
  return {ok:true,status:200,text:async()=>fixture('profile-basic-en.txt')};
 });
 assert.equal(api.ready(),true); const result = await api.profile('321');
 assert.equal(result.location,'Taiwan'); assert.equal(result.username,'testuser');
 assert.deepEqual(Object.keys(result).sort(),['displayName','isNew','joined','location','username']);
 assert.ok(!JSON.stringify(result).includes('secret-token'));
});
test('does not request profiles without login', async () => {
 const api = bridge(()=>{throw Error('should not fetch');},false);
 assert.equal(api.ready(),false); assert.equal((await api.profile('123'))._loginRequired,true);
});
test('rejects invalid IDs and does not expose bridge on another origin', async () => {
 assert.equal((await bridge(()=>{throw Error('fetch');}).profile('1&admin=true'))._error,'invalid_id');
 assert.equal(bridge(()=>{},true,'instagram.com'),undefined);
});
for (const status of [429,401,403,500]) test(`handles HTTP ${status}`, async()=>{
 const result = await bridge(async()=>({status,ok:false})).profile('123');
 assert.equal(result[status===429?'_rateLimited':status===500?'_error':'_loginRequired'],status===500?'http':true);
});
test('malformed responses and fetch failures remain recoverable', async()=>{
 const bad = await bridge(async()=>({status:200,ok:true,text:async()=>'<html>login</html>'})).profile('123');
 assert.equal(bad._error,'unavailable');
 const failed = await bridge(async()=>{throw Error('offline')}).profile('123'); assert.equal(failed._error,'network');
});
test('reuses session scan for consecutive authors and refreshes it after 60 seconds', async()=>{
 let now=0, scans=0;
 const api=bridge(async()=>({status:200,ok:true,text:async()=>fixture('profile-basic-en.txt')}),true,'www.threads.com',{
  now:()=>now, onScan:()=>scans++
 });
 await api.profile('1'); await api.profile('2'); assert.equal(scans,1);
 now=60001; await api.profile('3'); assert.equal(scans,2);
});
test('authentication rejection invalidates cached tokens before another query', async()=>{
 let token='old-token', calls=0, scans=0;
 const api=bridge(async(_,options)=>{
  assert.equal(options.body.get('fb_dtsg'),token); calls++;
  return calls===1 ? {status:403,ok:false} : {status:200,ok:true,text:async()=>fixture('profile-basic-en.txt')};
 },true,'www.threads.com',{onScan:()=>scans++,script:()=>`"DTSGInitialData":{"token":"${token}"},"USER_ID":"123456789012"`});
 assert.equal((await api.profile('1'))._loginRequired,true);
 token='new-token'; assert.equal((await api.profile('2')).location,'Taiwan'); assert.equal(scans,2);
});
test('notifies native readiness at document end with only a boolean',()=>{
 const messages=[];
 const window={webkit:{messageHandlers:{TPLeeSuReady:{postMessage:value=>messages.push(value)}}}};
 bridge(()=>{},true,'www.threads.com',{window}); assert.deepEqual(messages,[true]);
 messages.length=0; bridge(()=>{},false,'www.threads.com',{window}); assert.deepEqual(messages,[]);
});
