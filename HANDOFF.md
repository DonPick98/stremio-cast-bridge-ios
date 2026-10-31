# Cast Bridge: stato e passaggio di consegne

Ultimo aggiornamento: 31 ottobre 2026. Repository pubblico: DonPick98/stremio-cast-bridge-ios.

## Obiettivo dell'utente

iPhone con SideStore, Chromecast classico esistente, Stremio con Torrentio/Comet e account Real-Debrid personale. Esperienza semplice: scegliere un file da Stremio, avviare sulla TV, selezionare audio e sottotitoli inglesi, controllare anche dalla schermata bloccata. Preferenza 1080p, nessuna riduzione silenziosa. Il telefono puo' essere bloccato durante la visione e non deve servire un PC acceso. Ogni persona (inclusa un'amica con altro account) usa i propri manifest. Nessun token personale, link RD, chiave, certificato o profilo nel repo. GitHub Actions usa runner standard gratuito per repo pubblico.

## Validato sul dispositivo dall'utente

- IPA precedente compilata da GitHub e installata con SideStore.
- Estensione Live Activity minimale visibile sulla schermata bloccata.
- Video RD diretto MKV H264 High, 1920x1080 23.98 fps, AAC stereo: circa 2 minuti senza buffering osservato dopo l'avvio, video/audio confermati dall'utente. Fonte Frieren episodio 03 piu' recente nella cronologia RD; non e' stato confrontato l'ID con tutte le precedenti sorgenti HLS.
- Video diretto + sottotitolo esterno WebVTT sintetico, servito da PC per la sola prova: un minuto continuo con scritte confermate dall'utente. Non e' una soluzione di hosting per l'app finale.
- Flusso HLS multitraccia sintetico: due audio e due sottotitoli selezionati con successo via Cast.

## Problema individuato

Il flusso convertito RD /streaming/transcode ha restituito segmenti TS incompleti con HTTP 200 e Content-Length della risposta troncata. La seconda richiesta allo stesso URL del segmento nella medesima sessione restituisce il segmento completo. Esempio: segmento 7 da 1.048.576 a 4.077.532 byte; segmento 8 da 524.288 a 4.049.144 byte. Alcuni recuperi impiegano 8-10 s per 5 s di video. Blocco intorno a 54 s osservato anche monitorando soltanto Cast. Causa interna RD e altre concause non determinate. Evitare HLS come percorso predefinito per file gia' compatibili.

## Implementazione integrata in corso

Leggere il codice del commit corrente per lo stato effettivo. Modifiche previste: URL diretto validato e metadati video; conversione esplicita per codec incompatibili o audio alternativo; selezione 1080p fra le qualita' convertite senza simulare un ridimensionamento sul file diretto; VTT esterno inglese; stato reale e timeout; conservazione ultimo minutaggio; Activity con titolo, avanzamento e AppIntents.

## Limiti da risolvere/verificare prima di dichiarare tutto completato

1. Audio multitraccia: un vero file diretto con piu' audio non e' stato validato. Google documenta selezione via API delle tracce testo nel Default Media Receiver; audio/video tramite API richiedono Custom Receiver. Non presentare selezione audio nativa come funzionante senza test. Compatibilita' RD alternativa puo' ereditare buffering.
2. Sottotitoli incorporati: non esiste ancora un percorso completo di estrazione e hosting indipendente da PC/telefono. Il backend Sites corrente fornisce fallback OpenSubtitles tramite URL VTT cifrato e limitato nel tempo. Estrarre un breve campione ASS con FFmpeg e' riuscito, ma non dimostra estrazione dell'intero episodio. Nel progetto locale del bridge esiste un parser Matroska indicizzato sperimentale (mkv-subtitles.mjs), non ancora validato sui file reali ne' distribuito come servizio di estrazione.
3. Live Activity: prova di visualizzazione riuscita; comandi in background, riconnessione e autenticazione su iPhone da verificare. Non usare audio silenzioso per aggirare sospensione. Non promettere avanzamento sempre esatto quando l'app e' sospesa.
4. Collaudo app integrata: avvio 1080p diretto, sottotitolo inglese reale, cambio traccia/modalita' con conservazione posizione, seek indietro/avanti, pause, perdita rete, timeout, riapertura app, telefono bloccato, account diverso. Quota e tempi esterni non devono diventare cicli di tentativi infiniti.

## Compilazione e ripresa

