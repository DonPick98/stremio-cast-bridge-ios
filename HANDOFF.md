# IPA53 candidata disponibile — CB028 latenza, 2026-11-06

Prodotto94e2c740bc055c59a5bec925947d694b2a983088, branchfix/captions-background-20261105,
PR9draft. BuildiPhone/regressioni42139358470 SUCCESSO. Runtimefunzionale353a9232;
94e2c740 cambia solo fixture/testbenchmark (numero frame del muxer nativo), non
il codice prodotto. TestSDK/lifecycle42133853266 SUCCESSO sul ramo latenza.

IPA effettiva0.8.1(53), app/estensione53, unsigned, audio+processing/CC1AD845,
risorsaMKVSubtitleExtractor.js e licenzeMIT incluse.69432627byte,
SHA256 38e66e493092fcf00f232ad852a0d842f797e42ef9fde9d524089f258df4dedc.
Artifact13468280746, ZIPdigest sha256:cd13fd9904c68241d4cf4f6c0f68411a821c02dc0d8a4f66ca593b66d3e1b47b,
run42139358470. File scaricato/auditato e disponibile inchat come candidata.
Nativa completa sulla sorgente esatta42139358480 IN_CORSO: recuperare esito e
non dichiararla passata prima della conferma. Nessun collaudo hardware53.

Utente: seconda traccia inglese visibile su52 dopo56s. Risoluzione53:
-IndicizzazioneMKV (upstreamMIT cryguy/mkv-subtitle-extractor dbe77e997de9d305d2b45b237352a3dec51b5bb5),
Cues+blocchi verificati controNUMBER_OF_FRAMES dellaTrackUID, niente documenti
parziali. Headercluster VINT variabili supportati; batch≤256KiB, limiti perread/byte/
requests/tempo,206/ContentRange/size/validator e HTTPSredirect prima delbody.
-URLSessionDataDelegate perblocchi, bridgebinarioBase64 versoJavaScriptCore;
FFmpeg completo52 parte in parallelo, primo documento valido vince/cancellaaltro.
-Descrizioni originali conservate, preferenza sulle labelespliciteForced/Signs/Songs
se esiste alternativa stessa lingua; scelta manuale invariata. Nessuna deduzione
forced dal numero cue. Codecvideo/receiver/OpenSubtitles/account invariati.

Misure controllate: fixtureMatroskavalida8389226byte,328074byte letti/6requests,
prime/ultimecue verificate. Throttledserverlocale1655ms intero vs133ms indicizzato.
CLIJavaScriptCore finale: locale0.054s, HTTP0.034s (prima5.55s), suite0.197s con
badRange/200/cambiofile/oversize/troncamento e cancellationprima/inflight passati.
Non sono tempi della puntata privata. TestHTTP anteriore0.1sNode è distinto dal
percorso nativo; non usare il numero come promessa su iPhone/TV.

Failure intermedie2a192/7dc (42133853361/42136639560): fixture dichiarava7ma
muxer iOS ha omesso la battuta durata0, lasciando6pacchetti e6Cues. Exportfile
verificato conFFprobe e parser: con ilsolo tagcorretto6 il fastpath riesce. In94
gate invariato, statistica fixture corretta; nessun falsoPASSretroattivo.
Difetto separato upstreamassumeva headerclusteruguali: corretto e provato con
MKVvero2cluster diversi, stessi testi/tempiFFmpeg. Varianti superate annullate.

CB028 IMPLEMENTATO_DA_VERIFICARE. Per misurare: Preferenze→Memoria locale→Svuota
cache sottotitoli, riaprire stessa puntata e scegliere seconda traccia; escludere
anche il documento ancora inRAM durante una sessione giàattiva. Log sicuro
caption_index_attempt/ready/fallback con secondi/byte/requests/codici distingue
fastpath dafallback. Se indice mancante/incompleto resta lettura completa52;
il fallback non attende un timeout sequenziale. Nessun tempo fisso promesso,
nessun merge o releasepubblica. Checkpoint sotto storici.

---

# Candidata53 — priorità latenza sottotitoli (CB028), 2026-11-06

Utente conferma seconda traccia inglese visibile sulla52 dopo56secondi. Non più
un fallimento generale di conversione/consegna; prima traccia ancora non identificata.
Base28aa3b2 (checkpoint recuperato), codice52 preservato come fallback.

Nuovo estrattore indicizzato MKV: upstream cryguy/mkv-subtitle-extractor MIT,
commitdbe77e997de9d305d2b45b237352a3dec51b5bb5, sorgenti+bundler offline conservati.
AdapterJavaScriptCore/URLSession bounded; accettaASS/SSA connumeroCues/blocks uguale
alla statistica NUMBER_OF_FRAMES della TrackUID corretta; noContentEncodings,
noindiceparziale come documento completo. Richieste206/ContentRange/size/validator
verificate prima delbody, HTTPSredirectguard, max1MiB/range32MiB/2048requests/12s.
Il demuxFFmpeg completo parte in parallelo: vince il primo documento validato,
perdente cancellato; fallback non aspetta la scadenza del percorso rapido.
ConversioneASS52 invariata. Nessuna modifica video/receiver/account.

TestNode fixture8.389.176byte:295.148byte letti/4richieste, cue iniziale e finale,
indiceincompleto/statisticaerrata/range200 rifiutati. Serverlocale throttled:
1.613ms lettura intera vs103ms indicizzata; misura sintetica, non puntata privata.
TestJSC nativoCLI+URLProtocol e MKV reale con motoreapp aggiunti; CI da acquisire.
App/estensione53. Nome originale tracce visibile anche dopo promozione;
preferenza automatica evita labelespliciteForced/Signs/Songs se esiste alternativa
stessalingua; selezionemanuale e unicaForced conservate. Non dedurre forced da5cue.

Nessuna IPA53 ancora dichiarata pronta. Resta necessario collaudo stessa puntata
secondatraccia con tempo reale, seek, blocco/cambioapp. Non promettere tempi fissi.
CB028 IN_CORSO. Nessun merge/main o releasepubblica. Checkpoint sotto storici.

---

# IPA52: sottotitoli ancora assenti su TV — CB028 RIAPERTO (2026-11-06)

Nessuna nuova IPA o correzione hardware dichiarata. Prodotto52 resta74748b2;
HEAD documentazione4a0a598 prima di questo checkpoint. Suite esatta52
42120072440 ora SUCCESSO, distinta dalla prova hardware ancora fallita.

