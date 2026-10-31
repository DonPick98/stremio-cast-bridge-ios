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