La workflow .github/workflows/build-ios.yml usa macos-26, CocoaPods Google Cast 4.8.6, build seriale, SWIFT_ENABLE_EXPLICIT_MODULES=NO, firma disattivata. Il primo runner macos-15 non aveva le API richieste dal framework. Durante la prova estensione si sono verificati crash Xcode che nascondevano errori di codifica: mantenere UTF-8, usare diagnostica seriale.

L'artefatto CastRemote-unsigned contiene CastRemote-unsigned.ipa. Deve includere PlugIns/CastLiveActivity.appex. SideStore lo firma sul dispositivo; niente credenziali Apple su GitHub. Prima di installare una nuova build conservare quella funzionante.

Al prossimo account OpenAI: clonare questo repo, leggere questo file e README, poi controllare l'ultima Actions e l'eventuale sezione di aggiornamento sotto. Non richiedere chiavi in chat. Non usare il vecchio repository fornito originariamente dall'utente.

## Checkpoint implementazione 0.2

Percorso diretto, modalita' compatibilita', stato/timeout, posizione persistita e AppIntents implementati nei cinque file Swift. In attesa di compilazione e collaudo. Estrazione/hosting sottotitoli incorporati ancora aperti; fallback esterno disponibile. Il codice e' una versione da collaudare, non dichiarata completa su tutti i formati.

## Checkpoint 0.3 - ripresa del 31 ottobre

La build 0.2 di main ec1ba022 ha concluso con successo (Actions 41213783243). La versione 0.3 aggiunge:

- Associazione dello stato Cast al contenuto caricato, invece di attendere obbligatoriamente un nuovo mediaSessionID: alcuni receiver possono riusarlo.
- Salvataggio del minutaggio immediatamente prima di ricaricare/cambiare sorgente e quando l'app passa in background; ripristino della chiave di posizione dopo riavvio del processo. Nessun URL persistito: solo hash e chiave hash della posizione.
- Traccia VTT esterna associata anche se disattivata: attivazione/disattivazione via setActiveTrackIDs senza ricaricare il video. Audio alternativo e sottotitoli incorporati continuano a richiedere conversione esplicita.
- Comandi dalla Live Activity consentiti solo per il contenuto della sessione dell'app; recupero dell'attivita' esistente al riavvio.
- Pulsante di avvio disabilitato durante LOAD, codice Cast negli errori di caricamento e segnalazione dopo 45 secondi di buffering continuo. Nessuna riduzione automatica della qualita'.
- Test Swift eseguibili in Actions con URLProtocol e dati sintetici: file diretto 1080p, selezione tracce, nessun downgrade implicito, conversione indisponibile e rifiuto di URL estranei.

### Blocco esterno accertato

Il progetto Sites esistente appgprj_6ae4994e5e088191a83a4d06571ea4e9 restituisce NOT_FOUND nell'account/workspace collegato alla nuova chat; anche la lista completa dei Sites non lo include. L'URL pubblico e' quello corretto, ma non concede accesso di modifica. Il backend non e' stato modificato o pubblicato da questa chat. Occorre collegare il proprietario/workspace del Site o renderlo modificabile dal nuovo account tramite i normali controlli Sites.

### Lavoro residuo reale (obiettivo completo non ancora raggiunto)

1. Implementare e validare estrazione completa dei sottotitoli incorporati testuali e hosting temporaneo indipendente da PC/iPhone. Il parser Matroska sperimentale nel precedente checkout non e' una funzione dell'app 0.3. Non inviare al server link RD legati all'IP presumendo che siano scaricabili da li': l'estrazione sul telefono prima del Cast e l'upload del solo VTT sono una possibilita' da verificare. Stabilire autenticazione, limiti, scadenza e CORS nel servizio prima dell'integrazione. PGS e fedelta' degli effetti ASS non sono coperti.
2. Per il cambio audio senza la conversione RD resta necessario validare un percorso Custom Receiver/remux compatibile. Il Default Media Receiver offre la selezione delle tracce testo, non una soluzione universale per gli audio incorporati. Il selettore audio attuale usa ancora la modalita' compatibilita', con i rischi HLS gia' documentati.
3. Sul dispositivo: verificare avvio diretto 1080p, sottotitolo reale attivato e disattivato senza salto/ripartenza, cambio in compatibilita' al minuto corrente, riconnessione, pausa e +/-30 secondi dalla Live Activity a schermo bloccato. La compilazione e i test del resolver non verificano questi comportamenti.

Non dichiarare il prodotto completo finche' questi punti non sono risolti o l'utente accetta esplicitamente i limiti.

## Checkpoint 0.4 - estrazione sul telefono