Nuovo log utente23:05:51→23:07:38UTC: catalogo16SSA, conversione completata
23:07:00.386 con3720byteASS/5eventi/dropped0 e454byteVTT. Promozioneembedded,
secondoLOAD daoffset265.600, clockvideo procede. Nessun erroreconversione.
Questo non dimostra completezza né visibilità della traccia suTV. Cinquecue
potrebbero essere forced/signs, una traccia sparsa corretta o estrazione interrotta.
Non scegliere una causa senza prova; nessun HTTPfetch/ack di attivazione texttrack
né intervallo cue nel log attuale.

Risposta utente al tipo traccia: Inglese-nelfile. Difetti accertati nel codice:
PlaybackPreferences.subtitle sceglie tracks.first per lingua senza distinguere
forced/full; trackLabel omette RDTrack.label e mostra lingua/numero soltanto;
embeddedSubtitleLabel perde anche il numero e descrizione originale dopo
promoteReadyEmbeddedText. CaptionCatalog ignora disposition.forced/default.
Questi difetti possono scegliere/nascondere una traccia sparse, ma non provano
che questa sia la causa del file privato. OffsetVTT viene correttamente ribasato
inEmbeddedMediaEngine.start; selectedembedded attiva kind2 conIDpresente.
Proxy serveVTT conCORS; manca evidenza del fetch effettivo in questo caso.

Prossimo passo hardware minimo: scegliere un'altra voce Inglese-Traccia…-nelfile,
diversa dalla prima e dall'alias estratto, attendere preparazione; verificare
visibilità. Evitare un'altra build a tentativi senza questo riscontro. Se fallisce
servono metadati sanitizzati forced/default+intervallo/countcue, stato GET VTT e
activeTrackIDs sul ricevitore; eventualmente sample originale autorizzato senza
credenziali. Poi correggere scelta automatica e nomi preservando selezione manuale,
lingua e OpenSubtitles. Nessuna scelta silenziosa basata solo sul numero5cue.
Issue1 riaperta con evidenze; nessun codice prodotto cambiato in questa analisi.

---

# IPA52 pronta — CB028 implementato, collaudo file privato richiesto

Prodotto74748b2a503188748fe03950e7be7fa7a1f59f83; branch fix/captions-background-20261105,
PR9 draft. Build iPhone/regressioni42120072427 SUCCESSO. Suite nativa completa
42118240017 su bdd3f160 SUCCESSO: independentCaptions.passed=true,
degenerateASS=true, sixteenSSA=true, complete/batch, font/CORS/cancellazione,
matrice codec/qualità/overlay e background65s con offscreen=true PASSATI.
Confronto bdd3f160→74748b2 verificato: solo licenza inclusa nel bundle e fixture/test
unitario (tempi centisecondi per portabilità FFmpegCLI); nessuna differenza nel
codice prodotto, CaptionFFmpeg/SubtitleDocument/integrazione nativa invariati.
La ripetizione automatica42120072440 sulla sorgente74748b2 è IN_CORSO e non
viene dichiarata passata. Non serve attendere una duplicazione per certificare
nuovamente il codice prodotto identico; recuperare comunque l'esito al prossimo giro.

IPA effettiva0.8.1(52), app/estensione52, unsigned, audio+processing,
CC1AD845, attribuzione Subtitle Edit presente nel bundle. 69381613byte,
SHA256 9fffa9d92bc300c51e418bd8457b210efc6c0f33ed81d3283c344c63c7945832.
ZIPartifact13458581190, digest sha256:9d2d62d16965de52c9f76c6ed3ff230af81262d99d23da85d40ff142d13935f6,
run42120072427, fino2026-11-12. IPA scaricata, verificata e resa disponibile inchat.

CorrezioneCB028: per ASS/SSA demux originale copy→parser eventi Swift adattato
Subtitle Edit MIT→WebVTT. Isola durate0/clock invalidi/commenti/disegni,
conserva dialogo/overlap/virgole, escape del testo e serializzazione dei tempi.
Nessun VTT incompleto servito come completo. Errori empty/document distinti da
exitFFmpeg; conteggi conversione senza testo/URL privati. SRT/WebVTT esterni,
codecvideo, receiver, seek50 e features49 preservati. UI/accountStremio invariati.

Limite: il difetto WebVTT è riprodotto con una fixture; causa esatta del file privato
utente non provata. CB028 IMPLEMENTATO_DA_VERIFICARE, riaperto dalla prova51.
Prossimo passo: stessa puntata/traccia su iPhone/TV e diagnostica2min se fallisce;
nessun risultato hardware52 dichiarato. Primo51 esatto42106877735 rimaneFAILURE
per offscreen simulatore, distinto dal nuovo successo nativo52. Nessun merge o
release pubblica. Checkpoint seguenti storici.

---

# Candidata52 — CB028 riaperto dopo prova hardware51

Base df38ad5, branch fix/captions-background-20261105, PR9 draft. IPA51 fallisce
ancora: catalogo16tracce riuscito, errore process successivo senza exit-code.
Non attribuire il caso originale a una causa non ancora provata.

Riproduzione concreta locale FFmpeg6.1.1: ASS con evento durata0 e \\N\\N
produce WebVTT non valido pur con exit0. Validazione51 scarta l'intera traccia.
Nuovo percorso: demux ASS/SSA originale (-c:s copy, -f ass), parser Swift
text-only adattato dal trattamento eventi Subtitle Edit (MIT, licenza inDocs),
poi WebVTT. Scarta commenti/disegni/durate0 ed eventi non interpretabili, isola
le anomalie per evento, conserva overlap/virgole, ordina i tempi, escapeHTML e
linee non vuote per evitare delimitatori VTT nel payload. Nessun parser generico
VTT reso permissivo; altri codec/media/receiver/OpenSubtitles invariati.
Diagnostica distingue exit FFmpeg, output vuoto, documento invalido e conteggi
conversione; nessun testo/URL privato. Dimensione/timeout/cancellazione conservati.
Test unitari e demux nativo suMKV con ASS problematico aggiunti. App/estensione52.

Prima suite esatta51 42106877735: caption indipendenti/sixteenSSA PASSATI,
righe audio/video decoder PASSATE; workflow FAILURE perché simulatore non entra
in offscreen (comando openurl fallito, background.offscreen=false). Non è un
passaggio della prova background né una regressione caption dimostrata.
Parent51 42106360183 resta SUCCESSO distinto. Non indebolire le asserzioni.

CI52 da acquisire; nessuna IPA52 dichiarata pronta. File privato originale
non disponibile: prova iPhone/TV specifica necessaria, CB028 IN_CORSO. Non toccati
accountStremio/altrefeatures. Non fare merge/main o pubblicazione release.

