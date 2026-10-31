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

