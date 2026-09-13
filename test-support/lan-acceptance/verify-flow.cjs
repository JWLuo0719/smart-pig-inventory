// Explicit local research harness. Test config and all evidence stay ignored.
const fs = require('node:fs');
const path = require('node:path');
const https = require('node:https');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../..');
const config = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const env = Object.fromEntries(fs.readFileSync(path.join(root, '.env'), 'utf8').split(/\r?\n/)
  .filter(line => /^[^#=]+=/.test(line)).map(line => [line.slice(0,line.indexOf('=')).trim(),line.slice(line.indexOf('=')+1).trim()]));
const ca = fs.readFileSync(path.join(root,'artifacts/lan-acceptance/tls/ca.pem'));
const base = 'https://pig-inventory.local:8443/api/v1';
const agent = new https.Agent({ca});
const uuid = () => crypto.randomUUID();
const sleep = ms => new Promise(resolve => setTimeout(resolve,ms));
async function request(method, route, {token,body,key=uuid(),headers={},expect}={}) {
  const payload = body === undefined ? null : Buffer.isBuffer(body) ? body : Buffer.from(JSON.stringify(body));
  const opts = {method,agent,headers:{'X-Idempotency-Key':key,...headers}};
  if (token) opts.headers.Authorization = `Bearer ${token}`;
  if (payload) { opts.headers['Content-Type'] ??= 'application/json'; opts.headers['Content-Length']=payload.length; }
  return new Promise((resolve,reject) => {
    const req = https.request(base+route,opts,res => {
      const chunks=[];
      res.on('data',c=>chunks.push(c));
      res.on('end',()=>{
        if (expect && res.statusCode === expect) return resolve({status:res.statusCode});
        if (res.statusCode < 200 || res.statusCode >= 300 || expect) return reject(new Error(`${method} ${route}: unexpected HTTP ${res.statusCode}`));
        const text=Buffer.concat(chunks).toString();
        try {resolve(text ? JSON.parse(text) : null);} catch {reject(new Error('Invalid JSON response'));}
      });
    });
    req.setTimeout(15000,()=>req.destroy(new Error('HTTPS request timeout')));
    req.on('error',reject);
    if(payload) req.write(payload);
    req.end();
  });
}
(async()=>{
  assert.equal(env.MODEL_APPROVED,'false');
  assert.equal(env.COUNTING_PROVIDER,'research-http-yolo');
  const login=async username => (await request('POST','/auth/login',{body:{username,password:env.APP_E2E_FIXTURE_PASSWORD}})).accessToken;
  const operator=await login('e2e-operator');
  const me=await request('GET','/me',{token:operator});
  const master=await request('GET','/master-data/changes',{token:operator});
  const pen=master.pens.find(p=>p.code==='E2E-P01');
  assert.ok(pen,'Synthetic E2E pen required');
  const date=new Date().toLocaleDateString('en-CA',{timeZone:'Asia/Shanghai'});
  let commit;
  if (config.resumeCommit) {
    commit=config.resumeCommit;
  } else {
  const image=fs.readFileSync(config.imagePath);
  const sha=crypto.createHash('sha256').update(image).digest('hex');
  const pkg=await request('POST','/upload-packages',{token:operator,body:{clientPackageId:uuid(),organizationId:me.activeOrganizationId,penId:pen.id,businessDate:date,captureKind:'single'}});
  const assetId=uuid();
  await request('PUT',`/upload-packages/${pkg.id}/blobs/${assetId}`,{token:operator,body:image,headers:{'Content-Type':'application/octet-stream','X-Content-SHA256':sha}});
  await request('PUT',`/upload-packages/${pkg.id}/manifest`,{token:operator,body:{captureSetId:uuid(),captureKind:'single',penId:pen.id,assets:[{assetId,viewPosition:'single',capturedAt:new Date().toISOString(),originalName:'authorized-research-e2e.jpg',width:config.width,height:config.height,sha256:sha,perceptualHash:null,byteSize:image.length,mediaType:'image/jpeg',exif:{},roi:null}]}});
  const commitKey=uuid();
  commit=await request('POST',`/upload-packages/${pkg.id}/commit`,{token:operator,key:commitKey});
  const replay=await request('POST',`/upload-packages/${pkg.id}/commit`,{token:operator,key:commitKey});
  assert.equal(commit.inferenceJobId,replay.inferenceJobId);
  config.resumeCommit=commit;
  fs.writeFileSync(process.argv[2],JSON.stringify(config,null,2));
  }
  let session;
  for(let i=0;i<60;i++) {
    session=await request('GET',`/inventory-sessions/${commit.sessionId}`,{token:operator});
    if(session.status==='review_required' || session.status==='confirmed') break;
    await sleep(2000);
  }
  assert.ok(Number.isInteger(session.rawModelCount));
  assert.equal(session.model.checksum,env.MODEL_CHECKSUM);
  if (session.status==='review_required') {
  assert.equal(session.count,null);
  const before=await request('GET',`/inventory-reports/daily?businessDate=${date}`,{token:operator});
  assert.ok(!before.some(row=>row.sessionId===commit.sessionId));
  // Count comes from independent fixture labels supplied in config, never the AI value.
  assert.ok(Number.isInteger(config.manualCount) && config.manualCount>=0);
  const confirmation={confirmedCount:config.manualCount,reason:'Authorized research fixture label; automated workflow verification only'};
  await request('POST',`/inventory-sessions/${commit.sessionId}/confirm`,{token:operator,body:confirmation,expect:404});
  const unchanged=await request('GET',`/inventory-sessions/${commit.sessionId}`,{token:operator});
  assert.equal(unchanged.status,'review_required');
  assert.equal(unchanged.count,null);
  config.preConfirmationVerified=true;
  config.confirmKey=uuid();
  fs.writeFileSync(process.argv[2],JSON.stringify(config,null,2));
  } else {
    assert.equal(session.status,'confirmed');
    assert.equal(config.preConfirmationVerified,true,'Resume requires preserved pre-confirmation verification');
    assert.ok(config.confirmKey);
  }
  const confirmation={confirmedCount:config.manualCount,reason:'Authorized research fixture label; automated workflow verification only'};
  const reviewer=await login('e2e-reviewer');
  const confirmKey=config.confirmKey;
  const confirmed=await request('POST',`/inventory-sessions/${commit.sessionId}/confirm`,{token:reviewer,body:confirmation,key:confirmKey});
  assert.equal(confirmed.status,'confirmed');
  assert.equal(confirmed.id,commit.sessionId);
  assert.equal(confirmed.count,config.manualCount);
  const confirmedReplay=await request('POST',`/inventory-sessions/${commit.sessionId}/confirm`,{token:reviewer,body:confirmation,key:confirmKey});
  assert.equal(confirmedReplay.id,confirmed.id);
  const daily=await request('GET',`/inventory-reports/daily?businessDate=${date}`,{token:reviewer});
  assert.equal(daily.find(row=>row.sessionId===commit.sessionId)?.confirmedCount,config.manualCount);
  const media=await request('GET',`/inventory-sessions/${commit.sessionId}/media`,{token:reviewer});
  assert.ok(media.length>0);
  assert.ok(media.every(item=>item.locked===true),'Confirmed evidence must be locked');
  const evidence={status:'passed',verifiedAt:new Date().toISOString(),transport:'HTTPS with exact private CA and DNS hostname verification',sessionId:commit.sessionId,inferenceJobId:commit.inferenceJobId,candidateCount:session.rawModelCount,fixtureLabelCount:config.manualCount,confirmedCount:confirmed.count,commitReplay:true,operatorDenied:true,confirmReplay:true,reportVerified:true,mediaLocked:true,modelApproved:false,manualAcceptance:'pending',resumeNote:config.resumeNote??null};
  fs.writeFileSync(config.evidencePath,JSON.stringify(evidence,null,2));
  console.log(JSON.stringify(evidence));
})().catch(error=>{console.error(error.message);process.exitCode=1;}).finally(()=>agent.destroy());