---

# IPA51 pronta — priorità SSA, CB027/028 (2026-11-05)

Prodotto620f7544e840cbeff128b425e650a80d0dd95d5a; branch fix/captions-background-20261105,
PR9 draft. Build iPhone42106877628 e policy/SDK42106877504 SUCCESSO.
Suite nativa completa42106360183 su6db6d31 SUCCESSO: sixteenSSA=true,
independentCaptions.passed=true, documenti completi/font/CORS/cancellazione,
gate video/audio/caption,35codec/qualità/background passati. CaptionFFmpeg,
CaptionModel e CaptionIntegrationValidation sono identici tra6db6d31 e620f754.
Unica differenza prodotto620: prima registrazione job quando l'handoff inizialmente
inactive diventa foreground. Questa parte compilata/testata SDK sul prodotto.
La ripetizione della suite completa sulla sorgente esatta42106877735 è IN_CORSO;
recuperarne esito nella prossima sessione. Non confondere fonti dei risultati.

IPA effettiva verificata: app/estensione0.8.1(51), unsigned, audio+processing,
receiverCC1AD845,69374568byte. SHA256
e1809e67f19a7b6017fb6fed0ed60ae8abefe6fb45f58238b74f3c34eecdc3ca.
ZIPartifact13452947597, digest ZIP sha256:d74fc911feedf4aa8aca8398d3f751363241dae6baefe48779d2a1ad2c035b00.
Download https://github.com/DonPick98/stremio-cast-bridge-ios/actions/runs/42106877628/artifacts/13452947597
Fino2026-11-12; IPA estratta e resa disponibile nella chat.

SSA: header-only prima dell'analisi video, estrazione scelta isolata dalle alternative,
riconnessione HTTP temporanea bounded, exit code/state senza URL/log grezzi e retry
della stessa traccia daUI. TestCLI6.1.1 HTTPS503→success e403 senza retry passati,
distinti dal backend nativo. Originale privato con16SSA/HEVC4K non acquisito:
CB028 resta IMPLEMENTATO_DA_VERIFICARE, nessuna promessa che quel file sia risolto.
BG: consegna confermata per segmenti e residuo ricalcolato dopo seekback, clock
vecchi esclusi, rollback riallineato e diagnostica unità/ultimo progresso.
CB027 IMPLEMENTATO_DA_VERIFICARE hardware; progresso fermo prima della scadenza
è provato nel codice50, la causa precisa dell'expiry di iOS resta un'ipotesi.
Nessun heartbeat fittizio, rinnovo automatico, nuovo receiver o pagamento.
Fix50 e features49 preservati. Nessun merge su seek/feature/fix/main.
Registro issue1 aggiornato. Checkpoint seguenti storici.

---

# Candidata51 — priorità SSA e progresso background (CB027/028)

Base db3f114 / IPA50, branch fix/captions-background-20261105. Due riscontri:
-16SSA/HEVC2160: fallimenti probe/proccess prima del testo; causa originale non
ancora provata. Catalogo header-only con fallback analizzato, scelta singola
anziché batch alternativo, recupero HTTP temporaneo bounded, codici d'uscita
sanitizzati e retry della stessa traccia visibile senza cambiare sorgente.
-Seek2061→556: BackgroundPlaybackWork ignorava le posizioni sotto start1952 e
pubblicava progresso fermo. Ora conta consegna confermata per segmento, rebase
non guadagna unità e aggiorna lavoro residuo; clock vecchi/preparazione esclusi.
Rollback riallinea l'anchor precedente. Log completed/total/tempo da ultimo
progresso a cadenza snapshot e prima di expiry. Nessun heartbeat fittizio,
nessun rinnovo automatico dopo expiry, posizione originale50 preservata.

Test previsti: regressioni tempi reali e16SSA, vero backend iOS/probe/estrazione,
SDK e buildiPhone. App/estensione51. Da acquisire risultati prima della consegna;
nessuna IPA51 ancora dichiarata. Il file privato non è stato acquisito e un test
sintetico non certifica quel caso, né la causa precisa della scadenza di iOS.
Nessuna finestra VTT parziale servita come documento completo. Receiver gratuito,
OpenSubtitles e decoder invariati. SyncStremio non modificata: login separato
dal toggle, come documentato nella issue1. Nessun account reale usato.

---

# IPA50 pronta — CB025/026, 2026-11-05

Sorgente prodotto750ad1d06c8c6e708a21c571e96797931170dc3e; branch fix/seek-burst-20261105, PR8 draft.
Build iPhone/regressioni42101551169 SUCCESSO, lifecycle/API42101551139 SUCCESSO.
Nuove regressioni per tempi reali della raffica, intent superati/stop e offset.
Pipeline codec48 invariata; non rieseguita la matrice nativa completa.

IPA effettiva verificata localmente: app/estensione0.8.1(50), unsigned,
audio+processing, receiverCC1AD845. 69375547byte,
SHA256 6d4874d3b3a219318cd3af8bb75aebcad7584384e4b3851e52e1a4a99c2fc8f5.
ZIPartifact13448728918, digest ZIP sha256:b53471f696e7e8a846d501be21bd1a18b32ec32d446ddcd9dbd08f32d671d02a.
Download https://github.com/DonPick98/stremio-cast-bridge-ios/actions/runs/42101551169/artifacts/13448728918
Artifact fino2026-11-12; IPA estratta e resa disponibile nella chat.

CB025/026 IMPLEMENTATO_DA_VERIFICARE su iPhone/TV: 4tap+30→+120 e cambio
direzione durante prepare/LOAD, pausa/stop, tracce e ripresa dopo expiry.
Nessun candidato preparato superato deve inviare LOAD. Un LOAD già inviato al
ricevitore non può essere retroattivamente annullato con certezza: il nuovo
target non attende più che quel LOAD raggiunga PLAYING prima di prepararsi.
L’offset posseduto dal LOAD sopravvive all’encoder; sospensione/nonloaded escludono
capture e callback tardive. Nessun nuovo job automatico dopo expiry; la causa
della scadenza di sistema non è dimostrata. Features49 preservate.
Registro issue1 aggiornato, nessun merge su feature/fix/main compiuto.
Checkpoint sotto storici; non dichiarare collaudo fisico50 o consumi migliorati.

---

# Candidata50 — seek rapidi e timeline dopo expiry (CB025/026)

Base446ea0d / IPA49, branch fix/seek-burst-20261105. Riscontro hardware49:
4tapforward2124.859→2244.859, ma LOADintermediooffset2184.859 e solo dopo
nuova preparazione2244.859; expiry poi salva0.850 relativo al posto di2123.731.
Non attribuire la causa di continued_expired a RAM o a un fatto non provato.

