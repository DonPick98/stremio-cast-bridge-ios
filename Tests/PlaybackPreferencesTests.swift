import Foundation

@main struct PlaybackPreferencesTests {
    static func main() {
        let suite = "cast.preferences." + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        defaults.set("preserve",forKey:"cast.personal.configuration")
        defaults.set(321.0,forKey:"cast.position.example")
        for key in PlaybackPreferences.appSettingKeys { defaults.set("changed",forKey:key) }
        PlaybackPreferences.resetAppSettings(defaults:defaults)
        precondition(PlaybackPreferences.appSettingKeys.allSatisfy { defaults.object(forKey:$0)==nil })
        precondition(defaults.string(forKey:"cast.personal.configuration")=="preserve")
        precondition(defaults.double(forKey:"cast.position.example")==321)
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
        defaults.set("auto",forKey:"cast.preferred.audio")
        defaults.set("auto",forKey:"cast.preferred.subtitle")
        precondition(PlaybackPreferences.audio(tracks,fallback:"b",defaults:defaults)=="b")
        precondition(PlaybackPreferences.subtitle(tracks,external:true,handoff:"eng",defaults:defaults)=="a")
        precondition(PlaybackPreferences.subtitleLanguage(handoff:"ita",defaults:defaults)=="it")
        precondition(PlaybackPreferences.subtitleLanguage(handoff:"off",defaults:defaults)=="en")
        precondition(!PlaybackPreferences.subtitlesRequested(handoff:"off",defaults:defaults))
        precondition(PlaybackPreferences.subtitlesRequested(handoff:"eng",defaults:defaults))
        defaults.set("none",forKey:"cast.preferred.subtitle")
        precondition(!PlaybackPreferences.subtitlesRequested(handoff:"eng",defaults:defaults))
        defaults.set("it",forKey:"cast.preferred.subtitle")
        precondition(PlaybackPreferences.subtitlesRequested(handoff:"off",defaults:defaults))
        defaults.set("fr",forKey:"cast.preferred.subtitle")
        precondition(PlaybackPreferences.subtitle([],external:true,handoff:"eng",externalLanguage:"fra",defaults:defaults)=="external")
        precondition(PlaybackPreferences.subtitle([],external:true,handoff:"eng",externalLanguage:"it",defaults:defaults)=="none")
        defaults.set("none",forKey:"cast.preferred.subtitle")
        precondition(PlaybackPreferences.subtitle([],external:true,handoff:"eng",externalLanguage:"fr",defaults:defaults)=="none")
        precondition(MediaDisplayTitle.clean("[Provider] Example.Movie.2025.1080p.WEB-DL.AC3.mkv") == "Example Movie 2025")
        precondition(MediaDisplayTitle.clean("Example.Series.S02E03.1080p.mkv") == "Example Series · S2 E3")
        precondition(MediaDisplayTitle.clean("...") == "Video da Stremio")
        print("Playback preferences passed: language aliases, new track IDs, embedded captions first, external fallback, persistent off, clean titles")
    }
}


