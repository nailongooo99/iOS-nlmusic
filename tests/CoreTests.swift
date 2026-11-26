import Foundation
@main struct CoreTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }
    static func main() throws {
        let lines = Lyrics.parse("[ar:测试]\n[offset:100]\n[00:01.20][00:03.2]第一句\n[00:04.050]第二句",translation:"[00:01.30]Translation")
        require(lines.count == 3,"LRC multiple timestamps")
        require(abs(lines[0].time-1.3)<0.0001,"LRC offset/fraction")
        require(lines[0].translation == "Translation","translation")
        require(Lyrics.active(lines,at:0) == nil,"before first")
        require(Lyrics.active(lines,at:3.5) == 1,"active index")
        require(Lyrics.active(lines,at:99) == 2,"after last")
        let yrc = Lyrics.parse("[1000,1200](1000,500,0)你(1500,700,0)好")
        require(yrc.count == 1 && yrc[0].text == "你好" && yrc[0].words.count == 2,"YRC words")
        require(abs(yrc[0].words[1].end-2.2)<0.0001,"YRC word time")
        let merged = Lyrics.complete(yrc,base:Lyrics.parse("[00:01.00]你好\n[00:03.00]尾句"))
        require(merged.count == 2 && !merged[0].words.isEmpty,"complete word timeline with plain LRC")
        let enhanced = Lyrics.parse("[00:01.00]<00:01.00>Hey <00:01.50>you")
        require(enhanced[0].words.count == 2 && enhanced[0].text == "Hey you","enhanced LRC")
        require(Lyrics.parse("[ar:artist]\nempty\n[00:01.0]").isEmpty,"metadata ignored")
        require(PlayMode.order.next(current:2,count:3,automatic:true) == nil,"order end")
        require(PlayMode.repeatAll.next(current:2,count:3,automatic:true) == 0,"repeat wrap")
        require(PlayMode.repeatOne.next(current:1,count:3,automatic:true) == 1,"repeat one")
        require(PlayMode.repeatOne.next(current:1,count:3,automatic:false) == 2,"manual next")
        require(PlayMode.shuffle.next(current:0,count:1,automatic:false) == nil,"single shuffle")
        require(PlayMode.shuffle.next(current:0,count:2,automatic:true) == 1,"shuffle no immediate repeat")
        let a = Track(id:"1",title:"A",artist:"B",platform:.wy,playableUri:"https://example.com/private.mp3?token=123",extra:#"{"songmid":"1","cookie":"secret","albumName":"album"}"#)
        let b = Track(id:"1",title:"A",artist:"B",platform:.tx)
        require([a,a,b].uniqueTracks().count == 2,"cross-platform stable key")
        require(a.portable().playableUri.isEmpty && a.portable().metadata["cookie"] == nil,"portable privacy")
        require(a.portable().metadata["albumName"] == "album","portable metadata")
        var backup = LibraryBackup()
        backup.favorites = [a,a,b]
        let clean = try backup.validated()
        require(clean.favorites.count == 2 && clean.favorites[0].playableUri.isEmpty,"backup normalization")
        let encoded = try JSONEncoder().encode(clean)
        let roundtrip = try JSONDecoder().decode(LibraryBackup.self,from:encoded)
        require(roundtrip.favorites.count == 2,"backup roundtrip")
        let old = #"{"type":"nailong.music.library","version":1,"exportedAt":0,"favorites":[],"recent":[],"playlists":[],"searches":[]}"#
        let legacy = try JSONDecoder().decode(LibraryBackup.self,from:Data(old.utf8)).validated()
        require(legacy.version == 1 && legacy.statistics == nil,"Android v1")
        // Regression: the actual mutation used by Library.add must compile
        // and preserve uniqueness, platform identity and unrelated playlists.
        var edited = LibraryBackup()
        let c1 = MusicCollection(id:"local-test-a",name:"A",platform:.wy)
        let c2 = MusicCollection(id:"local-test-b",name:"B",platform:.wy)
        edited.localPlaylists = [.init(collection:c1,tracks:[]), .init(collection:c2,tracks:[b])]
        edited.addTrack(a,toPlaylist:c1.key)
        require(edited.localPlaylists?[0].tracks == [a],"add to local playlist")
        edited.addTrack(a,toPlaylist:c1.key)
        require(edited.localPlaylists?[0].tracks == [a],"deduplicate local playlist")
        edited.addTrack(b,toPlaylist:c1.key)
        require(edited.localPlaylists?[0].tracks == [a,b],"preserve distinct platform keys")
        require(edited.localPlaylists?[1].tracks == [b],"other playlist unchanged")
        let snapshot = edited.localPlaylists
        edited.addTrack(a,toPlaylist:"not-found")
        require(edited.localPlaylists == snapshot,"missing playlist no-op")
        edited.localPlaylists = nil
        edited.addTrack(a,toPlaylist:c1.key)
        require(edited.localPlaylists == nil,"missing playlist storage no-op")
        backup.version = 99
        do { _ = try backup.validated(); fatalError("unknown version accepted") }
        catch MusicError.message { }
        require(clockText(123.1) == "2:03" && clockText(.nan) == "0:00","time format")
        print("PASS: 30 core checks (including playlist mutation regression)")
    }
}