Implementati Sources/MkvSubtitles.swift, CastRemote/SubtitleHosting.swift e integrazione nella UI. L'estrattore usa Range HTTP validati e un indice Matroska con CueRelativePosition e BlockDuration; limiti: 1800 cue, 32 MB di letture, 6000 richieste, 180 secondi. Legge UTF8 e ASS/SSA semplificato; non scarica o ricodifica il film. Completa solo le cue presenti: la completezza rispetto a tutti i sottotitoli del file non e' dimostrata dall'indice. Rifiuta tracce compresse/cifrate, lacing, indici assenti e durate assenti.

Da Audio e sottotitoli > Estrai sottotitoli dal file, prepara la lingua EN o IT secondo l'handoff. Esporta il VTT con ShareLink. Se l'utente ha configurato un servizio sottotitoli, invia solo il VTT tramite HTTPS con chiave nel portachiavi, valida l'URL restituito e lo associa come traccia Cast 2. Non spedisce il link RD. I redirect dell'upload sono bloccati. Il POST del testo al servizio avviene premendo Estrai con il servizio configurato.

SubtitleService contiene Worker con D1, API autenticata di upload, URL casuale 256 bit, scadenza 24 ore, limite 100 file da 1 MB e test Node. Il componente non e' pubblicato e richiede l'account del provider per la distribuzione. Non e' una modifica del Site originale. Il testo e' memorizzato nel database del servizio e puo' essere letto da chi possiede l'URL temporaneo; non descriverlo come cifrato end-to-end.

