import Foundation

@main struct PlaybackPreferencesTests {
    static func main() {
        let suite = "cast.preferences." + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let tracks = [RDTrack(key:"a",language:"eng",label:"English",codec:"aac"),RDTrack(key:"b",language:"ita",label:"Italiano",codec:"ac3")]
        precondition(PlaybackPreferences.audio(tracks,fallback:"a",defaults:defaults) == "a")
        PlaybackPreferences.remember(audio:tracks[1],subtitle:"it",defaults:defaults)
        let changed = [RDTrack(key:"new",language:"it-IT",label:"Italiano",codec:"eac3")]
        precondition(PlaybackPreferences.audio(changed,fallback:"other",defaults:defaults) == "new")
        precondition(PlaybackPreferences.subtitle(changed,external:true,handoff:"ita",defaults:defaults) == "new")
        precondition(PlaybackPreferences.subtitle([],external:true,handoff:"ita",defaults:defaults) == "external")
        precondition(PlaybackPreferences.subtitle(tracks,external:true,handoff:"eng",defaults:defaults) == "b")
        precondition(PlaybackPreferences.subtitle([],external:true,handoff:"eng",defaults:defaults) == "none")
        precondition(PlaybackPreferences.subtitle(changed,external:false,handoff:"ita",defaults:defaults) == "new")
        PlaybackPreferences.remember(audio:nil,subtitle:"none",defaults:defaults)
        precondition(PlaybackPreferences.subtitle(changed,external:true,handoff:"ita",defaults:defaults) == "none")
        precondition(MediaDisplayTitle.clean("[Provider] Example.Movie.2025.1080p.WEB-DL.AC3.mkv") == "Example Movie 2025")
        precondition(MediaDisplayTitle.clean("Example.Series.S02E03.1080p.mkv") == "Example Series · S2 E3")
        precondition(MediaDisplayTitle.clean("...") == "Video da Stremio")
        print("Playback preferences passed: language aliases, new track IDs, embedded captions first, external fallback, persistent off, clean titles")
    }
}