Patch: debounce trailing300ms con generazione intent, cancellazione prepare/LOAD
locali superati, guardia prima di installare il candidato e completamenti obsoleti
esclusi. Il dispatch locale non attende più il primo LOAD/conferma per elaborare
l'ultimo target. Play/pausa e tracce mantenuti. Offset originale posseduto dal LOAD
ricevitore, non dall'encoder; capture escluso durante sospensione/nonloaded e
callback trasporto obsolete escluse. Nessun nuovo job automatico dopo expiry.

Test policy con tempi reali della raffica, cambio direzione e nuove richieste
mentre prepare/LOAD precedenti sono attivi, invalidazione/stop e mapping originale
alla ripresa. CI regressioni/API e buildiPhone da acquisire. App/estensione50.
Pipeline codec e decoder invariati; nuova prova iPhone/TV indispensabile.
Registro canonico issue1; nuove funzioni49 preservate, nessun merge sufix/main.

---

# IPA49 compilata — selettore episodi e attesa autoplay, 2026-11-05

Sorgente prodotto40dfd8eba5d3e44cd3e8f4efc944849d2e49d1ef.
Branch feature/episode-picker-20261105, PR7 draft verso fix/playback-recovery-20261103.
Build iPhone e regressioni42059128287 SUCCESSO; lifecycle/API iOS42059128067 SUCCESSO.
Artifact IPA13430746684, ZIP68772212byte, digest ZIP
sha256:3fcfb7a2e86b402f76f9447a6fa6db95e6ee9524eab59813b4fa813c887b818a.
Download: https://github.com/DonPick98/stremio-cast-bridge-ios/actions/runs/42059128287/artifacts/13430746684
Disponibile fino2026-11-12. Estrarre CastRemote-unsigned.ipa dal pacchetto ZIP.
Non confondere il digest ZIP con quello dell'IPA interna. Nessun audit binario
aggiuntivo effettuato; packaging e controlli previsti nel workflow passati.

App/estensione impostate0.8.1(49) nel progetto. FT001/002/003 implementate da verificare:
selettore stagione/puntata, countdown0/5/10/15s (default0), Avvia ora/Annulla.
La riproduzione manuale annulla anch'essa l'attesa; in background serve lease valida.
Tutte le regressioni build passate, incluso Stremio/offline, lingue/caption,
cataloghi, preferenze/reset, resolver, hosting e receiver. Nessun nuovo collaudo
di queste feature su iPhone/TV. Pipeline media48 invariata; non rieseguita la
suite nativa dei codec in questa iterazione. Nessun merge su fix/main compiuto.
L'utente conferma background e controlli iOS nella versione già in uso, fps finora:
preservare quei riscontri senza estenderli ai nuovi passaggi episodio.
Registro canonico issue1 aggiornato; restano contesto origine, personalizzazione
restante, sync/account e updater stabile/in-place. Checkpoint sotto storici.

---

# Iterazione49 — selezione puntata e attesa autoplay (FT-001/002/003)

Base prodotto 05b8bed / IPA48, branch feature/episode-picker-20261105.
L'utente conferma ora continuità in background, fps rilevati finora e ritorno
dei controlli iOS. Non equivale a ogni scenario di interruzione/recupero né
alla chiusura del probe intermittente CB024. Preservati Now Playing nativo,
receiver CC1AD845 e pipeline media48. Nessuna nuova ActivityKit personalizzata.

Nuovo: elenco stagioni/puntate dal catalogo validato esistente, selezione diretta
anche fra stagioni usando la stessa preparazione transazionale della navigazione.
Nessun episodio inventato; speciali secondo preferenza. Puntata corrente marcata.
Attesa autoplay facoltativa 0/5/10/15s, default immediato conservato; si attiva solo
alla fine confermata e per il prossimo episodio già ammesso dalla policy esistente.
Avvia ora/Annulla, deadline monotona, token invalidato prima dell'avvio e su reset,
stop, cambio fonte/episodio o ritorno a Stremio. Lease UIKit limitata per l'attesa;
alla scadenza annulla, nessun rinnovo o garanzia background illimitato.
Disattivare autoplay annulla l'attesa. Le modifiche alla durata valgono dal
passaggio successivo. Codec, fps, qualità e preferenze tracce invariati.

Test policy: destinazioni valide/stessa serie, buchi, invalidi, ritardo/default/reset,
wake tardivo e contesto cambiato. CI regressioni e build iPhone da acquisire;
non dichiarare IPA49 pronta prima della build. App/estensione impostate49.
Restano collaudo due episodi e picker su iPhone/TV, contesto origine app/web,
tema/accessibilità/profili conversione, sync account e updater stabile/in-place.
Registro canonico issue1. Gli altri checkpoint sotto sono storici.

---

# Candidata48 — gate testo passato; correggere fallback VP8 troncato

18fef57/42017281562/artifact13409969866: gate testo integrato bounded PASSATO
210frame, identità79..90, audio440Hz/stereo, delay+0.5s e cleanup. Tutte35 righe
matrice e6pixel-caption PASSATE; background65.039s/7.87MB e controlli PASSATI.
Suite complessiva FAIL al quality vp82997: timeout -1001 e soli102/120frame,
WebM incompleto. Non era un semplice ritardo da ignorare. Gate seek e quality
successivi al decodecheck non eseguiti in CI: verificare senza abbassare soglie.

Nuovo: softwareVP8 passa anch'esso a FFmpeg/libvpx, con drain encoder e EOF
esplicito. Mantiene Vorbis192k/stereo; preferisce libvorbis se disponibile, altrimenti
encoder Vorbis nativo con flag experimental esplicito. Encoder disponibili letti
via API C pubblica della versione pinned, senza ipotesi sulla build. Il gate testo
ora copre anche VP8 con clock, audio, pixel e cleanup. Nessuna nuova IPA pronta;
47 resta ultima consegnata. Serve nuova suite prima di promozione/IPA48.

---

# Candidata48 — rendering testo FFmpeg/libass con documenti bounded

Prototipo locale iOS ca0aa416 /42015146268/artifact13409701754: libass PASSA gate
rigoroso con210frame/210, prime identità79..90, gap42ms. Le quattro varianti VLC
sul backend video non hanno completato prepare (nessun confronto frame lì);
i risultati VLC affidabili restano ddbeb9b con basebackend. Non attribuire a
sola microprecisione la soluzione. CLI locale: anche VTT completo, stile e delay
+0.5s passati (pixel quiet/on/quiet) con210frame e timeline corretta.

