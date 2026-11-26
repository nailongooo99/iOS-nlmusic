import Foundation

// Runs on the GitHub macOS/Xcode runner using real Apple JavaScriptCore,
// Security, and CommonCrypto. No third-party audio or live network is used.
@main struct LXNativeTests {
    static func require(_ condition:Bool,_ message:String) throws {
        if !condition { throw MusicError.message("LX native regression: "+message) }
    }
    @MainActor static func main() async throws {
        let bootstrap=try String(contentsOfFile:"NailongMusic/Resources/lx-user-api-ios.js",encoding:.utf8)
        let runtime=LXRuntime(bootstrapOverride:bootstrap)
        defer { runtime.close() }
        let script="""
        /**
         * @name Offline Fixture
         * @author Test
         * @version 2.0
         */
        if (lx.version!=='2.0.0' || lx.currentScriptInfo.name!=='Offline Fixture') throw Error('metadata');
        const b=lx.utils.buffer,c=lx.utils.crypto;
        if(b.bufToString(b.from('中文😀'))!=='中文😀')throw Error('utf8');
        if(c.md5('abc')!=='900150983cd24fb0d6963f7d28e17f72')throw Error('md5');
        if(c.randomBytes(16).length!==16)throw Error('random');
        const aes=c.aesEncrypt(b.from('00112233445566778899aabbccddeeff','hex'),'aes-128-ecb',b.from('000102030405060708090a0b0c0d0e0f','hex'));
        if(b.bufToString(aes,'hex')!=='69c4e0d86a7b0430d8cdb78070b4c55a')throw Error('aes');
        lx.on(lx.EVENT_NAMES.request,({source,action,info})=>new Promise((resolve,reject)=>{
          if(source!=='wy'||action!=='musicUrl'||info.musicInfo.songmid!=='offline-id'||info.type!=='320k')return reject(Error('music info'));
          // This is rejected before DNS/HTTP, exercising the actual async callback path.
          lx.request('https://127.0.0.1/forbidden',{},(err,resp,body)=>{
            if(!err)return reject(Error('private URL not blocked'));
            setTimeout(()=>resolve('https://media.example.org/authorized-fixture.mp3'),5);
          });
        }));
        lx.send(lx.EVENT_NAMES.inited,{sources:{wy:{type:'music',actions:['musicUrl'],qualitys:['320k','128k']}}});
        """
        let source=LXSource(metadata:LXMetadata.parse(script,fallback:"Fixture"),origin:"offline",script:script)
        let capabilities=try await runtime.initialize(source,timeout:5)
        try require(capabilities["wy"]==["320k","128k"],"standard inited event")
        let track=Track(id:"offline-id",title:"Fixture",artist:"Test",platform:.wy)
        let url=try await runtime.resolve(track,quality:"320k",timeout:5)
        try require(url=="https://media.example.org/authorized-fixture.mp3","request, timer and musicUrl")
        runtime.close()
        let timeoutRuntime=LXRuntime(bootstrapOverride:bootstrap)
        defer { timeoutRuntime.close() }
        let never=LXSource(metadata:LXMetadata(name:"No initialization"),origin:"offline",script:"lx.on('request',()=>new Promise(()=>{}));")
        do {
            _=try await timeoutRuntime.initialize(never,timeout:0.3)
            throw MusicError.message("LX native regression: timeout accepted")
        } catch {
            try require(error.localizedDescription.contains("初始化超时"),"initialization deadline")
        }
        print("PASS: native JavaScriptCore LX initialization, metadata, UTF-8, MD5, AES, random, local URL rejection, callback, timer, timeout")
    }
}