Audio: aggiunto un controllo che impedisce al percorso diretto di ignorare una selezione audio alternativa. Il Default Media Receiver supporta le tracce testo via API, mentre per audio/video Google richiede Custom Receiver (https://developers.google.com/cast/docs/ios_sender/media_tracks). Anche un Custom Receiver deve ricevere un contenitore/flusso con tracce selezionabili: registrare un ID da solo non rende gli MKV multiaudio compatibili. Cambio audio senza conversione e remux autonomo non sono implementati; richiedono una prova sul ricevitore e una decisione sul servizio di remux. Non far dipendere il video da un server HTTP sull'iPhone, che iOS puo' sospendere.

Verifica aggiunta alla workflow: fixture MKV sintetica con UTF8 inglese e ASS italiano, tempi, escaping e input malformati; test del servizio. Restano da provare un MKV reale intero, i tempi di estrazione, iOS -> hosting -> Chromecast a telefono bloccato e la nuova IPA su SideStore. Nessuna di queste prove reali e' sostituita dalla compilazione.

### Riscontri utente e correzioni controlli (0.4 build 5)

L'utente riferisce video diretto stabile, ma controlli dell'app inattivi mentre i controlli standard aperti dal tasto Cast funzionano. Individuato un rischio concreto nel controllo di identita': confrontava solo contentID con l'URL caricato da init(contentURL:). Ora controlla contentURL e contentID, imposta entrambi al LOAD e include test di regressione con contentID diverso dall'URL. Non e' ancora una conferma della causa sul dispositivo. Registrati listener sessione/media, riagganciati alla ripresa e richiesto stato aggiornato al ritorno in primo piano. Non disabilitata la sospensione iOS in background.

Le tracce RD prima erano nascoste dall'interfaccia in modalita' diretta: ora il selettore mostra quelle rilevate nel file, indicando che le alternative audio e i sottotitoli impressi richiedono conversione. La scelta attiva esplicitamente la modalita' compatibilita'; il cambio diretto non e' dichiarato supportato.

Live Activity: tempo trascorso e durata totale, barra e contatore a timer nelle viste blocco/Dynamic Island espansa; quando lo stato diventa obsoleto mostra l'ultima posizione nota. Durata inviata nel LOAD quando fornita dai metadati RD e usata come fallback quando Cast non la espone. Richiede verifica sul dispositivo, specialmente dopo sospensione e con LiveActivityIntent.

Riferimenti Stremio consultati, senza copiare codice: stremio-web/src/services/Chromecast/ChromecastTransport.js (eventi di sessione e media); stremio-video/src/ChromecastSenderVideo/ChromecastSenderVideo.js (proprieta' tempo, durata e tracce); stremio-chromecast-receiver/src/App/App.js (ricevitore personalizzato e messaggi urn:x-cast:com.stremio). Stremio usa un proprio receiver/protocollo: il suo selettore non dimostra che il Default Media Receiver possa selezionare gli audio MKV. Le idee di sincronizzazione sono state adattate all'SDK iOS, senza cambiare ricevitore in questa versione.

Conferma successiva dal dispositivo, 31 ottobre: sola GET_STATUS sul Chromecast classico, senza LOAD/STOP/SEEK e senza registrare l'URL video. Default Receiver in PLAYING a 160.6 s, durata 1440 s; media.contentUrl presente e media.contentId assente. TEXT EN con ID 1 presente e attivo. Questa risposta spiega concretamente il rifiuto dei controlli da parte della vecchia guardia contentID-only. La nuova guardia va comunque collaudata nell'app installata. Nessuna traccia AUDIO esposta nel media.tracks osservato: l'assenza di un selettore audio nativo Cast non prova che il file originale sia mono-audio.

## Checkpoint 0.4.1 build 6 - preparazione sorgenti

Riscontro utente: selezione sorgenti produceva HTTP 451 o messaggio generico 'sta ancora preparando il file, riprova'. La causa specifica del 451 non e' acquisita dal dispositivo. Il vecchio codice scartava il body RD; il limite richieste documentato e' HTTP 429 e codice RD 34, mentre RD 35 e' infringing_file e RD 36 fair usage. Non dedurre il codice RD dal solo HTTP.

Modifiche: CastController ora prova prima BridgeClient.resolveDirect anche quando esiste torrentHash. Solo BridgeError.cannotResolve permette il ripiego addMagnet; errori HTTP espliciti e rete non generano una nuova aggiunta torrent. Metadati preparati riusati in RAM per 120 s (max 8 sorgenti); nessuna nuova persistenza di URL. La risoluzione dell'add-on usa HEAD come gia' prima; host che non risolvono HEAD possono ancora richiedere il ripiego. Va collaudato sullo stesso file Stremio/iPhone: non promettere che tutti gli add-on espongano un URL riutilizzabile.

RDNativeResolver attende automaticamente la preparazione con aggiornamenti di stato/percentuale e legge le tracce appena ready, senza un nuovo clic. Gestisce anche metadati torrent inizialmente assenti. Poll ogni 5 s, massimo 36 controlli e deadline 180 s prima del successivo controllo (una richiesta in corso puo' aggiungere il suo timeout). Cambia sorgente annulla il task. Alla scadenza mostra stato reale non pronto, senza il vecchio 'riprova tra poco'. Il file potrebbe essere realmente non in cache: non garantire avvio immediato.

Attore condiviso per account (chiave hash SHA256 del token): richieste API distanziate di 0.4 s, cooldown minimo 60 s su HTTP 429/codici RD 5 e 34; Retry-After numerico rispettato fino a 3600 s. Non conta o controlla le chiamate che altri client/add-on fanno allo stesso account. Nessun retry automatico degli errori. Riusa id torrent per cinque minuti, separati per account/hash/nome file/dimensione; massimo 64 id. Nessuna cancellazione di torrent dall'account. Legge error_code e mostra fase sanitizzata, mai il body arbitrario o link.

Test sintetici aggiunti: magnet_conversion senza files -> waiting_files_selection -> downloading -> downloaded -> preparazione tracce senza nuovo clic; aggiornamenti di stato ordinati; timeout non marca ready e non aggiunge il torrent due volte; distinzione HTTP451/RD35 e HTTP451/RD36; secondo tentativo durante cooldown non produce rete. La nuova IPA richiede collaudo sul dispositivo. OAuth resta una futura miglioria di configurazione, non e' stato implementato.

## Checkpoint 0.5 build 7 - Live Activity, preferenze sottotitoli e dimensioni

Sources/CastDirectControl.swift usa Network.framework per connessioni Cast TLS brevi sulla porta 8009, solo IPv4 privati. Il pin SHA256 del certificato viene acquisito soltanto mentre l'SDK e' connesso al dispositivo scelto dall'utente; ogni comando successivo deve verificare il pin. UserDefaults conserva host, pin pubblico, hash dell'identita' del contenuto e timestamp (massimo 24 ore), senza URL o credenziali RD. Ogni comando rilegge receiver e media session, verifica l'hash del contenuto, invia PLAY/PAUSE/SEEK e aggiorna la Live Activity solo dalla risposta MEDIA_STATUS. Non fa LOAD, non lancia receiver, non trasferisce video e non usa audio silenzioso o permessi background estranei. Cambio IP/certificato/dispositivo o contenuto diverso richiedono riapertura dell'app e nuova connessione SDK. Primo handshake 6 s e richieste 4 s ciascuna; socket chiuso dopo il comando.

LiveActivityIntent esegue il comando breve quando l'app non e' attiva; in primo piano usa prima l'SDK e poi il collegamento breve come ripiego. CAST_WIDGET distingue il target estensione dal codice del processo app. Timer SDK non riscrive lo stato mentre l'app e' in background. La barra fornisce 11 punti di salto tra 0 e 100% e pulsanti +/-30 s: non e' uno slider trascinabile. Apple supporta Button/Toggle interattivi, non un normale Slider nella Live Activity. Nessuna promessa di stato sempre aggiornato quando nessun processo puo' interrogare la TV. Riferimenti: documentazione Apple adding-interactivity-to-widgets-and-live-activities e Google Cast suspendSessionsWhenBackgrounded. Non disabilitata la sospensione dell'SDK.

Sources/SubtitleAppearance.swift e CastRemote/SubtitleAppearanceView.swift: preferenze Codable/UserDefaults validate, anteprima indicativa, scala 60-200%, colori, caratteri, contorno e sfondo. LOAD include textTrackStyle; cambi correnti applicati tramite setTextTrackStyle con debounce 400 ms. Persistenza per dispositivo/sessioni, non sincronizzazione account. Tracce impresse nel video non modificabili. La preview non e' rendering esatto del receiver.

SourceFileSize preferisce behaviorHints.videoSize; ripiega sulla dimensione testuale dichiarata dal provider e distingue '2.61 / 24.6 GB' (file/raccolta). Mostra dimensione a destra della scheda sorgente e delle righe in-app; sconosciuto esplicito. Non puo' spostare colonne nell'UI di Stremio.

Incluse anche le distinzioni handoff HTTP locali preparate nel turno precedente: solo 410 e' scadenza, altri HTTP e risposte non JSON distinti. Test sintetici HandoffTests, CastWire (envelope, LAN, limiti seek), preferenze persistenti e dimensioni; nessun test sintetico sostituisce il collaudo iPhone bloccato -> Chromecast. Verificare pin iniziale, pausa/riprendi, salti, riconnessione a SDK sospeso, font/stile reali e SideStore. Estrattore/hosting e audio senza conversione mantengono i limiti gia' documentati.

## UI minimale - revisione senza compilazione

L'utente ha fermato le compilazioni e chiesto di migliorare prima la UI. Non avviare nuove build/IPA finche' non lo richiede. La build 0.5 gia' partita era conclusa al momento dello stop; non equivale alla verifica di questa revisione UI.

ContentView ridisegnata: intestazione compatta Cast Bridge con stato e menu; scheda sorgente con dimensione a destra; player con timeline a larghezza piena, pausa centrale e +/-30 secondi; pannello Audio e sottotitoli separato; accesso diretto all'anteprima; opzioni avanzate e configurazione servizio in sezioni richiudibili. Dettagli completi sorgente conservati nel pannello. Nessun codice traccia interno nei titoli; tracce omonime distinte da numero. Impostazioni sottotitoli con campioni colore, preview neutra e indicazione del salvataggio automatico.

Verifica di questa UI: controllo diff e revisione visiva di uno studio del layout con dati d'esempio. Non e' una schermata di SwiftUI compilata; nessun test su simulatore/iPhone o compilazione eseguiti dopo lo stop. Conservate le logiche di selezione, compatibilita', applicazione tracce, volume, seek, estrazione ed esportazione. Da controllare alla successiva compilazione autorizzata: tutte le viste e sheet, Dynamic Type, schermi piccoli e corrispondenza del layout nativo.

## 0.5.1 build 8 - compilazione autorizzata e icona

L'utente ha approvato la UI minimale e richiesto esplicitamente la nuova IPA, revocando lo stop precedente. Aggiunta icona opaca 1024 px nel catalogo AppIcon, collegato alle risorse del target app; versione app/estensione allineata a 0.5.1 (8). La verifica reale dei controlli in background resta da svolgere su iPhone. Nessuna modifica al backend Sites o nuova promessa su audio multitraccia/hosting sottotitoli.


## 0.5.2 build 9 - audio AC3 e verifica conversione

Riscontro utente: MKV senza audio nel percorso diretto, conversione in caricamento senza avvio, codec AC3. GET_STATUS sola lettura sul ricevitore il 31 ottobre: PLAYING, contentType video/x-matroska, volume dispositivo e media 1, muted false su entrambi. Non e' una prova di audio effettivamente decodificato; esclude solo il mute esposto dal Cast in quel momento.

Aggiunti avvisi audio Dolby/DTS/multitraccia nei pannelli e sommario codec reale; il default HLS non e' presentato come audio predefinito del file originale. Stato muto del dispositivo visibile con riattivazione esplicita, senza alzare automaticamente il volume.

Prima di LOAD in compatibilita', RDStreamProbe legge solo playlist HLS dal telefono: massimo tre livelli, 256 KiB per risposta, timeout risorsa 20 s, soli host stream RD gia' previsti, niente credenziali API nelle richieste. Verifica header, playlist non vuota, riferimenti child e cicli. Non scarica segmenti, non verifica decodifica/passthrough o accessibilita' dal Chromecast. Un errore HTTP/playlist e' persistente in UI e non sostituisce il video diretto gia' in riproduzione. Non trasforma AC3 in AAC in locale e non implementa un nuovo servizio di conversione.

Da collaudare: ottenere l'errore effettivo della conversione sullo stesso film. Non dichiarare risolto l'audio AC3 finche' manca questa prova.


## Checkpoint 0.6.0 (10) - motore integrato, candidato in verifica

Questa sezione sostituisce le indicazioni di architettura dei checkpoint precedenti. L'utente ha richiesto esplicitamente una nuova IPA con adattamento automatico interamente nell'app, senza NAS/server o scelta di codec. main resta 0.5.2 finche' la verifica del candidato non e' conclusa.

MobileVLCKit 3.7.5 legge le vere tracce del file e realizza remux/codifica su iPhone. Se possibile conserva il video H.264; converte l'audio in AAC stereo. Per video incompatibili o sottotitoli incorporati usa H.264 VideoToolbox, con ripiego VP8/Vorbis. Il controller rigenera il flusso al seek, preservando posizione, durata originale, pausa e selezioni. VTT esterni serviti in LAN e riallineati dopo i salti. Gateway con token casuale e accesso limitato al Chromecast scelto, buffer limitati e chiusura del flusso a EOF.

Il pacchetto iOS VideoLAN non contiene il decoder TrueHD: acquisito log effettivo "codec not found (TrueHD Audio)". AudioRepairPipe usa FFmpegKit Extended base LGPL v0.11.2-ios, archivio verificato SHA256, per sostituire soltanto l'audio scelto con AAC. Video e sottotitolo selezionato passano senza ricodifica in una FIFO privata 0600, letta da VLC. Nessun intero film scritto su disco. Comandi con argv, log disabilitati, cronologia limitata a una sessione in RAM, nessuna chiave o URL nei file. Dipendenza, sorgenti e licenze documentate in THIRD_PARTY_NOTICES.md.

Background: adottato il meccanismo della riproduzione remota di VLC iOS (sessione audio e riproduttore /dev/zero solo mentre il flusso locale e' attivo), UIBackgroundModes audio e suspendSessionsWhenBackgrounded=false. Questo sostituisce la precedente indicazione di non usare un riproduttore ausiliario: non e' un divieto esplicito dell'utente. La prova offscreen su simulatore ha trasferito oltre 1.5 MB in circa 15 s, con helper realmente attivo. Non e' una prova dello schermo bloccato su iPhone fisico. Il telefono deve restare acceso e sulla rete Wi-Fi; la chiusura forzata interrompe la conversione.

Prove gia' ottenute prima dell'ultimo candidato: 24/25 combinazioni sintetiche convertite con audio stereo, scelta corretta della traccia italiana (440 Hz effettivamente decodificati), AC3 5.1 convertito in AAC stereo con audio non silenzioso e sottotitolo SRT visibile nel fotogramma prodotto. Tre percorsi da file generati dall'effettivo binario iOS sono stati riprodotti sul Chromecast fisico: MP4 H.264/AAC, MP4 con trasferimento chunked, WebM VP8/Vorbis. Non equivalgono al collaudo della nuova IPA integrata o di un film intero.

In verifica: nuovo AudioRepairPipe TrueHD e preriscaldamento della stessa connessione HTTP conservata per la TV, che evita di scartare l'inizio dei clip brevi durante il controllo di compatibilita'. La workflow del simulatore esercita i tre modi video, TrueHD tramite FIFO e gateway, 25 combinazioni e background. CAST_ENGINE_TESTING e' escluso dalla produzione. Restano da acquisire esito di queste prove, build iphoneos e pacchetto 0.6.0 (10), quindi collaudo dell'utente sullo stesso film AC3 e su iPhone realmente bloccato.