48 usa il backend LGPL video pinned v0.11.2, SHA772310d94274a5721e302960bc3f6aab706115409cb03dd2839d67fd4f718891.
Primo percorso FFmpeg anche per testo integrato. Prima estrae/cache documento
completo1MiB con timeout120s, catalogo2MiB e font bounded12MiB/8file; selezione
convalida indice/codec/lingua. Renderer riceve soltanto file VTT/font locali privati;
nessuna riapertura URL remoto nel filtro. Rispetta stile e shift timeline/delay,
con riavvio e cache-key aggiornata per modifiche delay. Directory rimossa dopo
rilascio backend, anche stop/errori. Percorsi sidecar/OpenSubtitles restano.

Nuovo gate text-overlay: identità completa, testo negli intervalli attesi con
+0.5s, tono440Hz/stereo e cleanup. Suite nativa completa sul branch test; NON
promuovere a fix o consegnare48 prima di gate estesi. IPA47 resta ultima consegnata.
Il gate seek originale non è allentato. Default receiver invariato, nessun deploy.

---

# CB009/021 — nessuna variante VLC supera il gate, prova libass locale

Esperimento ddbeb9b /42012879991/artifact13407854195: baseline e decoder software
212frame, gap125.125ms, prime identità73,73,77,77; clock fine elimina duplicati
ma conserva73,75,77 prima del target79, gap83.416ms. Quattro output catturati,
nessuno passa checkOverlaySeek: nessuna variante attivata in produzione.
Nativo47/42010715495 concluso FAIL allo stesso seek; background65.036s/8.26MB,
probe23.976 e controlli nativi passati, artifact13406869574. IPA47 invariata.

Seconda prova: workflow seek-probe richiede CAST_ENGINE_ASS_TEST=1 solo durante
pod install; Podfile normale continua a usare il backend base originale. Variante
LGPL video v0.11.2 con SHA256 del release asset verificato, per libass. Nuovo
trial usa soltanto fixture locale sintetica con subtitles filter e seek FFmpeg,
riporta timeline originale al renderer prima di ribasare. NON è una funzione
remota pronta: serve poi estrazione locale bounded/cache/fonti/font/style/delay,
licenze distribuite e gate estesi prima della produzione. Nessuna nuova IPA48.

---

# CB009/021 — esperimento seek isolato, prodotto invariato

Da a5f8fb2 / IPA47. Nuovo workflow seek-probe sul branchtest confronta baseline,
decoder VLC software, clock encoder microsecondi senza filtro fps e combinazione.
Opzioni attivate esclusivamente CAST_ENGINE_TESTING. Nessuna modifica alla IPA47
né attivazione di queste opzioni in release. Quattro output sintetici con identità
di frame; checkOverlaySeek rigoroso esistente senza soglie modificate. Catturare
seek-trial-checks.json e log; successo job richiede un candidato che superi il gate,
ma non sostituisce la suite di accettazione produzione e i test audio/sottotitoli.
Non dichiarare correzione prima di risultati e validazione estesa del vincitore.
Nativo47/42010715495 ancora in corso alla ripresa. Registro commento6655856545.

---

# IPA47 pronta — episodi Stremio integrati

Commit ccbdc0e1494b09b032c91fa7e1321ec3c59f8722, branchfix e PR2 draft.
PR5 risulta integrata per avanzamento del branchfix. iPhone42010715581 SUCCESSO;
policy/SDK42010715369 e documenti sottotitoli42010715354 PASSATI. Artifact13406658794
estratto: app ed estensione0.8.1(47), receiverCC1AD845, audio+processing e namespace
BG verificati. Stremio-Core.txt incluso nel bundle, identico al notice MIT.
IPA unsigned33540315byte, SHA256
38416c171159efe7fdb402a6e2b912a2a7b8081f6c2dfa53e006bd238b283fcd,
CastBridge-0.8.1-47-unsigned.ipa disponibile nella chat. Nessun ID privato qui.

Comprende ottimizzazioni46 + parser titoli/name e ordine speciali Stremio + blocco
autoplay stagione regolare→speciali. Entro speciali e manuale conservati. Test
passati; FT001/002 da collaudare sulla serie reale, supporto ancora IMDb/Cinemeta.
Nativo47/42010715495 ancora in corso al checkpoint: acquisire risultato/artifact.
Ultimo completo46: offscreen65.184s/probe23.976/decodertrial passati, FAIL seek
212/210frame e125.125ms. CB009/021 restano aperti, pipeline media invariata in47.
Nessuna garanzia di consumo/buffering/continuità fisica da test simulatore.

Residui di sviluppo: contesto origine app/scheda/PWA nel contratto handoff;
personalizzazione tema/accessibilità, eccezioni e profili conversione; canale
release stabile per updater. Sync account e installazione SideStore in-place da
collaudare. Ranking sorgenti, salto10/15/30/60s, cache clear e priorità sottotitoli
interni/esterni/solo esterni già presenti (inventario issue aggiornato).
Priorità successiva: CB009/021 seek, poi fonti sottotitoli originali e collaudo
background/buffering/energia su iPhone+TV. Non chiudere quei criteri senza prove.

---

# Iterazione47 — episodi compatibili Stremio e confine speciali

Base6591e9d, include patch120adda parser e ordine speciali, test42009722543 passati.
Nuovo: autoplay da stagione regolare non entra negli speciali; navigazione manuale
conservata e autoplay speciale→speciale consentito con data trascorsa. Stremio Core
next_video è il riferimento, senza importare tutto il runtime Rust. La politica
conservativa per data assente resta invariata. Licenza MIT aggiunta alle risorse
app della IPA. App/estensione47. Test nuovi, build iPhone/native ancora da eseguire.
Ultima IPA consegnata46; non dichiarare47 pronta prima di acquisirla. Registro
issue1 commento avvio47; FT001/002 restano da collaudare con sorgente reale.
CB009/021 seek, CB014 energia, CB001 background fisico ancora aperti.

---

# FT-001 — patch Stremio Core verificata nei test, commit120adda

Workflow42009722543 SUCCESSO: alias name/titolo assente/priorità title, ordine
speciali, navigazione, policy/diagnostica e typecheck SDK. Issue #1 aggiornata.
Patch in PR separata dal branch test verso fix, draft; non ancora nella IPA46
energetica. Prima della nuova IPA aggiornare build oltre46. Collo di bottiglia
reale Cinemeta/rete e fonte utente da collaudare; non dichiarare risolto il suo
caso. Autoplay con data assente resta conservativo; bingeGroup già implementata.

