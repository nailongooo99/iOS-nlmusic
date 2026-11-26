/*
 * LX UserApi v2 adapter. Protocol derived from the user's Android bridge and
 * uploaded LX Mobile preload. Runs inside a dedicated JavaScriptCore context.
 * No browser, filesystem, device identifiers or native objects are exposed.
 */
(() => {
  'use strict';
  const post = globalThis.__nlPost;
  const utility = globalThis.__nlUtility;
  const metadata = JSON.parse(globalThis.__nlMetadata);
  delete globalThis.__nlPost; delete globalThis.__nlUtility; delete globalThis.__nlMetadata;
  const pending = new Map(), timers = new Map();
  let sequence = 0, handler = null, inited = false, alerted = false;
  const key = () => String(++sequence);
  const call = (op, args) => utility(op, JSON.stringify(args));
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  const from64 = text => {
    text = String(text).replace(/\s/g,'');
    if (text.length > 3000000 || !/^[A-Za-z0-9+/]*={0,2}$/.test(text)) throw new Error('Invalid base64');
    const result = []; let bits = 0, value = 0;
    for (const c of text.replace(/=+$/,'')) {
      value = (value << 6) | chars.indexOf(c); bits += 6;
      if (bits >= 8) { bits -= 8; result.push((value >> bits)&255); }
    }
    return new Uint8Array(result);
  };
  const to64 = input => {
    const a = new Uint8Array(input);
    if (a.length > 2097152) throw new Error('Buffer too large');
    let out = '';
    for (let i=0;i<a.length;i+=3) {
      const x=(a[i]<<16)|((a[i+1]||0)<<8)|(a[i+2]||0);
      out+=chars[(x>>18)&63]+chars[(x>>12)&63]+(i+1<a.length?chars[(x>>6)&63]:'=')+(i+2<a.length?chars[x&63]:'=');
    }
    return out;
  };
  const from = (input, encoding) => {
    if (typeof input === 'string') {
      if (encoding === 'base64') return from64(input);
      if (encoding === 'hex') {
        if (!/^(?:[0-9a-fA-F]{2})*$/.test(input)) throw new Error('Invalid hex');
        return Uint8Array.from(input.match(/../g)||[], x=>parseInt(x,16));
      }
      if (encoding === 'binary') throw new Error('Binary strings unsupported');
      return from64(call('utf8',[input]));
    }
    if (Array.isArray(input) || ArrayBuffer.isView(input)) return new Uint8Array(input);
    if (input instanceof ArrayBuffer) return new Uint8Array(input);
    throw new Error('Unsupported buffer');
  };
  const bufToString = (buf, format) => {
    const a = from(buf);
    if (format==='binary') return a;
    if (format==='hex') return Array.from(a,b=>b.toString(16).padStart(2,'0')).join('');
    if (format==='base64') return to64(a);
    return call('decodeUTF8',[to64(a)]);
  };
  const utils = Object.freeze({
    buffer:Object.freeze({from,bufToString}),
    crypto:Object.freeze({
      md5(str) { if(typeof str!=='string') throw new Error('String required'); return call('md5',[str]); },
      randomBytes(n) {
        if (!Number.isInteger(n)||n<0||n>65536) throw new Error('Invalid random size');
        const result=from64(call('random',[n]));
        if (result.length!==n) throw new Error('Random source failed');
        return result;
      },
      aesEncrypt(buf,mode,secret,iv) {
        const out=call('aes',[to64(from(buf)),String(mode),to64(from(secret)),iv==null?'':to64(from(iv))]);
        if (!out && !(mode==='aes-128-ecb' && from(buf).length===0)) throw new Error('AES operation failed');
        return from64(out);
      },
      rsaEncrypt(buf,pem) {
        const out=call('rsa',[to64(from(buf)),String(pem)]);
        if (!out) throw new Error('RSA operation failed');
        return from64(out);
      },
    }),
  });
  const EVENT_NAMES=Object.freeze({request:'request',inited:'inited',updateAlert:'updateAlert'});
  const send=(event,data)=>{
    if(event===EVENT_NAMES.inited){
      if(inited) return Promise.reject(new Error('Script is inited'));
      inited=true;post('inited',JSON.stringify(data||{}));return Promise.resolve();
    }
    if(event===EVENT_NAMES.updateAlert){
      if(alerted) return Promise.reject(new Error('Already notified'));
      alerted=true;post('updateAlert',JSON.stringify({log:String(data?.log||'').slice(0,1024)}));
      return Promise.resolve(); // report only; never fetch or install a script update automatically
    }
    return Promise.reject(new Error('Unsupported event: '+event));
  };
  const on=(event,fn)=>{
    if(event!==EVENT_NAMES.request||typeof fn!=='function') return Promise.reject(new Error('Unsupported handler'));
    handler=fn;return Promise.resolve();
  };
  const request=(url,options,callback)=>{
    if(typeof options==='function'){callback=options;options={};}
    if(typeof callback!=='function') throw new Error('Request callback required');
    if(pending.size>=6) throw new Error('Too many pending HTTP requests');
    const id=key();pending.set(id,callback);
    try { post('http',JSON.stringify({requestKey:id,url:String(url),options:options||{}})); }
    catch(e){pending.delete(id);throw e;}
    return ()=>{if(pending.delete(id)) post('cancel',id);};
  };
  const setTimer=(fn,delay=0,...args)=>{
    if(typeof fn!=='function'||timers.size>=32) throw new Error('Invalid timer');
    const id=key();timers.set(id,()=>fn(...args));
    post('timer',JSON.stringify({key:id,delay:Math.max(0,Math.min(15000,Number(delay)||0))}));
    return id;
  };
  const clearTimer=id=>{id=String(id);if(timers.delete(id))post('cancelTimer',id);};
  const expose=(name,value)=>Object.defineProperty(globalThis,name,{value,writable:false,configurable:false});
  expose('lx',Object.freeze({EVENT_NAMES,request,send,on,utils,version:'2.0.0',env:'mobile',currentScriptInfo:Object.freeze(metadata)}));
  expose('setTimeout',setTimer);expose('clearTimeout',clearTimer);
  try { expose('console',Object.freeze({log(){},info(){},warn(){},error(){},debug(){}})); } catch {}
  expose('__nlHttpResponse',(id,json)=>{
    const cb=pending.get(id);if(!cb)return;
    pending.delete(id);
    const p=JSON.parse(json);
    if(p.error){cb(new Error(p.error),null,null);return;}
    const body=typeof p.binaryBase64==='string'?from64(p.binaryBase64):p.body;
    const response={statusCode:p.statusCode,statusMessage:p.statusMessage||'',headers:p.headers||{},body};
    cb(null,response,body);
  });
  expose('__nlTimer',id=>{const fn=timers.get(id);if(fn){timers.delete(id);fn();}});
  expose('__nlMusicUrl',(id,source,json,quality)=>{
    if(!handler){post('error',JSON.stringify({key:id,message:'没有注册 request 处理器'}));return;}
    Promise.resolve().then(()=>handler.call(lx,{source,action:'musicUrl',info:{musicInfo:JSON.parse(json),type:quality}}))
      .then(url=>{
        if(typeof url!=='string'||url.length>4096||!/^https:\/\//i.test(url.trim()))throw new Error('音源须返回有效 HTTPS 音频地址');
        post('musicUrl',JSON.stringify({key:id,url:url.trim()}));
      }).catch(e=>post('error',JSON.stringify({key:id,message:String(e?.message||e).slice(0,250)})));
  });
  // Match the upstream prohibition on dynamic eval; native evaluation of an
  // explicitly imported script still works. This is not a process sandbox.
  const deny=()=>{throw new Error('Dynamic code execution is not allowed');};
  try { Object.defineProperty(Function.prototype,'constructor',{value:deny,writable:false,configurable:false}); } catch {}
  try { expose('eval',deny); expose('Function',deny); } catch {}
})();
