import Foundation
import CryptoKit
import CommonCrypto
import Security

enum LXCrypto {
    static func run(_ op:String,_ raw:String) -> String {
        guard raw.utf8.count <= 6*1024*1024,
              let args = (try? JSONSerialization.jsonObject(with:Data(raw.utf8))) as? [Any] else { return "" }
        func str(_ i:Int) -> String { args.indices.contains(i) ? args[i] as? String ?? "" : "" }
        func bytes(_ i:Int) -> Data? { let s=str(i); guard s.utf8.count <= 2800000 else { return nil }; return Data(base64Encoded:s) }
        switch op {
        case "utf8": return Data(str(0).utf8).base64EncodedString()
        case "decodeUTF8": return bytes(0).map { String(decoding:$0,as:UTF8.self) } ?? ""
        case "md5": return Insecure.MD5.hash(data:Data(str(0).utf8)).map{String(format:"%02x",$0)}.joined()
        case "random":
            guard let number=args.first as? NSNumber,number.doubleValue.isFinite,
                  number.doubleValue.rounded() == number.doubleValue,(0...65536).contains(number.intValue) else { return "" }
            let count=number.intValue
            if count == 0 { return "" }
            var data=Data(count:count)
            let status=data.withUnsafeMutableBytes { ptr -> OSStatus in
                guard let address=ptr.baseAddress else { return errSecParam }
                return SecRandomCopyBytes(kSecRandomDefault,count,address)
            }
            return status == errSecSuccess ? data.base64EncodedString() : ""
        case "aes":
            guard let input=bytes(0),let key=bytes(2),key.count==16,input.count<=1024*1024 else { return "" }
            let mode=str(1)
            let iv=bytes(3) ?? Data()
            guard (mode=="aes-128-cbc" && iv.count==16) || (mode=="aes-128-ecb" && input.count%16==0) else { return "" }
            let option=CCOptions(mode=="aes-128-cbc" ? kCCOptionPKCS7Padding : kCCOptionECBMode)
            var output=Data(count:input.count+16)
            let capacity=output.count
            var written=0
            let status=output.withUnsafeMutableBytes { out in
                input.withUnsafeBytes { data in
                    key.withUnsafeBytes { secret in
                        iv.withUnsafeBytes { vector in
                            CCCrypt(CCOperation(kCCEncrypt),CCAlgorithm(kCCAlgorithmAES),option,
                                    secret.baseAddress,key.count,mode=="aes-128-cbc" ? vector.baseAddress : nil,
                                    data.baseAddress,input.count,out.baseAddress,capacity,&written)
                        }
                    }
                }
            }
            guard status==kCCSuccess else { return "" }
            return output.prefix(written).base64EncodedString()
        case "rsa":
            guard let input=bytes(0),input.count<=1024,let keyData=publicKey(str(1)) else { return "" }
            let attrs:[String:Any]=[kSecAttrKeyType as String:kSecAttrKeyTypeRSA,kSecAttrKeyClass as String:kSecAttrKeyClassPublic]
            guard let key=SecKeyCreateWithData(keyData as CFData,attrs as CFDictionary,nil),
                  SecKeyIsAlgorithmSupported(key,.encrypt,.rsaEncryptionRaw) else { return "" }
            let size=SecKeyGetBlockSize(key)
            guard size>=128,size<=1024,input.count<=size else { return "" }
            let padded=Data(repeating:0,count:size-input.count)+input
            guard let encrypted=SecKeyCreateEncryptedData(key,.rsaEncryptionRaw,padded as CFData,nil) else { return "" }
            return (encrypted as Data).base64EncodedString()
        default: return ""
        }
    }
    // Convert SubjectPublicKeyInfo (PEM PUBLIC KEY) to PKCS#1 DER.
    private static func publicKey(_ text:String) -> Data? {
        guard text.count<=16384 else { return nil }
        let b64=text.replacingOccurrences(of:#"-----[^-]+-----|\s"#,with:"",options:.regularExpression)
        guard let der=Data(base64Encoded:b64) else { return nil }
        let a=[UInt8](der)
        func tlv(_ pos:inout Int,_ tag:UInt8,_ end:Int) -> Range<Int>? {
            guard pos+2<=end,a[pos]==tag else { return nil }; pos+=1
            var length=Int(a[pos]);pos+=1
            if length>=128 {
                let count=length&127
                guard count>0,count<=3,pos+count<=end else { return nil }
                length=0
                for _ in 0..<count { length=length*256+Int(a[pos]);pos+=1 }
            }
            guard length<=end-pos else { return nil }
            let range=pos..<(pos+length);pos+=length;return range
        }
        var i=0
        guard let outer=tlv(&i,0x30,a.count),i==a.count,!outer.isEmpty else { return nil }
        var j=outer.lowerBound
        if a[j]==0x02 { return der }
        guard tlv(&j,0x30,outer.upperBound) != nil,
              let bit=tlv(&j,0x03,outer.upperBound),bit.count>1,a[bit.lowerBound]==0 else { return nil }
        return Data(a[(bit.lowerBound+1)..<bit.upperBound])
    }
}