---

# FT-001 — compatibilità Stremio Core, in verifica

Confronto con Stremio/stremio-core 3417c2e7: Video accetta name come alias di
title e titolo mancante. Il nostro decode sintetizzato richiedeva title per ogni
voce, invalidando tutto il catalogo anche con un solo episodio senza titolo.
Parser Swift ora compatibile; ordinamento stagione zero in fondo come upstream.
Attribuzione/licenza MIT in ThirdPartyNotices/Stremio-Core.txt. Test sintetici per
alias, assenza titolo e ordine speciali. Da eseguire CI; nessuna prova della fonte
privata né garanzia che il suo errore di rete/catalogo sia risolto. Stessa bingeGroup
già usata per la sorgente successiva; non importato l'intero core Rust.

IPA46 resta la candidata energetica già compilata: questa patch successiva va
verificata prima di incorporarla in una nuova IPA. Mantenere confronto A/B 45/46.

---

# Build 46 pronta — CB-014 implementato, consumo fisico da verificare

Commit prodotto: 9127bddf7f0368761ed6eab6505f4fc1835833af, PR #2 draft.
Build iPhone 41993979997 e policy/SDK 41993980048: SUCCESSO. IPA unsigned
CastBridge-0.8.1-46-unsigned.ipa, 33537710 byte, SHA256
 aeb1c479ffe662b197847dc2683ab5bb3c724fdf297441f0531c499b4dc81d56.
App ed estensione 0.8.1 (46); background audio/processing e namespace BG verificati.
File disponibile nella chat; nessun identificatore privato da pubblicare qui.

Nativo 41993979995: compilazione/regressioni passate, report completo raccolto
(artifact 13399957680). H264 offscreen 65.184s / 7536313 byte, pausa/ripresa e
cleanup PASSATI. Now Playing, sessione primaria e rilascio preparazione PASSATI.
sourceCadenceProbe: 23.976023976 fps, fixed=true, PASSATO sul backend incorporato.
Trial decoder: entrambi 96 frame, identità e tempi corretti, SSIM 1. CPU processo
simulatore 5.726s baseline / 4.073s richiesta VT: dato esplorativo, ordine fisso,
non misura batteria e non prova hardware. Decoder della IPA resta invariato.
Suite nativa complessiva FAIL al difetto preesistente seek: 212/210 frame,
gap 125.125ms, identità iniziali 73,73,77,77 invece 79. CB-009/021 ancora aperti;
nessun gate allentato. Il fallimento non riguarda le policy energetiche nuove.

CB-014 IMPLEMENTATO_DA_VERIFICARE; issue #1 aggiornata con codice, prove e limiti.
Prossimo passo: confronto fisico 45/46 stesso video/tracce/rete/durata e schermo,
conferma pausa/seek/cambio app/blocco e nessun lavoro dopo stop. Nessun risparmio
percentuale o correzione del seek dichiarati. Vedere Docs/ENERGY.md.

---

# CB014 — ottimizzazioni batteria build46, 2026-11-05

Ridotti gli aggiornamenti ridondanti Now Playing (2s foreground / 10s background),
con pubblicazione immediata per comandi, seek, stato, tracce e lifecycle. Il clock
nativo avanza autonomamente. Timer salute invariato 1s con tolleranza 100ms.
Diagnostica ordinaria raggruppata 2s; errori, recuperi e flush lifecycle immediati;
nessuna riscrittura di dati invariati. Contatore writes per lancio, non I/O fisico.
Nessun cambiamento a qualità, codec, frame, soglie recupero o sessione audio.

VideoToolbox decoder soltanto CAST_ENGINE_TESTING: confronto sintetico 4s contro
baseline, CPU processo/simulatore, identità 96 frame NTSC, gap <=1.5 frame e SSIM
>=0.98. Decoder prodotto invariato. Test locale CLI dei gate passato per controllo
valido, frame mancante respinto e decoder sperimentale indisponibile. Workflow YAML
/shell validi. Policy/diagnostica Swift e build iPhone/native ancora da eseguire.
Raccolta evidenze anche in errore simctl; apertura Safari limitata a 20s senza
saltare l'asserzione offscreen. Vedere Docs/ENERGY.md per limiti e protocollo A/B.

Issue1 CB014 IN_CORSO. Archivio esatto corpo precedente verificato nel commento
6652854175 prima di accorciare la sola cronologia. Non dichiarare risparmio batteria
senza confronto reale iPhone. Ultima IPA consegnata resta45 finché46 non compilata.
CB009/021 seek ancora aperti: il gate rigoroso preesistente resta invariato.

---

# Audit batteria CB014 — 2026-11-05, nessuna modifica prodotto

Segnalazione privata di consumo da verificare mediante confronto A/B.
Non pubblicare screenshot o metriche personali della schermata Batteria.
Audit349e37a: H264VTencoder giàpresente, decoderVT nonrichiesto esplicitamente.
Profilare decodificahardware controsoftware evalidateframe/subtitle/background;
non assumere accelerazione semprepiùefficiente (copie/formati possono costare).
Timerstato1s senzataleranza, monitor50/100ms e flushlog300ms: candidati a batching
prima di abbassare qualità o indebolire recuperi. Packetcopy/fonti compatibili e
sottotitoli separati giàprioritari. Misurare stesso telefono/sorgente/durata/rete,
schermobloccato/altreapp/temperatura, A/Benergia e attivitàresidua dopoStop.
Nessun codice prodotto cambiato o risparmio verificato qui. CB014IN_ANALISI,
issuecomment6652335647 e relativo dettaglio aggiornati; corpoissue65205char,
archiviare con verifica prima della prossima append lunga preservando storia.

Nativo45/41916741542 ora conclusoFAIL: compilazione/regressioni passate, poi
CoreSimulator errore405/NSPOSIX60 aprendoexample.com pertestoffscreen; nessun
artifactraccolto. Non interpretare comeasserzionefpsfallita, ma sourceCadenceProbe
/matrice45 nonverificabili daquelrun. Commento6652369269. Serve retryjobfallito e
raccoltaevidenze anche quando simctlopenurl fallisce. Nativo44resta ultimo report
completo: controlli/configaudio eH264background PASSATI, distinto seek125msfallito.
UltimaIPAconsegnata45 noncambiata. Nessuna nuovaIPA o ottimizzazionebatteria.

---

# IPA45 pronta — framerate e player nativo, 2026-11-04

