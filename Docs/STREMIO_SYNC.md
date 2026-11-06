# Sincronizzazione libreria Stremio — build56

Protocollo reimplementato in Swift, senza codice Rust/React copiato e senza nuovo servizio a pagamento. Fonti primarie verificate il2026-11-06:
- Stremio/stremio-core3417c2e7ed45cdbfd86b3226f69814c2dc4947ad: src/models/meta_details.rs (external_player_progress_update), src/models/player.rs (Seek/TimeChanged), src/constants.rs (WATCHED_THRESHOLD_COEF=0.7), tipi API/libraryItem e watched-bitfield.
- Stremio/stremio-web55d8b33487e95ab8d67fda3030c7b86dd68f2d99: src/routes/MetaDetails/useExternalPlayerCallback.ts legge position in secondi, converte in millisecondi e invia ExternalPlayerProgressChanged. Il ritorno non è un canale universale per ogni player/piattaforma.

## Comportamento56

CastBridge dispone già del clock confermato della propria sessione TV: aggiorna direttamente la libreria dell’account, senza riaprire Stremio automaticamente. IDIMDb movie/series canonici, millisecondi,video_id e bitfield sono preservati. Il player esterno di Stremio può usare posizione/durata; qui si adotta il criterio più conservativo del player interno: tempo realmente avanzato>70% della durata, oppure fine naturale confermata vicina alla fine. La sola apertura, un target seek o il tempo in pausa non marcano visto. Alla soglia l’offset continua a rappresentare il punto attuale; alla fine naturale diventa0.

StremioWatchTracker usa movimento del clockTV e uptime, gestisce status ripetuti senza falsa accelerazione, non accredita grandi salti/rewind e viene sospeso esplicitamente prima di seek/preparazione. Crediti cumulativi per sessione: solo la differenza non ancora riconosciuta aumenta timeWatched. Le ricevute persistenti evitano doppio conteggio dopo retry e coalescenza. Campioni ogni tick; invii al massimo ogni15s se posizione/credito cambiano, più eventi forzati su pausa/background/stop. Nessun traffico ripetuto per progressi fermi, salvo retry della coda.

## Conferma e recupero

Prima del PUT, il journal protetto salva evento, stato desiderato e baseline. Gli eventi in-flight non vengono rimossi dalla coalescenza. Dopo success:true si rilegge lo stesso item: solo uno stato coerente consente ACK e messaggio «salvati e verificati». Se risposta/readback si perdono o il processo termina, il journal riconosce lo stato già applicato senza un secondo credito. Se il server conserva la baseline, il retry usa metadata/appartenenza alla libreria freschi; se è cambiato lo stato di riproduzione, blocca per conflitto. Campi sconosciuti, visti esistenti e preferiti vengono conservati. Le voci nuove rimangono temporanee/removed, senza aggiunta automatica ai preferiti.

Outbox32eventi, ricevute128, account isolati tramiteSHA256, file≤2MiB con protezione UntilFirstUserAuthentication. Vecchie code senza nuovi campi vengono decodificate. PUT e GET limitati nel tempo/dimensione, nessun redirect del token. Retry-After429 rispettato; retrymanuale può anticipare solo il backoff locale. Contatore pending e ultima verifica visibili. La rete/account reale non sono usati nei test.

## Account e consenso

Password mai salvata, token solo nel KeychainAfterFirstUnlockThisDeviceOnly. Il pulsante «Collega e sincronizza» rende esplicita l’attivazione dopo login; la sincronizzazione resta disattivabile. L’upgrade non attiva un account che era disabilitato: nel player compare «Attiva sincronizzazione Stremio» per gli account già collegati. Nessun import daaltre app/SSO/QR. Disconnessione elimina token+coda locale, non la libreria remota. Disabilitazione/cambio account invalidano task/callback; un PUT già accettato non è revocabile.

## Ripresa e limiti

Resume remoto soltanto se stesso video_id, _mtime più recente e nessun evento locale pendente. Timestamp storici mancanti non sono considerati vecchi automaticamente. La lettura avviene alla scelta della sorgente; Stremio può conservare una UI locale finché non ricarica la libreria. Non c’è CAS/PUT condizionale nel contratto esaminato: la corsa fra altri dispositivi e GET/PUT rimane best-effort. Non promettere atomicità fra dispositivi o esecuzione iOS illimitata. FT-004 resta IMPLEMENTATO_DA_VERIFICARE finché manca prova su account/telefono/Chromecast reali, inclusi fine puntata, due episodi offline, risposta persa, conflitto e ripresa. CB-030 attende prova di scorrimento sul dispositivo; motore54 invariato.

## Test

Tests/StremioLibraryTests.swift verifica bitfield upstream, legacy queue, unità, campi sconosciuti, conflitti, soglia70%, pausa/statusripetuti/seek/sospensione, journal dopo riavvio/coalescenza, crediti una sola volta e APIReadBack verificato/rifiutato. Le risposte sono URLProtocol sintetiche. Build iPhone/SDK necessaria per UI, Keychain e worker. Nessuna credenziale o cronologia reale richiesta o inviata.
