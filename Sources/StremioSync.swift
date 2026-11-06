#if canImport(UIKit)
import Foundation
import SwiftUI
import UIKit
import Security
import CryptoKit

private enum StremioAccountStore {
    private static var query:[String:Any]{[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"app.castbridge.stremio",kSecAttrAccount as String:"primary"]}
    static func load()throws->StremioAccount? {
        var q=query;q[kSecReturnData as String]=true;q[kSecMatchLimit as String]=kSecMatchLimitOne
        var value:CFTypeRef?;let status=SecItemCopyMatching(q as CFDictionary,&value)
        if status==errSecItemNotFound{return nil}
        guard status==errSecSuccess,let data=value as? Data else{throw StremioSyncError.storage}
        return try JSONDecoder().decode(StremioAccount.self,from:data)
    }
    static func save(_ account:StremioAccount)throws {
        let data=try JSONEncoder().encode(account)
        let values:[String:Any]=[kSecValueData as String:data,kSecAttrAccessible as String:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let updated=SecItemUpdate(query as CFDictionary,values as CFDictionary)
        if updated==errSecSuccess{return}
        guard updated==errSecItemNotFound else{throw StremioSyncError.storage}
        var q=query;values.forEach{q[$0.key]=$0.value}
        guard SecItemAdd(q as CFDictionary,nil)==errSecSuccess else{throw StremioSyncError.storage}
    }
    static func remove()throws {
        let status=SecItemDelete(query as CFDictionary)
        guard status==errSecSuccess || status==errSecItemNotFound else{throw StremioSyncError.storage}
    }
}
@MainActor final class StremioSync:ObservableObject {
    static let shared=StremioSync()
    @Published private(set) var connected=false
    @Published private(set) var accountLabel="Stremio"
    @Published private(set) var busy=false
    @Published private(set) var pending=0
    @Published private(set) var conflicts=0
    @Published private(set) var lastSynced:Date?
    @Published private(set) var message="Collega Stremio per sincronizzare visti e punto di ripresa."
    @Published private(set) var enabled=UserDefaults.standard.bool(forKey:"cast.stremio.enabled")
    private var account:StremioAccount?
    private var outbox=StremioOutbox()
    private var blocked=Set<UUID>()
    private var worker:Task<Void,Never>?
    private var generation=UUID()
    private let api=StremioLibraryAPI()
    private var lastObservation:[String:Date]=[:]
    private var nextAttempt=Date.distantPast
    private var failedAttempts=0
    private var serverRetryRequired=false
    private var watchTrackers:[String:StremioWatchTracker]=[:]
    private var lastQueued:[String:(position:Double,watched:Double)]=[:]
    private init() {
        do {
            account=try StremioAccountStore.load();connected=account != nil
            if connected{accountLabel=account?.email ?? "Stremio";try loadOutbox();message=enabled ? "Stremio collegato.":"Stremio collegato. Attiva la sincronizzazione quando vuoi."}
        }catch{enabled=false;message="Non riesco a leggere i dati Stremio su questo dispositivo. Riprova l’accesso."}
    }
    private var file:URL? {
        guard let account else{return nil}
        let hash=SHA256.hash(data:Data(account.id.utf8)).map{String(format:"%02x",$0)}.joined()
        return FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first?.appendingPathComponent("CastBridge/stremio-"+hash+".json")
    }
    private func loadOutbox()throws {
        outbox=StremioOutbox();blocked=[]
        if let file,FileManager.default.fileExists(atPath:file.path) {
            guard let size=try file.resourceValues(forKeys:[.fileSizeKey]).fileSize,size<=2_097_152 else{throw StremioSyncError.limit}
            outbox=try JSONDecoder().decode(StremioOutbox.self,from:Data(contentsOf:file))
            guard outbox.entries.count<=32,outbox.entries.allSatisfy({$0.event.valid && $0.episodes.count<=4096}),outbox.receipts.count<=128,
                  (outbox.writes?.count ?? 0)<=32,(outbox.watchReceipts?.count ?? 0)<=128,
                  outbox.writes?.values.allSatisfy({write in write.item.count<=262_144 && write.state.count<=65_536 && (write.baseline?.count ?? 0)<=65_536 && outbox.entries.contains(where:{$0.id==write.entryID && $0.event.itemID==write.itemID})}) ?? true,
                  outbox.watchReceipts?.values.allSatisfy({$0.watched.isFinite && $0.watched>=0 && $0.watched<=604_800}) ?? true else{throw StremioSyncError.format}
        }
        counts()
    }
    private func save()throws {
        guard let file else{throw StremioSyncError.storage}
        let data=try JSONEncoder().encode(outbox);guard data.count<=2_097_152 else{throw StremioSyncError.limit}
        try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
        try data.write(to:file,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication]);counts()
    }
    private func counts(){blocked.formIntersection(Set(outbox.entries.map(\.id)));pending=outbox.entries.count;conflicts=blocked.count}
    func connect(email:String,password:String,synchronize:Bool=true)async->Bool {
        guard !busy else{return false}
        busy=true;defer{busy=false}
        let token=generation,transition=UUID()
        do {
            let next=try await api.login(email:email.trimmingCharacters(in:.whitespacesAndNewlines),password:password)
            guard token==generation else{return false}
            try StremioAccountStore.save(next)
            worker?.cancel();worker=nil;generation=transition;account=next;connected=true;nextAttempt = .distantPast;failedAttempts=0;accountLabel=next.email ?? "Stremio"
            enabled=synchronize;UserDefaults.standard.set(enabled,forKey:"cast.stremio.enabled")
            watchTrackers=[:];lastObservation=[:];lastQueued=[:];lastSynced=nil;serverRetryRequired=false
            try loadOutbox();message=enabled ? "Stremio collegato. Sincronizzazione attiva.":"Stremio collegato. Sincronizzazione disattivata."
            if enabled{flush()}
            return true
        }catch{if generation==token || generation==transition{message="Accesso non riuscito. Controlla email, password e connessione."};return false}
    }
    func setEnabled(_ value:Bool) {
        enabled=value && connected;UserDefaults.standard.set(enabled,forKey:"cast.stremio.enabled")
        if enabled{message="Sincronizzazione attiva.";flush()}
        else{generation=UUID();worker?.cancel();worker=nil;watchTrackers=[:];lastObservation=[:];lastQueued=[:];message="Sincronizzazione disattivata. I progressi sul dispositivo restano salvati."}
    }
    func disconnect() {
        do{try StremioAccountStore.remove()}
        catch{message="Non riesco a rimuovere l’accesso dal portachiavi. Riprova.";return}
        let oldFile=file
        generation=UUID();worker?.cancel();worker=nil;account=nil;connected=false;enabled=false;accountLabel="Stremio"
        UserDefaults.standard.set(false,forKey:"cast.stremio.enabled")
        outbox=StremioOutbox();blocked=[];lastObservation=[:];watchTrackers=[:];lastQueued=[:];lastSynced=nil;serverRetryRequired=false;counts()
        if let oldFile{try? FileManager.default.removeItem(at:oldFile)}
        message="Stremio disconnesso. La libreria remota non è stata cancellata."
    }
    func suspendWatchSampling(type:String,videoID:String){watchTrackers[type+"|"+videoID]?.suspend()}
    func observe(type:String,videoID:String,title:String,position:Double,duration:Double,completed:Bool=false,force:Bool=false,episodes:[String]=[],playing:Bool=false) {
        guard enabled,connected else{return}
        let now=Date(),key=type+"|"+videoID
        var tracker=watchTrackers[key] ?? StremioWatchTracker()
        let watched=tracker.observe(position:position,playing:playing,time:ProcessInfo.processInfo.systemUptime)
        if watchTrackers.count>=64,watchTrackers[key]==nil{watchTrackers.removeAll()}
        watchTrackers[key]=tracker
        if !outbox.entries.isEmpty{flush()}
        if !force,!completed,let queued=lastQueued[key],abs(queued.position-position)<0.25,abs(queued.watched-watched)<0.25{return}
        if force,!completed,let previous=lastObservation[key],now.timeIntervalSince(previous)<1{return}
        if !force,!completed,let previous=lastObservation[key],now.timeIntervalSince(previous)<15{return}
        let event=StremioProgressEvent(type:type,videoID:videoID,title:String(title.prefix(500)),position:position,duration:duration,observedAt:now,completed:completed,watched:watched,sessionID:tracker.sessionID)
        guard event.valid else{return}
        let previous=outbox
        do {
            try outbox.enqueue(event,episodes:episodes);try save();lastObservation[key]=now;lastQueued[key]=(position,watched)
            if lastObservation.count>64{lastObservation=[:];lastQueued=[:];lastObservation[key]=now;lastQueued[key]=(position,watched)}
            flush()
        }catch{outbox=previous;counts();message="Non riesco a salvare la coda Stremio. I progressi locali restano disponibili."}
    }
    func resume(type:String,videoID:String,localUpdated:Date)async->Double? {
        guard Date()>=nextAttempt,enabled,UserDefaults.standard.object(forKey:"cast.stremio.resume") as? Bool ?? true,let account else{return nil}
        let token=generation
        let identity=StremioProgressEvent(type:type,videoID:videoID,title:"Resume",position:0,duration:1,observedAt:Date(),completed:false)
        guard let id=identity.itemID else{return nil}
        // A queued local change has not reached Stremio yet: don't replace it
        // with the older server pointer while offline/retrying.
        guard !outbox.entries.contains(where:{$0.event.itemID==id}) else{return nil}
        do {
            guard let item=try await api.item(id,account:account),token==generation,enabled else{return nil}
            return StremioLibraryMerge.resume(item,videoID:videoID,localUpdated:localUpdated)
        }catch StremioSyncError.rateLimited(let delay){serverRetryRequired=true;nextAttempt=Date().addingTimeInterval(Double(delay));return nil}
        catch{return nil}
    }
    func discardConflicts() {
        let previous=outbox
        outbox.discard(blocked)
        do{try save();blocked=[];counts();message="Mantengo i dati presenti su Stremio.";flush()}
        catch{outbox=previous;counts();message="Non riesco a salvare la scelta. Riprova."}
    }
    private func acknowledge(_ entry:StremioOutbox.Entry,remote:[String:Any])throws {
        guard let id=entry.event.itemID,let state=try StremioLibraryMerge.stateData(remote) else{throw StremioSyncError.format}
        let previous=outbox
        outbox.acknowledge(entry.id,itemID:id,state:state)
        do{try save()}catch{outbox=previous;counts();throw error}
        failedAttempts=0;nextAttempt = .distantPast;serverRetryRequired=false
        lastSynced=Date();message="Progressi salvati e verificati su Stremio."
    }
    func flush(force:Bool=false) {
        if Date()>=nextAttempt{serverRetryRequired=false}
        if force,!serverRetryRequired{nextAttempt = .distantPast}
        guard Date()>=nextAttempt,enabled,connected,worker==nil,let account else{return}
        let token=generation
        worker=Task { [weak self] in
            guard let self else{return}
            let background=CastBackgroundLease(name:"Sync Stremio") {
                Task { @MainActor [weak self] in if self?.generation==token{self?.worker?.cancel()} }
            }
            defer{background.end();if self.generation==token{self.worker=nil}}
            while !Task.isCancelled,self.generation==token,self.enabled,let entry=self.outbox.entries.first(where:{!self.blocked.contains($0.id)}) {
                guard let id=entry.event.itemID else{return}
                do {
                    let remote=try await self.api.item(id,account:account)
                    try Task.checkCancellation();guard self.generation==token,self.enabled else{return}
                    if let remote,remote["type"] as? String != entry.event.type{throw StremioSyncError.format}
                    // Recover an accepted PUT whose response/readback was lost,
                    // including after process termination. Never credit twice.
                    if let write=self.outbox.intent(for:entry),StremioLibraryMerge.matches(write.state,remote:remote),let remote {
                        try self.acknowledge(entry,remote:remote);continue
                    }
                    let item:[String:Any]
                    if let write=self.outbox.intent(for:entry) {
                        guard StremioLibraryMerge.matches(write.baseline,remote:remote) else{throw StremioSyncError.conflict}
                        guard let restored=try JSONSerialization.jsonObject(with:write.item) as? [String:Any],restored["_id"] as? String==id,
                              let intendedState=restored["state"] as? [String:Any] else{throw StremioSyncError.format}
                        // Preserve metadata/library membership changed since the
                        // first attempt when the playback baseline is unchanged.
                        var retry=remote ?? restored
                        var state=remote?["state"] as? [String:Any] ?? [:]
                        intendedState.forEach{state[$0.key]=$0.value}
                        retry["state"]=state;retry["_mtime"]=StremioLibraryMerge.stamp(Date())
                        item=retry
                    } else {
                    var episodes=entry.episodes
                    if entry.event.type=="series",entry.event.completed || (entry.event.watched ?? 0)>0,episodes.isEmpty {
                        let found=try await BridgeClient.shared.episodes(videoID:entry.event.videoID)
                        try Task.checkCancellation();guard self.generation==token else{return}
                        episodes=SeriesNavigation.ordered(found,series:id,includeSpecials:true).map(\.id)
                    }
                    guard self.outbox.entries.contains(where:{$0.id==entry.id}) else{continue}
                    item=try StremioLibraryMerge.applying(entry.event,to:remote,episodes:episodes,acceptedState:self.outbox.receipts[id],acceptedWatch:self.outbox.watchedReceipt(for:entry.event))
                    let previous=self.outbox
                    do{try self.outbox.prepare(entry,item:item,baseline:remote);try self.save()}
                    catch{self.outbox=previous;self.counts();throw error}
                    }
                    try Task.checkCancellation();guard self.generation==token,self.enabled else{return}
                    let confirmed=try await self.api.putAndReadBack(item,account:account)
                    try Task.checkCancellation();guard self.generation==token,self.enabled else{return}
                    try self.acknowledge(entry,remote:confirmed)
                }catch is CancellationError{return}
                catch StremioSyncError.conflict {
                    guard self.generation==token else{return}
                    self.blocked.insert(entry.id);self.counts();self.message="Stremio ha dati più recenti. Puoi mantenerli dalle impostazioni senza sovrascriverli."
                }catch StremioSyncError.catalog {
                    guard self.generation==token else{return}
                    self.blocked.insert(entry.id);self.counts();self.message="Non posso aggiornare i visti senza un elenco episodi coerente. I dati Stremio sono conservati."
                }catch StremioSyncError.rateLimited(let delay) {
                    guard self.generation==token else{return}
                    self.serverRetryRequired=true;self.nextAttempt=Date().addingTimeInterval(Double(delay));self.message="Stremio richiede una pausa. La coda resta salvata e verrà riprovata più tardi.";return
                }catch StremioSyncError.authentication {
                    guard self.generation==token else{return}
                    self.nextAttempt=Date().addingTimeInterval(300)
                    self.message="L’accesso Stremio è scaduto. Disattiva la sincronizzazione e ripeti l’accesso.";return
                }catch {
                    guard self.generation==token else{return}
                    self.failedAttempts=min(5,self.failedAttempts+1);self.nextAttempt=Date().addingTimeInterval(min(900,60*pow(2,Double(self.failedAttempts-1))))
                    self.message="Sincronizzazione in attesa: riproverò alla prossima apertura o durante la riproduzione.";return
                }
            }
        }
    }
}
#endif