Sorgente349e37ade48e5a71be8f4e0795facbc773e8e1e8, branchfix ePR2 draft.
iPhone41916741549 SUCCESSO, artifact13365990544 estratto/verificato: app e
estensione0.8.1/build45, receiverCC1AD845, backgroundaudio+processing e namespaceBG.
IPA unsigned33533340byte,SHA256f09f626f6b253d26caba656d59cc0ab60ea2e4b739c8cb0bc78bc4d10af22cc4,
CastBridge-0.8.1-45-unsigned.ipa disponibile nella chat perSideStore. Include44.
Nessun identificatore privato della chat necessario nel repository pubblico.

Policy/SDK41916478271 PASSATI sulla logica/parser3e3f129; unica modifica dopo
349e37a rendeCFR soltanto il capfps giàprevisto. CLI6.1.1 fixtureHEVCprobe24000/1001;
H264software48/48frame/2s a24000/1001, cap60→30 produce60frame/2s. Build45 app
completa passata. Nativo45/41916741542 in corso: acquisire sourceCadenceProbe
(reale backend HEVC1080NTSC), matrice e gate esterni. Non attribuire questi test
locali al codificatore iPhone né dichiarare FPS/scatti della fonteprivata risolti.

Native44/41913763082: systemMediaControls,systemMediaSessionNonMixable,
preparationAudioMixesAfterClear tuttiTRUE; H264offscreen65.096s/7.34MB PASSATO,
pausa/ripresa/cleanup. Run complessivoFAIL al gateVLCseek212/210frame,125.125ms,
identitàiniziali73,73,77,77 invece79. Nessuna sogliaallentata. CB009/021 aperto.
CB011 e nuova patchFPS IMPLEMENTATO_DA_VERIFICARE suhardware. Ricaricare stessa
fonte: guardare metadata cadence ffprobe/fps/status eFPSUI; provare fluidità,
seek/tracce/background e player nativo (senza vecchiaActivityKitcustom).
Screenshot segnala anche catalogoepisodi indisponibile, FT001/002 ancora aperto.

Questo checkpoint sul branchtest evita unnuovo buildmain solo documentale;
integrare dopo nativo45 conHEADfresco. Issue1 resta canonica, prossima append
richiede archiviare partecronologia (corpo vicino limite65k), senza perdere storia.

---

# Framerate VLC mancante — build45 candidata, 2026-11-04

Nuova segnalazione: fpsnonrilevati perHEVC1080 e lievi scatti. UIzero non prova
FFmpeg30fps: percorsoH264 usa già passthrough.45 aggiunge FFprobe bounded solo
conmetadataVLC invalidi, razionaliavg/r, compatibilitàcodec/dimensioni, primaV
noncover, cancellazione/8s/8MiB, niente scaninterofile. Dati aUI eVideoFormat,
nessunCFRVLC seavg/nominale mancano o discordano. GOP2s arrotondato48 a23.976,
60 a29.97. Nuova policytest e proberealeHEVC1080NTSC per libreriainclusa.
Docs/VIDEO_CADENCE.md. Caso privato non acquisito: FPS e fluiditàTV da collaudare.
CB012/019/021 aperti, gateframeidentity/seek invariato. Preservare44nativeplayer.

IPA44 già pronta e salvata:app/estensione44, iPhone41913762920 SUCCESSO,
33524997byte,SHA256a1aae4f9f39eeeaf190648dd90cd439367d38abf31c1ce7b516117b2286fad59,
IPA disponibile nella chat. Consegna finale45 può sostituirla
se la nuova build è pronta; non dichiarare testhardware o IPA45 prima di averla.
Nativo44/41913763082 prosegue (cancel-in-progressfalse);45 si accoda. SDK/audio
44 passati41913225071/41913762952, probeLockScreen runtime ancora da acquisire.

---

# IPA44 consegnabile — player nativo iOS, 2026-11-04

Sorgente9ec71a96dff312bd536e9308e9577eb25158e7bd su branchfix e PR2 draft.
iPhone41913762920 SUCCESSO, artifact13363183457 estratto: app eLiveActivity44,
0.8.1, audio+processing/BGnamespace/receiverCC1AD845 verificati. IPA33524997byte,
SHA256a1aae4f9f39eeeaf190648dd90cd439367d38abf31c1ce7b516117b2286fad59.
FileCastBridge-0.8.1-44-unsigned.ipa salvato perSideStore:
IPA disponibile nella chat. Non sostituire il link con43.

SDK/policy41913225071 e41913762952 PASSATI.44 appcompilata con vere dipendenze;
checkrapidoMediaPlayer/AVAudioSession/ActivityKit controSDK iOS16.1 usa solo
helperVLCimmutato stub, non prova visibilitàLockScreen. Nativo44/41913763082 in
corso alcheckpoint; leggere risultati, in particolare systemMediaSessionNonMixable
preparationAudioMixesAfterClear/systemMediaControls e background.44 pulisce custom
pregresse e non ne crea più; BGjob di sistema resta distinto, nessuna garanzia
che iOS mostri sempre questo player quando altre app riproducono audio.

Native43/41910000713 concluso: H264offscreen65.128s PASSATO,7798457byte,
1966080byte dopo50s, pause/resume ecleanup riusciti. Run globaleFAIL al gate seek
VLC:212/210frame,gap125.125ms, immagini73,73,77,77 prima di79. Non allentare gate.
CB011 IMPLEMENTATO_DA_VERIFICARE, ancora necessaria prova fisica delplayer nativo,
progressoscrubbabile/pausa/salti, vecchia scheda scomparsa e servizioBG preservato.
CB009/021 distinto aperto. Questo checkpoint solo branchtest per evitare nuove
buildmain inutili mentre nativo44 gira: integrare dopo risultati confreshHEAD.

---

# Player nativo iOS — build44 candidata, 2026-11-04

CB011 riaperto da screenshot43: scheda progressoBG presente, vecchia ActivityKit
custom ancora mostrata e playerNowPlaying assente. Causa concreta nel codice:
CastAudioSession sempre.mixWithOthers; AppleWWDC2022/110338 richiede categoria
nonmixable per eligibilityNowPlaying. Non basta pubblicare metadata. La causa
non è la schedaBG in sé. Non pubblicare screenshot o suoi titoli/notifiche.

44: ownernow_playing anche conproducerlocale, categoria.playback nonmixable
prima di metadata; worker solo preparazione restamixable e torna tale alclear.
VecchieActivity custom chiuse all'avvio pertipoCastActivityAttributes; nessuna
nuova richiestaActivityKit, rimosse UIduplicata e opzioneinattiva. Il vecchio
bundlewidget rimane per compatibilità aggiornamenti, non viene riattivato.
Scheda BGContinuedProcessing di iOS43 conservata: non è il player multimediale.
Audio altrui può essere interrotto attivando una sessione primaria; iOS può dare
il player a un'altra app quando ne parte l'audio. Collaudare cambioapp/interruzioni.

