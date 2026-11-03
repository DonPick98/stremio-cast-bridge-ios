import Foundation
@main struct SeriesNavigationTests {
    static func main() throws {
        let data=Data(#"[{"id":"tt1:2:1","title":"Next season","season":2,"episode":1,"released":"2020-01-01T00:00:00.000Z"},{"id":"tt1:1:3","title":"After gap","season":1,"episode":3,"released":"2020-01-01T00:00:00Z"},{"id":"tt1:1:1","title":"Pilot","season":1,"episode":1},{"id":"tt1:0:1","title":"Special","season":0,"episode":1},{"id":"tt2:1:2","title":"Wrong show","season":1,"episode":2},{"id":"tt1:1:3","title":"Duplicate","season":1,"episode":3},{"id":"tt1:1:4","title":"Mismatch","season":9,"episode":9}]"#.utf8)
        let rows=try JSONDecoder().decode([SeriesEpisode].self,from:data)
        let ordered=SeriesNavigation.ordered(rows,series:"tt1",includeSpecials:false)
        precondition(ordered.map{$0.id} == ["tt1:1:1","tt1:1:3","tt1:2:1"])
        precondition(SeriesNavigation.adjacent(ordered,current:"tt1:1:1",direction:1)?.id == "tt1:1:3","Do not invent the missing episode")
        precondition(SeriesNavigation.adjacent(ordered,current:"tt1:1:3",direction:1)?.id == "tt1:2:1")
        precondition(SeriesNavigation.adjacent(ordered,current:"tt1:1:1",direction:-1)==nil)
        precondition(SeriesNavigation.adjacent(ordered,current:"tt1:2:1",direction:1)==nil)
        precondition(SeriesNavigation.adjacent(ordered,current:"unknown",direction:1)==nil)
        precondition(SeriesNavigation.adjacent(ordered,current:"tt1:1:1",direction:0)==nil)
        precondition(SeriesNavigation.ordered(rows,series:"tt1",includeSpecials:true).first?.season==0)
        precondition(!ordered[0].aired(),"Unknown release date must not trigger autoplay")
        precondition(!ordered[1].aired(at:Date(timeIntervalSince1970:0)))
        precondition(ordered[1].aired(at:Date(timeIntervalSince1970:2_000_000_000)))
        for invalid in ["tt1","tt1:-1:2","tt1:1:2:3","https://private.example/token","tt1:one:2"] {precondition(SeriesNavigation.seriesID(invalid)==nil)}
        precondition(SeriesNavigation.stremioURL(videoID:"tt1:2:1",web:false)?.absoluteString == "stremio:///detail/series/tt1/tt1:2:1")
        precondition(SeriesNavigation.stremioURL(videoID:"tt1:2:1",web:true)?.host == "web.stremio.com")
        print("Series navigation: catalogue ordering, gaps, seasons, boundaries, future/unknown release and safe links passed")
    }
}
