'use strict';
// These are protocol tests with a fake host, not a real streaming source.
const fs=require('fs'),vm=require('vm'),assert=require('assert/strict'),crypto=require('crypto');
const bridge=fs.readFileSync('NailongMusic/Resources/lx-user-api-ios.js','utf8');
async function main(){
  const messages=[];
  const context=vm.createContext({
    __nlMetadata:JSON.stringify({name:'Offline LX fixture',version:'2.0',author:'Test',rawScript:'fixture'}),
    __nlPost:(action,raw)=>messages.push({action,raw}),
    __nlUtility:(op,raw)=>{
      const a=JSON.parse(raw);
      if(op==='utf8')return Buffer.from(a[0],'utf8').toString('base64');
      if(op==='decodeUTF8')return Buffer.from(a[0],'base64').toString('utf8');
      if(op==='md5')return crypto.createHash('md5').update(a[0],'utf8').digest('hex');
      if(op==='random')return Buffer.alloc(a[0],42).toString('base64');
      if(op==='aes'){
        const algorithm=a[1]==='aes-128-cbc'?'aes-128-cbc':'aes-128-ecb';
        const cipher=crypto.createCipheriv(algorithm,Buffer.from(a[2],'base64'),algorithm.endsWith('cbc')?Buffer.from(a[3],'base64'):null);
        cipher.setAutoPadding(algorithm.endsWith('cbc'));
        return Buffer.concat([cipher.update(Buffer.from(a[0],'base64')),cipher.final()]).toString('base64');
      }
      throw new Error('Unexpected mock op '+op);
    }
  });
  const evalJS=s=>vm.runInContext(s,context,{timeout:1000});
  evalJS(bridge);
  assert.equal(evalJS('lx.version'),'2.0.0');
  assert.equal(evalJS('lx.env'),'mobile');
  assert.equal(evalJS('lx.currentScriptInfo.name'),'Offline LX fixture');
  assert.equal(evalJS('lx.utils.crypto.md5("中文+emoji😀")'),crypto.createHash('md5').update('中文+emoji😀').digest('hex'));
  assert.equal(evalJS('lx.utils.buffer.bufToString(lx.utils.buffer.from("中文😀"))'),'中文😀');
  assert.equal(evalJS('lx.utils.buffer.bufToString(lx.utils.buffer.from("0001feff","hex"),"base64")'),'AAH+/w==');
  assert.equal(evalJS('lx.utils.buffer.bufToString(lx.utils.crypto.randomBytes(3),"hex")'),'2a2a2a');
  assert.equal(evalJS('lx.utils.buffer.bufToString(lx.utils.crypto.aesEncrypt(lx.utils.buffer.from("00112233445566778899aabbccddeeff","hex"),"aes-128-ecb",lx.utils.buffer.from("000102030405060708090a0b0c0d0e0f","hex")),"hex")'),'69c4e0d86a7b0430d8cdb78070b4c55a');
  await evalJS(`
    lx.on(lx.EVENT_NAMES.request,({source,action,info})=>{
      if(source!=='wy'||action!=='musicUrl'||info.musicInfo.songmid!=='fixture-id'||info.type!=='320k')throw Error('bad metadata');
      return new Promise((resolve,reject)=>lx.request('https://example.org/fixture',{method:'POST',body:{id:info.musicInfo.songmid}},(error,response,body)=>{
        if(error)return reject(error);
        if(response.statusCode!==200||body.ok!==true)return reject(Error('bad response'));
        setTimeout(()=>resolve('https://media.example.org/owned-fixture.mp3'),1);
      }));
    });
    lx.send(lx.EVENT_NAMES.inited,{sources:{wy:{type:'music',actions:['musicUrl'],qualitys:['320k','128k']}}});
  `);
  assert.equal(messages[0].action,'inited');
  assert.equal(JSON.parse(messages[0].raw).status,undefined);
  evalJS(`__nlMusicUrl("music1","wy",JSON.stringify({songmid:"fixture-id"}),"320k")`);
  await new Promise(resolve=>setImmediate(resolve));
  const request=messages.find(x=>x.action==='http');
  assert.ok(request);
  const req=JSON.parse(request.raw);
  assert.equal(req.options.body.id,'fixture-id');
  evalJS(`__nlHttpResponse(${JSON.stringify(req.requestKey)},${JSON.stringify(JSON.stringify({statusCode:200,body:{ok:true}}))})`);
  const timer=JSON.parse(messages.find(x=>x.action==='timer').raw);
  evalJS(`__nlTimer(${JSON.stringify(timer.key)})`);
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(JSON.parse(messages.find(x=>x.action==='musicUrl').raw).url,'https://media.example.org/owned-fixture.mp3');
  evalJS(`globalThis.binaryResult=''; lx.request('https://example.org/binary',{binary:true},(_,resp,body)=>{binaryResult=lx.utils.buffer.bufToString(body,'hex');});`);
  const binary=JSON.parse(messages.filter(x=>x.action==='http').at(-1).raw);
  evalJS(`__nlHttpResponse(${JSON.stringify(binary.requestKey)},${JSON.stringify(JSON.stringify({statusCode:200,binaryBase64:"AAH+/w=="}))})`);
  assert.equal(evalJS('binaryResult'),'0001feff');
  evalJS(`globalThis.called=false; const abort=lx.request('https://example.org/abort',()=>{called=true});abort();`);
  const cancelled=messages.filter(x=>x.action==='cancel').at(-1);
  assert.ok(cancelled);
  evalJS(`__nlHttpResponse(${JSON.stringify(cancelled.raw)},'{"statusCode":200,"body":"ignored"}')`);
  assert.equal(evalJS('called'),false);
  await assert.rejects(evalJS(`lx.send(lx.EVENT_NAMES.inited,{})`),/Script is inited/);
  await evalJS(`lx.on(lx.EVENT_NAMES.request,()=>Promise.resolve("http://example.org/cleartext.mp3"));`);
  evalJS(`__nlMusicUrl("http-ok","wy","{}","128k")`);
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(JSON.parse(messages.find(x=>x.action==='musicUrl'&&JSON.parse(x.raw).key==='http-ok').raw).url,'http://example.org/cleartext.mp3');
  await evalJS(`lx.on(lx.EVENT_NAMES.request,()=>Promise.resolve("file:///private/secret.mp3"));`);
  evalJS(`__nlMusicUrl("bad","wy","{}","128k")`);
  await new Promise(resolve=>setImmediate(resolve));
  assert.ok(messages.some(x=>x.action==='error'&&JSON.parse(x.raw).key==='bad'));
  assert.throws(()=>evalJS(`eval("1+1")`),/Dynamic code execution/);
  console.log('PASS: LX bridge events, async callbacks, timers, abort, binary, buffer, crypto contract, HTTP/HTTPS protocol (mock host)');
}
main().catch(e=>{console.error(e);process.exitCode=1;});