Verifiche44: nativeprobe aggiunge assertcategoria nonmixable/metadata/seek e
ritorno mixable dopo clear conworker vivo. FastSDK typecheck classeproduzione
contro vere APIUIKit/AVFAudio/MediaPlayer/ActivityKit (soloVLChelper stub non
modificato), oltre a regressioni43. Non equivale alla visibilitàsuLockScreen.
Build44 e collaudo fisico da acquisire. Nativo43/41910000713 prosegue: workflow
nativo ora cancel-in-progressfalse conserva la cattura in corso e accoda44.
Policy/typecheckcompletoSDK iOS16.1 PASSATI41913225071; solo helperVLC invariato
stub nelcheckrapido, nessuna visibilitàLockScreen dichiarata.

---

# IPA43 pronta per collaudo background — 2026-11-04

Codice390685200eb596b1e04b5411197497bd9a23faa0 integrato in
fix/playback-recovery-20261103, PR2 draft. iPhone41910000846 SUCCESSO,
artifact13361499222: app e LiveActivity0.8.1/build43 verificate, receiverCC1AD845,
UIBackgroundModesaudio+processing, BGpermessoapp.example.castbridge.*.
IPA33535961byte, SHA25658cd10235dbb246fa137e1ef00ae1f206b3d784b0637d1d495bd6c82c46af1f6.
App senza firma/provisioning; pronta perSideStore, salvata come
CastBridge-0.8.1-43-unsigned.ipa, IPA disponibile nella chat.

Policy e veri adapterSDK passati41909937728 e41910000770. Regressioni della build
complete passate (caption/serie/Stremiomock/resolver/hosting). Nativo43/41910000713
ancora in corso al checkpoint; verificare esito reale senza cancellarlo con push
main di documentazione. Questo aggiornamento HANDOFF resta sul branchtest:
riportarlo al branchfix quando nativo43 termina. Nessuna prova hardware43.

Nativo42/41905267348: compilato/eseguito, reportcopia offscreen65.127s PASSATO
(7.67MB/byte tardivi1.84MB/pausa-ripresa/cleanup), poi gate esternoseek fallito:
212/210frame, gap125.125ms e immagini73,73,77,77 invece di79 iniziale. Gate invariato.
Il probe43 ora codifica H264vero; non confondere i due tipi di test.

Prossimo passo: installare43 conSideStore e ripetere stesso videoHEVC1080/AAC6ch,
esterni e PGS, cambio app e blocco10min. Leggere continued_submitted/active o
unavailable e background_lease_expired/continued_expired; verificare avanti TV,
recupero limitato, annullamento UI/stop senza riavvii, seek/tracce e consumi.
Controllare namespaceBG nel plist dopo firma se continued_unavailable. BGtask non
promette accessoVT/GPU indefinito: nessun entitlementGPU aggiunto. CB001/004/019
IMPLEMENTATO_DA_VERIFICARE; CB009/021 seek/cadenza resta aperto e distinto.

---

# Background locale e cadenza — build43 candidata, 2026-11-04

Prova fisica41: FFmpegAVERROR_EXTERNAL 323ms dopo background nonostante helper
attivo; retryH26441 parte e prepara nuovo flusso ma manca confermaTV nel log.
CB001/004/019 aperti; scatti non dimostrati dal solo fps di produzione. CB009/021
seek125ms/identitàframe resta aperto. Dettagli in Docs/BACKGROUND_PLAYBACK.md.

43 aggiunge BGContinuedProcessingTask iOS26+ per invio locale finito avviato in
foreground, progresso confermato TV, stessa richiesta nei recuperi/seek/cambi
traccia, ID univoco/callback tardive escluse, fail senza coda. UI di sistema può
annullare: ferma lavoro e conserva posizione, nessun rinnovo automatico. Nessun
entitlementGPU aggiunto o garanzia di continuità VT. Audio + leaseUIKit esplicita
coprono transizione; tutte le lease preparazione e syncStremio chiudono nella
scadenza prima della cancellazione. Probe65s ora H264reale, non solo copia.
Workflowbackground: regressioni policy + typecheck veri adapterSDKiOS. Build43 e
prova fisica ancora da acquisire, non dichiarare risolto da compilazione.

42 build iPhone41905267593 SUCCESSO; nativo41905267348 in corso mentre si prepara
43 nel branch test/background-processing-20261104. Non cancellare il run42 con
pushfix prematuro; poi fastforward al candidato43. Nessuna IPA42 consegnata.

---

# Consegna IPA41 e verifica42 — 2026-11-04

Su richiesta di correggere l'interruzione38, consegnata IPA0.8.1(41) per prova
viaSideStore: build41901395190 SUCCESSO, artifact13359572581, app/estensione41
verificate, 33520353byte, SHA256c3d1f5afd964c8a6ce7552aa20d5cd8e8b42254858dadba96df4995cff5cdf32.
Sorgente41 12ef7f8a44ec1be6e08525c4bea5078df6529457. Include Torna39 e priorità40.
Non dichiarare risolto il guastoVideoToolbox: manca prova iPhone/Chromecast reale.

Nativo41/41901395026 eseguito: FAIL al gate seek125.125ms con primi frame
73,73,77,77,79,81,81 controattesi79,80,83,84…; non è un nuovo errore del decoder
H264 delcaso38 né prova di guarigione background. Test precedenti e statistiche
normalizzatore eseguiti, decodifica40/captionpixel6 passati; gate non abbassato.

42 12ec7374bd6d0b2bbaff9dae8ec1663c95e7b41a integrata nel branchfix dopo41.
Header41905267933 e caption41905267587 SUCCESSO; iPhone41905267593 e nativo
41905267348 ancoraQUEUED senza step alcheckpoint20:23UTC. NessunaIPA42.
Questo checkpoint documentale è sul branchtest per non cancellare i run42 in
coda con una scrittura doc-only sul branchfix. Dopo i run, riportare nel branchfix
insieme alle relative evidenze. La issue1 è la fonte canonica dello stato.

Prossimo risultato necessario: ripetere caso38 passando adaltraapp con41; attendere
build42, leggereeventuali header_validation e verificare preservazione posizione.
Causaoriginaria/backend e rifiutoWebM restano aperti; niente promesse di attività
inRAM garantita o esecuzione continua dopo la fine di questo turno.

---


