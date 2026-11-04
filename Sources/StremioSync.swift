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
            guard outbox.entries.count<=32,outbox.entries.allSatisfy({$0.event.valid && $0.episodes.count<=4096}),outbox.receipts.count<=128 else{throw StremioSyncError.format}
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
    func connect(email:String,password:String)async->Bool {
        guard !busy else{return false}
        busy=true;defer{busy=false}
        let token=generation,transition=UUID()
        do {
            let next=try await api.login(email:email.trimmingCharacters(in:.whitespacesAndNewlines),password:password)
            guard token==generation else{return false}
            try StremioAccountStore.save(next)
            worker?.cancel();worker=nil;generation=transition;account=next;connected=true;nextAttempt = .distantPast;failedAttempts=0;accountLabel=next.email ?? "Stremio"
            enabled=false;UserDefaults.standard.set(false,forKey:"cast.stremio.enabled")
            try loadOutbox();message="Stremio collegato. Attiva la sincronizzazione per condividere visti e punto di ripresa."
            return true
        }catch{if generation==token || generation==transition{message="Accesso non riuscito. Controlla email, password e connessione."};return false}
    }
    func setEnabled(_ value:Bool) {
        enabled=value && connected;UserDefaults.standard.set(enabled,forKey:"cast.stremio.enabled")
        if enabled{message="Sincronizzazione attiva.";flush()}
        else{generation=UUID();worker?.cancel();worker=nil;message="Sincronizzazione disattivata. I progressi sul dispositivo restano salvati."}
    }
    func disconnect() {
        do{try StremioAccountStore.remove()}
        catch{message="Non riesco a rimuovere l’accesso dal portachiavi. Riprova.";return}
        let oldFile=file
        generation=UUID();worker?.cancel();worker=nil;account=nil;connected=false;enabled=false;accountLabel="Stremio"
        UserDefaults.standard.set(false,forKey:"cast.stremio.enabled")
        outbox=StremioOutbox();blocked=[];lastObservation=[:];counts()
        if let oldFile{try? FileManager.default.removeItem(at:oldFile)}
        message="Stremio disconnesso. La libreria remota non è stata cancellata."
    }
    func observe(type:String,videoID:String,title:String,position:Double,duration:Double,completed:Bool=false,force:Bool=false,episodes:[String]=[]) {
        guard enabled,connected else{return}
        let now=Date(),key=type+"|"+videoID
        if force,!completed,let previous=lastObservation[key],now.timeIntervalSince(previous)<1{return}
        if !force,!completed,let previous=lastObservation[key],now.timeIntervalSince(previous)<60{return}
        let event=StremioProgressEvent(type:type,videoID:videoID,title:String(title.prefix(500)),position:position,duration:duration,observedAt:now,completed:completed)
        guard event.valid else{return}
        let previous=outbox
        do {
            try outbox.enqueue(event,episodes:episodes);try save();lastObservation[key]=now
            if lastObservation.count>64{lastObservation=[:];lastObservation[key]=now}
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
        }catch StremioSyncError.rateLimited(let delay){nextAttempt=Date().addingTimeInterval(Double(delay));return nil}
        catch{return nil}
    }
    func discardConflicts() {
        let previous=outbox
        outbox.discard(blocked)
        do{try save();blocked=[];counts();message="Mantengo i dati presenti su Stremio.";flush()}
        catch{outbox=previous;counts();message="Non riesco a salvare la scelta. Riprova."}
    }
    func flush() {
        guard Date()>=nextAttempt,enabled,connected,worker==nil,let account else{return}
        let token=generation
        worker=Task { [weak self] in
            guard let self else{return}
            let background=UIApplication.shared.beginBackgroundTask(withName:"Sync Stremio") {
                Task { @MainActor [weak self] in if self?.generation==token{self?.worker?.cancel()} }
            }
            defer{if background != .invalid{UIApplication.shared.endBackgroundTask(background)};if self.generation==token{self.worker=nil}}
            while !Task.isCancelled,self.generation==token,self.enabled,let entry=self.outbox.entries.first(where:{!self.blocked.contains($0.id)}) {
                guard let id=entry.event.itemID else{return}
                do {
                    let remote=try await self.api.item(id,account:account)
                    try Task.checkCancellation();guard self.generation==token,self.enabled else{return}
                    var episodes=entry.episodes
                    if entry.event.type=="series",entry.event.completed,episodes.isEmpty {
                        let found=try await BridgeClient.shared.episodes(videoID:entry.event.videoID)
                        try Task.checkCancellation();guard self.generation==token else{return}
                        episodes=SeriesNavigation.ordered(found,series:id,includeSpecials:true).map(\.id)
                    }
                    guard self.outbox.entries.contains(where:{$0.id==entry.id}) else{continue}
                    let item=try StremioLibraryMerge.applying(entry.event,to:remote,episodes:episodes,acceptedState:self.outbox.receipts[id])
                    try Task.checkCancellation();guard self.generation==token,self.enabled else{return}
                    try await self.api.put(item,account:account)
                    guard self.generation==token else{return}
                    let state=try JSONSerialization.data(withJSONObject:item["state"]!,options:.sortedKeys)
                    self.outbox.acknowledge(entry.id,itemID:id,state:state);try self.save()
                    self.failedAttempts=0;self.nextAttempt = .distantPast
                    self.message="Progressi sincronizzati con Stremio."
                }catch is CancellationError{return}
                catch StremioSyncError.conflict {
                    guard self.generation==token else{return}
                    self.blocked.insert(entry.id);self.counts();self.message="Stremio ha dati più recenti. Puoi mantenerli dalle impostazioni senza sovrascriverli."
                }catch StremioSyncError.catalog {
                    guard self.generation==token else{return}
                    self.blocked.insert(entry.id);self.counts();self.message="Non posso aggiornare i visti senza un elenco episodi coerente. I dati Stremio sono conservati."
                }catch StremioSyncError.rateLimited(let delay) {
                    guard self.generation==token else{return}
                    self.nextAttempt=Date().addingTimeInterval(Double(delay));self.message="Stremio richiede una pausa. La coda resta salvata e verrà riprovata più tardi.";return
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
