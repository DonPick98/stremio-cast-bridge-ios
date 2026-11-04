# Checkpoint sottotitoli — 0.8.1 (30), 2026-11-04

Sorgente applicativa241be82673344f4755f0ccd48c58ba5a01163489; test/workflow
d55b0a870986baad03a1ea97bdbeb2a9fbd09c1f. Stesso branch/PR2 draft.
CB022/023 IMPLEMENTATO_DA_VERIFICARE; CB005/010 storici ancora IN_ANALISI.
CB009/021125ms ancora aperti; nuovo gate nativo NON rimosso o allentato.

Verifiche richieste, tutte ancora QUEUED senza runner assegnato al checkpoint:
- documenti/cache/trasporto/preferenze: https://github.com/DonPick98/stremio-cast-bridge-ios/actions/runs/41858736236
- build iPhone: https://github.com/DonPick98/stremio-cast-bridge-ios/actions/runs/41858736480
- integrazione nativa: https://github.com/DonPick98/stremio-cast-bridge-ios/actions/runs/41858736286
Non dire che hanno passato test, compilazione o creato una IPA30. Swift/Xcode
non disponibili localmente; controlli locali solo revisione del diff e whitespace.
Una nuova failure sul noto salto125ms resta distinta da eventuali regressioni
caption; leggere report, test documenti e sei pixel check senza inventare esiti.

Documenti completi: SRT senza separatori normalizzati in battute distinte;
numeri nei payload non indicizzati conservati. WebVTT vuoti/intestazione falsa/
battute malformate respinti prima di sostituire la scelta. Le finestre di silenzio
incrementali restano valide in CaptionDocument. La cache persistente esistente
valida all'accesso e scarta file vuoti/malformati senza cancellare tutta la cache;
put invalida non rimpiazza documento valido. Stessa regola per estrazioni complete
integrate e download, ma il caso storico vlc_3 era overlay con codec sconosciuto.

Esterni fonte: lingua preferita salvata + alias/regioni, lingua effettiva passata
a PlaybackPreferences; off e scelte manuali preservati, niente ripiego in altra
lingua. Handoff privo di lingua mantiene precedente default inglese.
Retry riuscito pulisce cache negativa; log formato/limite conserva provenienza
in kind e motivo in result. Nessun URL/testo/token nuovo nei log.

Test aggiunti: formati validi, note/markup, UTF16/SRT senza separatori, file vuoti/
HTML/malformati, HTTP404/limite1MiB/HTTPS/annullamento via URLProtocol, cache legacy
e LRU/budget con documenti reali, lingue diverse dall'handoff e fallback discordanti.
Il pool macos-15-intel per il test focalizzato è documentato dal README ufficiale
actions/runner-images; al checkpoint anche questo job è in coda. Non attribuire
la coda a quote/fatturazione/outage senza evidenze.

Prima di proseguire: leggere gli esiti dei tre run, correggere eventuali failure
e aggiornare issue1. Se restano in coda, non rilanciare job duplicati. Le prime
sorgenti3f9560a/f382d3e sono intermedie: f382 ha test budget precedente, corretto
a80byte in241be82; le sorgenti applicative sono altrimenti uguali. Nessun collaudo
iPhone/Chromecast reale o soluzione generale dei sottotitoli dichiarati.

---


# Sottotitoli — build30 in verifica, 2026-11-04

Richiesta utente corrente: lavorare sui sottotitoli, prima di proseguire gli altri task.
Baseline33acb7f/build29, stesso branch/PR2. Seek CB009/021125ms resta aperto;
questa patch non lo modifica e non elimina il gate nativo.

CB022: normalizzazione SRT senza righe vuote fra battute; documenti completi
WebVTT vuoti, con intestazione falsa o timing mescolati nel payload rifiutati
prima di sostituire la selezione. Le finestre incrementali senza battute restano
ammesse in CaptionDocument: non confondere silenzio temporaneo e file completo vuoto.
Stessa validazione per estrazioni integrate complete e download esterni.
Cache complete: valida anche letture precedenti e rimuove file vuoti/malformati;
una put invalida non sostituisce il documento funzionante. Test migrazione cache.
CB023: scelta automatica esterni da lingua salvata con alias/regioni; nessun
ripiego silenzioso su lingua diversa. URL handoff senza lingua mantiene default en.
Scelta manuale resta esplicita; off rispettato. Diagnostica mantiene provenienza
Stremio/OpenSubtitles anche per formato/limite e retry riuscito pulisce cache negativa.

Test nuovi formati/lingue e URLProtocol: UTF16, SRT senza separatori, HTTP404,
HTML/WebVTT vuoti/malformati, limite1MiB, HTTPS, annullamento. Step anticipato
prima dei pod, senza ripetere gli stessi test. Build app/estensione0.8.1(30).
Swift/Xcode non disponibili localmente; attendere CI prima di dire test passati.
Il codec del primo vlc_3 e il file esterno originale restano non identificati;
non dichiarare risolta la segnalazione storica da queste patch.

---

# Esito priorità 1 — build29 sperimentale, 2026-11-04

Sorgente: 2f025546bd48afd46fd6e1ef9ec91f599af67e44, stesso branch/PR #2 draft.
Ordine operativo 1–8 nella issue #1; CB-009/021 restano IN_CORSO.
Build iPhone41845102651 RIUSCITA, IPA13330773177 realmente scaricata/ispezionata:
app/estensione0.8.1(29), audio background. SHA256 singolo IPA:
7ac49fa4ca041f9e56f6b40d2ec6b19b502ed25413262aede61bb8e881e4e28e.
Archivio SHA256e22207007704bc87c2bb7d7bccac60f83caf878fd11fcc1a74c0bdae20906c4e.
Non consegnarla come candidata completamente validata: nuovo nativo41845102602
FALLITO sul gate di continuità introdotto in questa sessione.

EAC3 originale (codec passato esplicitamente da app/matrice) evita il precedente
remux packet-copy; AAC/MP3 copiabili conservano il percorso già corretto.
TrueHD, codec assente e altre famiglie conservano normalizzazione precedente.
Nativo finale: 40 output decodificati e 6 controlli pixel passati; EAC3 seek212/210
frame, audio440.096Hz, testo corretto. Gate nuovo FALLITO:
first0, last8.925583s, maxGap0.125125s >2frame a23.976fps.
I dieci controlli qualità successivi NON eseguiti, perché il gate ferma lo step.
Non descrivere questo run come superato.

Il run intermedio41844399242 (be52b6a, più ampio) fallisce sullo stesso maxGap;
cattura scaricata/analizzata: PTS0,0.041667,0.166792,0.208500,0.250250,0.333625.
Il salto125ms è fra seconda/terza immagine; segue un salto83ms. I successivi
intervalli sono regolari. Conteggio da solo non prova integrità delle immagini:
fixture nativa nera con sottotitoli non distingue i fotogrammi visivamente.
Locale Linux: vecchio remux192/210 conprimaimmagine0.792s, decode diretto210/210
da0; NON confondere questa prova FFmpeg con il comportamento effettivo VLC iOS.
Soglie mantenute. Nessuna certificazione hardware, VFR, batteria o micro-buffering.
Ultima baseline con run nativo completo riuscito resta build28/692623c.

Prossimo lavoro, sempre priorità1: fixture HEVC/EAC3 con immagini distinguibili
nella metà superiore e fondo nero per i controlli testo; confrontare contenuto/
PTS contro sorgente al seek3.25s per separare preroll, priming audio e fps filter
prima di cambiare timestamp o tolleranze. Non eliminare/allentare il gate per
ottenere verde. Conservarne i risultati anche se la preparazione video riesce.
Evidenze finali: run41845102602/artifacts/13330809941.

Preparazione sola lettura del punto2/CB-019: binario ffmpegkit arm64 della IPA28
ha simboli esterni definiti statistics_count/at e getters frames/fps/time/elapsed/
size/speed/dup/drop. Header e wrapper ufficiali v0.11.2-ios confermano int64_t per
count/frame/size, double per time/elapsed in millisecondi e speed. statistics_at
crea un handle Statistics da rilasciare con ffmpeg_kit_handle_release; non un
puntatore prestato. Nessun binding/campionamento nuovo implementato. In futuro
leggere solo ultimo campione, con frequenza limitata e handle protetto fino al
rilascio; verificare sul nativo, non dedurre velocità CPU/banda Internet/batteria.
Non passare alle features prima di chiudere o circoscrivere il primo intervento.

---


# Lavoro in corso — priorità 1, build 29

Baseline 42b145f / 0.8.1(28), stesso branch fix/playback-recovery-20261103 e PR #2.
Ordine operativo completo nella issue #1: prima integrità/seek, poi buffering e
background, sottotitoli ancora problematici, binge-watching, sync Stremio,
Live Activity, impostazioni restanti e compatibilità/ottimizzazioni misurate.

CB-009/021 IN_CORSO: gli overlay EAC3 (oltre agli AAC/MP3 già copiabili) evitano ora la normalizzazione packet-copy prima del seek. La conversione
in AAC resta nella catena VLC; repairAudio esplicito (TrueHD) e altre famiglie audio conservano il percorso
precedente. Il codec viene passato esplicitamente dai metadati app/matrice;
assenza di metadati non abilita la nuova strada. Nessuna estensione del risultato a quel percorso o a VFR/hardware.

Riproduzione locale Linux HEVC10/EAC3, 23.976 fps, GOP48, seek3.25s:
vecchio remux produce 192/210 frame, prima immagine a0.792s; decodifica diretta
produce210/210, prima immagine0, maxgap0.041709s. Sono controlli FFmpeg locali,
NON ancora una prova della libreria VLC iOS.
Nuovo verify-overlay-seek.mjs controlla almeno98% frame, prima immagine entro
2 frame, nessun salto oltre2 frame e copertura fino alla fine. Il controllo
locale accetta la clip completa e respinge quella vecchia. I controlli precedenti
su audio/pixel sottotitoli/qualità restano tutti attivi.
Build29 iPhone e simulatore da eseguire e leggere prima di consegnare la candidata.
Nessun collaudo fisico, risparmio energetico o soluzione generale buffering dichiarati.

---

# Checkpoint 2026-11-04 - 0.8.1 (28)
Sorgente692623cf50410a7a95f132922ec5451c54b8a700,samebranchPR2.
BuildiPhone41823062443 e nuovo nativo41823062547 SUCCESS.
40output,6pixel,10quality,background65.135s PASS.
AACoverlay usaVLCaccurateseekoriginalGOP,evita+0.79s normalizzatorecopy.
ASS/SRTseek213/210frame congate98percento e audio/testo corretti.
Metadativideo assenti risoltiviaengineinspect:gateway1 95/96frame.
Non estendere risultato a HEVC/EAC3 normalizzato(192/210build27),VFR o hardware.
FT003:Preferenze accessoAspetto/anteprima+resetmiratoserie/lingue confermato;
testchiaviisolamentoPASS. Aspetto,configurazioni eprogressi nonazzerati.
IPAoutputs/CastBridge-0.8.1-build28.ipa ispezionata0.8.1/28,CC1AD845,audiobackground.
SHA2566bff8f4f39a12f6af67b29de7201469c9281588f8555ef02fbe4a88ddd806305.
Issue1aggiornata.CB009/021hardwareda verificare,FT003parziale;account/LiveActivity,
microbuffering,batteria eautoplayfisico aperti. Nessundeploysito.

---
# Checkpoint 2026-11-04 - 0.8.1 (25)
Sorgente67ea62b49940220bef0e4c2995551d8bc0f3fc59, stesso branch/PR2.
Build iPhone41818164978 e nuovo nativo41818164931 RIUSCITI.
40 output A/V,6 pixel sottotitoli,10 qualità,background65.265s passati.
ASS seek:128/210 ->192/210 frame; supera soglia90percento esistente, ma perdita
residua non risolta completamente. Non dichiarare zero frame persi o VFR garantito.
Cadenza VLC esplicita anche per interi standard riconosciuti; FFmpeg invariato.
IPA outputs/CastBridge-0.8.1-build25.ipa realmente ispezionata0.8.1/25,
CC1AD845/backgroundaudio. SHA256a279f9f4dcc8a794ec2a67dbfd1abe74999cfef002e41f994311a8d48ca1a682.
Issue1 aggiornata. CB021 implementato da verificare; hardware/microbuffering/batteria
ancora aperti. Features dello stato agente preservate, non ampliate.

---
# Checkpoint 2026-11-04 — 0.8.1 (24)

Sorgente applicativa e test: 382fdd068666dc588b7021adaaa4dab6fb789179.
Branch fix/playback-recovery-20261103; PR #2 ancora draft, non unita.

- Build iPhone e regressioni RIUSCITE: https://github.com/DonPick98/stremio-cast-bridge-ios/actions/runs/41799917398
- IPA senza firma presente: https://github.com/DonPick98/stremio-cast-bridge-ios/actions/runs/41799917398/artifacts/13306907789
  Artefatto CastRemote-unsigned, 33.013.065 byte; digest archivio SHA256
  248cc7dc0ccf1420261a3f7773044dc9df966975d6d0990b12b01c87696c8eaa.
  In questa sessione verificati esistenza, log di packaging e sorgenti Xcode 0.8.1(24);
  NON scaricato/ispezionato nuovamente il singolo IPA: ambiente locale indisponibile.
- Test passati: episodi, preferenze, handoff/catalogo, resolver, sottotitoli,
  stream locale, diagnostica, generazioni/seek e receiver; BUILD SUCCEEDED.
- Audit catture iOS RIUSCITO: https://github.com/DonPick98/stremio-cast-bridge-ios/actions/runs/41799917508
  40 output decodificati, sei controlli bitmap sottotitoli e dieci qualità passati.
  h2642997: 119/120 frame, 29,9700345 fps, SSIM 0,999003, offset costante -1 frame.
  I controlli negativi respingono sia frame rimossi sia ripetizioni con conteggio completo.
  Riutilizza catture del run 41796455819; una guardia prova identico codice applicativo
  a 40e401. NON equivale a una nuova prova del simulatore.
- Nuovo run nativo 41799917489 ancora in corso al checkpoint (build simulatore).
  Leggere esito e log prima di dichiararlo superato; i run precedenti falliti restano tali.

CB-021 IMPLEMENTATO_DA_VERIFICARE su hardware. FT-001 implementato per IMDb/Cinemeta
con collaudo fisico pendente; FT-002 e FT-003 parziali; FT-004 account/visti/progresso
non implementato. Restano da verificare continuità reale in background/blocco schermo,
Live Activity, sottotitoli esterni originali, micro-buffering e consumo batteria.
Nessun nuovo codice applicativo in questo checkpoint. Prossima sessione: controllare
41799917489, recuperare ambiente di sviluppo, poi riprendere issue #1 senza duplicare
le liste. Nessuna modifica account o pubblicazione effettuata.

---

# 0.8.1 (24) — verifica cadenza frazionaria VLC

Il run nativo build23 41793318870 ha superato report interno, 35 casi codec,
40 output decodificati, sei pixel check e background 65,139 s, ma FALLITO il
controllo stretto h2642997: 92/120 frame, fps effettivi 23,30 anziché 29,97.
Il log gateway VLC contiene ripetuti "same PTS" e rigetta i frame all'encoder.
Build24 attiva fps=30000/1001 (e analoghi NTSC riconosciuti) solo nel fallback
hardwareH264 VLC, conservando il percorso FFmpeg predefinito e le soglie receiver.
Prova locale del verificatore: clip completa 120 frame/SSIM 0,999163 accettata;
clip con frame rimossi 90 frame/SSIM 0,775184 respinta. Confronto per indice su
base temporale comune per evitare falsi negativi fra Matroska/MP4.
Il test mantiene controlli precedenti e aggiunge frame count >=98% e SSIM >0,99 con allineamento fisso massimo di un frame
per h2642997: soglia immagini più stretta; la tolleranza di startup è esplicita.
Controlli del verificatore: clip completa e ritardata di un frame accettate;
clip con 90 frame e clip con 120 frame ripetuti irregolarmente respinte.
Workflow Audit captured native media riusa la cattura iOS 41796455819 soltanto
se git diff prova identico codice applicativo rispetto a 40e401. Esegue il nuovo
audit su tutti i media reali catturati e controlli sintetici su Linux; non è un nuovo
run del simulatore e non va descritto come tale. Aggiornare cattura e guardia prima
di riusarlo per sorgenti applicative diverse. Risultati ancora da verificare in CI.
Analisi del file iOS intermedio: 119/120 frame, fps 29,9700 e SSIM 0,999003
con ritardo costante di un frame; confronto senza allineamento 0,912491. Da verificare in CI, non dichiarare
risolto il buffering utente o garantita la cadenza VFR del fallback VLC.
Il checkpoint build23 sottostante conserva la IPA iPhone e le prove effettive.

---

# 0.8.0 (23) — episodi e preferenze

FT-001: catalogo Cinemeta per ID IMDb canonici, precedente/successivo, ordine
stagione/episodio da metadati reali, nessuna invenzione degli episodi mancanti.
FT-002 parziale: autoplay serie attivo di default solo verso episodio con data
nota già trascorsa e sorgente con stesso bingeGroup. Altrimenti azione esplicita
Stremio app/web; origine originale non ancora nel contratto handoff. Non è
implementata una ricerca automatica fra fonti alternative dopo fallimento.
FT-003 parziale: area Preferenze con autoplay, continuità sorgente, speciali,
app/web di ritorno e lingue. Aspetto sottotitoli resta nella schermata esistente;
non tutte le decisioni interne sono ancora configurabili. FT-004 non implementato.
CB-020: reset annulla il task work pendente e azzera busy, anche dopo stop.
CB-018: guardia contro callback di fine ripetuti dopo fine già consumata.
Protezione autoplay anche per sottotitoli richiesti ma assenti. Preparazione
sorgente/episodio mantiene un proprietario della sessione audio e un task
background temporaneo, rilasciati su successo/errore/annullamento.
Test nuovo: ordine, buchi, cambio stagione, limiti, future/ignote date e deep link.
Sorgente: 1763600e4eea8a7bfa5cdd10fa273dc1a852f812.
Build iPhone e regressioni RIUSCITE: https://github.com/DonPick98/stremio-cast-bridge-ios/actions/runs/41793318876
IPA: https://github.com/DonPick98/stremio-cast-bridge-ios/actions/runs/41793318876/artifacts/13304711001
Pacchetto ispezionato: 0.8.0(23), receiver CC1AD845, background audio.
SHA256 IPA: cd89aa4dc8c12072a8e7a4559a62226902ea6df700635c416135599fad5f6ae9.
Test passati: navigazione/ordinamento/limiti/date, preferenze/off/auto, catalogo mock
con GET, ID sbagliato/ostile, errori HTTP e dimensione, oltre alle regressioni esistenti.
Workflow nativo esteso 41793318870 ancora in corso al checkpoint: non anticiparne
il risultato. Il precedente b780061 aveva build iPhone riuscita ma run nativo failure
con job cancelled e senza step/log; la causa non era disponibile.
Nessun collaudo fisico o integrazione account dichiarati.

---

# Build 20 — contesto diagnostico periodico

Follow-up su CB-012/018/019: contesto formato/modalità/generazione/sessione ogni 15 s
anche dopo la scadenza di prepare; modalità/generazione associate ai campioni transfer;
ID sessione corrente/precedente negli eventi di stato. Retention resta 120 s.
Test aggiunto: contesto di un guasto tardivo dopo scadenza della preparazione,
con numeri di sessione/canali mantenuti e URL esclusi. Sorgente 6c55e92c646f1b01be0660f9a34ae8981b01363d.
Build iPhone e regressioni riuscite: https://github.com/DonPick98/stremio-cast-bridge-ios/actions/runs/41717008862
IPA build20: https://github.com/DonPick98/stremio-cast-bridge-ios/actions/runs/41717008862/artifacts/13270898945
Il test di scadenza/contesto tardivo e sanitizzazione è passato. Workflow nativo
esteso 41717007554 annullato: non dichiararlo superato per build20. La modifica
riguarda diagnostica e identificazione build; il precedente collaudo multimediale
build19 rimane distinto. Nessuna verifica fisica o risoluzione del buffering dichiarata.
Non dimostra ancora la causa dei micro-buffering o un risparmio energetico.
Il checkpoint build19 sottostante conserva le prove precedenti e la relativa IPA.
Prossimo passo CB-019: verificare statistiche del produttore e loro ABI nel binario
fissato; header upstream v0.11.2-ios FFmpegKit/src/ffmpegkit_wrapper.h espone
statistics_count/at e statistiche frames/fps/time/speed. Prima dei binding Swift
accertare simboli effettivi e durata degli handle. Nessun binding ancora aggiunto.

---

# Candidata 0.7.2 (19) — recupero, seek PGS e diagnostica

Branch: `fix/playback-recovery-20261103`; sorgente candidata `cafbaa979c42024137b4e141828ffde733721def`.
Baseline: `b9a17b0` / 0.7.1 (18). [PR #2](https://github.com/DonPick98/stremio-cast-bridge-ios/pull/2).

Il recupero conserva un intento accodato durante la disconnessione, con retry limitati,
controllo del produttore fallito e rilevamento dello stallo dal clock reale. Una preparazione
fallita ripristina generazione/timeline/scelte del flusso precedente e conserva i nuovi seek
pendenti. La sessione audio e il supporto background sono coordinati fra i proprietari,
con osservazione di interruzioni, route e reset. Il callback Cast di sospensione è esportato
esplicitamente al runtime Objective-C; il test nativo deve verificarne il selettore.

I PGS usano un percorso FFmpeg diretto di overlay/H264, con fixture sintetica HEVC10,
AAC a sei canali, due tracce PGS e selezione della seconda traccia anche dopo seek.
Il riconoscimento della fine naturale richiede ownership corrente o la stessa media session.
La diagnostica conserva due minuti e aggiunge codici/errori distinti, ciclo di vita,
correlazione richieste, batteria/temperatura e byte/attese di trasferimento locale.
Queste attese non misurano direttamente la banda Internet o il tempo CPU.

## Verifiche della sorgente candidata

- [Build iPhone finale 41711298197](https://github.com/DonPick98/stremio-cast-bridge-ios/actions/runs/41711298197): RIUSCITA, inclusi i test di regressione previsti dal workflow.
- [IPA senza firma](https://github.com/DonPick98/stremio-cast-bridge-ios/actions/runs/41711298197/artifacts/13266759875): artefatto `CastRemote-unsigned`, commit cafbaa9, 32.962.495 byte. Digest SHA256 dell'archivio artefatto (non del singolo IPA): `1922d2816089cf48e4e5e16300634ef5d4d066eb6ad150393c0801f1227f4018`.
- IPA ispezionata realmente: app ed estensione 0.7.2(19), receiver CC1AD845, Bonjour coerente, background audio, icona e framework ffmpegkit presenti. SHA256 del singolo IPA: `e24521b54162dc22a070a47798ba6405e6c341e8d0fecf5e785c92c3fecdcbb5`.
- [Integrazione nativa finale 41711298250](https://github.com/DonPick98/stremio-cast-bridge-ios/actions/runs/41711298250): RIUSCITA. Passati 35 casi codec, 40 output A/V decodificati indipendentemente, sei controlli pixel sottotitoli (PGS da zero/dopo seek inclusi) e dieci controlli stretti di qualità/cadenza/audio/seek, incluso confronto esatto dei frame del video 1080p copiato.
- Callback generico: `castSuspendProtocol=true`, `castSuspendDelegate=true`, selettore `sessionManager:didSuspendSession:withReason:`.
- Prova offscreen: 65,070 s, 7.274.169 byte letti esternamente, pausa/ripresa confermate e arresto pulito. Non certifica iOS su hardware fisico o il blocco schermo.
- [Evidenze native](https://github.com/DonPick98/stremio-cast-bridge-ios/actions/runs/41711298250/artifacts/13269276761): report, media sintetici e controlli decodifica/qualità. Nessuna sorgente o credenziale personale utilizzata.
- Prova locale FFmpeg Linux della fixture PGS: bitmap assente/presente/assente dopo seek 3,25 s, uscita H264/AAC stereo. Non sostituisce il test della libreria iOS fissata nel progetto.

Un test intermedio non tipizzato ha scelto il callback specifico GCKCastSession,
mentre il controller usa quello generico GCKSession con lo stesso nome Swift.
La risposta false non provava quindi l’assenza del callback generico corretto.
Il tentativo 29fa336 ha fallito la compilazione associando il selettore Cast al parametro
generico. La candidata cafbaa9 ripristina il selettore generico coerente e verifica
sia che il protocollo SDK lo dichiari sia che la classe risponda: entrambi true nel run
finale riuscito. Vedere la rettifica CB-015 nella issue e non riapplicare l’equivoco.

## Verifiche residue e ripresa

Nessun collaudo fisico iPhone/Chromecast o miglioramento della batteria è dichiarato.
Il codec vlc_3 della prima sorgente resta sconosciuto; una sorgente successiva è confermata
HEVC/AAC6/PGS e fallisceva dopo seek sulla 0.7.1. Gli snapshot durante lo stallo a 146,376 s
continuano: non provano una rimozione dalla RAM. Il recupero dopo circa 45 s coincide con
il vecchio timeout; il ritorno all'app non è prova sufficiente della causa. Restano da
identificare le cause dei micro-buffering e dell'errore degli esterni della fonte.

Leggere la issue #1 corrente, quindi collaudare su hardware: PGS da zero/dopo seek,
rollback del cambio traccia, ripresa dopo disconnessione/stallo, cambio app/blocco schermo,
interruzioni audio, controlli di sistema e fine naturale. Raccogliere la nuova diagnostica
di due minuti dopo un problema e misure energetiche confrontabili per ciascuna modalità.
Il registro CB-019 annota il limite residuo degli snapshot di modalità/formato dopo la
scadenza dell’evento prepare e la necessità di misure più complete del produttore; CB-018
richiede anche evidenza della media session del receiver nel caso fisico.
Le features FT-001–004 sono registrate ma non implementate. Conservare gli stati e i limiti
nella issue; non chiudere le voci solo perché i workflow sono verdi.

---

# Registro condiviso e baseline iniziale — 2026-11-03

Prima di riprendere il progetto, leggere [AGENTS.md](AGENTS.md) e il
[registro canonico dei problemi, issue #1](https://github.com/DonPick98/stremio-cast-bridge-ios/issues/1).
Il registro contiene bug e backlog Features aggiornati nella issue con evidenze, priorità, criteri di accettazione
e istruzioni per aggiornarle durante ogni sessione. Il numero delle voci può crescere:
consultare sempre la issue corrente.

Baseline analizzata: **0.7.1 (18)** sul branch **native/embedded-media-engine**,
commit **1e1965632597594ab6a6574f70732ba3e9d15560**. Il branch main è ancora
basato sulla **0.7.0 (17)**. Verificare versione e HEAD attuali prima di lavorare.

L'utente segnala interruzioni durante il normale uso di altre app, sottotitoli
integrati non funzionanti, errore con esterni della fonte e scomparsa dei controlli.
Il log del 2026-11-03 mostra una perdita della sessione con uscita FFmpeg -32,
recupero ritardato e quattro preparazioni overlay fallite per vlc_3. OpenSubtitles
funziona. La causa iniziale dell'interruzione e il codec di vlc_3 restano da accertare.

Il primo checkpoint documentale aveva salvato diagnosi e istruzioni di continuità,
senza modifiche funzionali. La candidata e le verifiche successive sono descritte
in apertura; consultare sempre la issue corrente per gli stati aggiornati.

---

## Checkpoint storici

Le sezioni seguenti sono conservate come storia delle verifiche dichiarate nei
checkpoint precedenti. Non certificano automaticamente la baseline 0.7.1 o build successive.

# Technical checkpoint: Cast Bridge 0.7.0 (17) - FREE receiver

## Current user decision

Use Google's Default Media Receiver (CC1AD845). The delivered app requires no
Google Cast developer registration, payment, new receiver hosting or Sites change.
The optional Receiver/ experiment is inactive with the default build configuration;
do not make its registration or publication a prerequisite for this release.

## Validated source and artifact

Application source: 3347dd93738202e7de6b163dc5684ff130010582.
Production build: https://github.com/DonPick98/stremio-cast-bridge-ios/actions/runs/41359477925
Native integration: https://github.com/DonPick98/stremio-cast-bridge-ios/actions/runs/41359477933
Unsigned IPA SHA256: bc98bd6521ae53c5baccd7d14297b9a8db32e7527937caecd373f0ebdb151f69.
The actual IPA plist was checked: 0.7.0, build17, receiverCC1AD845, matching Bonjour,
background audio mode, icon, ffmpegkit framework and activity extension.

## Free subtitle route

Embedded text tracks are selected using FFprobe's actual stream index with codec/
language validation, then exported by the pinned FFmpeg library to complete WebVTT.
Extraction is cancellable, has a 120-second deadline and a 1 MiB output limit, and
uses the existing remote-playback audio mechanism while preparing in background.
Six complete documents can be cached for the current source; changing source
invalidates workers and cache. Never pass a bounded 90-second window to the
standard receiver as though it were a complete movie subtitle.

The movie can start/continue while text is prepared. Pending/failed text does not
trigger a subtitle burn or stop video. An extraction failure stays a subtitle
error with retry/alternative subtitle choices. Actual bitmap tracks retain the
compatibility overlay path and its recovery.

Attaching a new, unregistered text track can require one video LOAD at the retained
position. Previously registered off/on and fine delay variants use active track IDs.
Arbitrary-language changes with zero reload are not guaranteed by the free route.
ASS/SSA becomes standard text; original ASS styling is hidden in the free UI.
Appearance and synchronization preferences remain persistent. Source-provided
subtitles and the existing Stremio/OpenSubtitles catalogue remain available.

Non-overlay conversions prefer FFmpeg/VideoToolbox to retain timestamps and frame
cadence; compatible video still uses packet copy. AV1 uses VLC because the pinned
FFmpeg build did not deliver valid decoded AV1 video on the tested platform.
Do not treat a successful process exit or metadata alone as valid video.

## Completed checks and acceptance gap

Both workflows succeeded. The native report passed 33 codec cases, five gateway
scenarios, 38 independently decoded A/V outputs, four timed caption-pixel checks
and ten strict video-quality/audio/seek checks. VP8 and AV1 each delivered 144/144
expected frames. Six ASS/WebVTT windows, two complete-document exports including a
late cue beyond 90 seconds, attached font bytes, cancellation and caption gateway
checks passed. The offscreen transfer/pause/resume/cleanup probe passed (65.08s).
Receiver experiment also has 14 Node tests and real browser rendering evidence,
but it is not part of the selected free activation path.

The new IPA has not yet been validated on the user's physical iPhone/Chromecast or
with that phone locked. The earlier physical standard-receiver tests do not prove
the new sender UI or private sources. Do not interrupt a movie for synthetic tests.
Use the local >_ diagnostics after actual failures; never commit personal source
manifests, Real-Debrid URLs/tokens, certificates or profiles.

---
## Historical 0.6.4 checkpoint (superseded where it conflicts with the above)

# Technical checkpoint: Cast Bridge 0.6.4 (14)

## Source and validation

Validated media-engine and controller source: d56b76bd27932bdb210fcefb7a2dd83ddc793c8f.
Native integration: https://github.com/DonPick98/stremio-cast-bridge-ios/actions/runs/41346105625
Candidate production compile and regression tests: https://github.com/DonPick98/stremio-cast-bridge-ios/actions/runs/41346105595

VLC 3's avformat demux exposed FFmpeg SUBRIP as undf after a seek. The overlay route now uses native Matroska demux for repaired inputs carrying subtitles. VLC 3 also refuses native Matroska on unseekable input. RewindableInputStream therefore adapts only the private loopback producer with an 8 MiB buffer and 2 MiB history through VLCKit's supported InputStream callback API. The callback advertises seeking with FASTSEEK=false, so the parser can revisit clusters without scanning to the movie end. Full buffers suspend the input task; trimming resumes it, and stop wakes blocked readers/writers. Both workflows test rewind, forward seek, byte continuity, EOF and blocked read/write cancellation before building. Other playback routes retain their prior demux. Initial default text selection now runs the same indexed extraction preflight as a manual selection; status callbacks cannot preempt it with an overlay. In-file captions in the selected language take priority over external source captions.

The native suite covers 31 actual-gateway codec cases, five gateway scenarios and ten strict video-quality/audio/seek cases, with 36 decoded baseline outputs. Two cases select the second subtitle and 440 Hz alternate audio, start at 3.25 seconds and require visible SRT/ASS captions only at the correct output time (checks at 1/4/7 seconds). This replaces reliance on the old seek fixture whose only cue had already elapsed. Caption integration retains 21 timing variants and the offscreen transfer probe retains delivery pause/resume and worker shutdown checks.

Automatic overlay recovery retains the user's language preference and exposes a persistent warning on the main screen. Only explicit UI subtitle choices write preferences; programmatic representation changes and recovery do not trigger the picker callback. The controller toggles already registered text captions through EDIT_TRACKS_INFO, without pausing/replacing the producer, changing the timeline or issuing LOAD. Re-selecting the cached embedded text reuses that representation. A different, unregistered text caption still requires LOAD; arbitrary-language switching without reload remains open.

The prior guarded physical Chromecast test verified one video with 21 text tracks and three delay switches without replacing the media session. It did not validate this version's iPhone UI or exact private subtitles. The latest read-only Wi-Fi check observed the user's video advancing; it was not interrupted to run synthetic tests.

## OpenSubtitles and Stremio

SubtitleCatalog uses the same official opensubtitles-v3.strem.io add-on as Stremio, through the documented subtitles resource. It includes the exact content ID and optional filename, byte size and OpenSubtitles hash. The hash uses two validated 64 KiB ranges; it never downloads the movie merely to identify subtitles. Results retain language, subtitle filename, release and optional FPS. Exact episode names are ranked above conflicting episode/pilot names. FPS similarity is a hint, never an automatic speed conversion.

Source-provided external tracks appear alongside online results. The app retains embedded-track discovery. It can unwrap a Stremio localhost subtitle-conversion URL only to its HTTPS upstream and performs its own bounded text conversion. It cannot read a subtitle selection already made in a separate Stremio player unless the source/handoff supplies that information.

SubtitleDocument handles SRT, ASS text and WebVTT with size limits and encoding checks. WebVTTTimeline applies delay and the original-media seek offset exactly once, clips elapsed cues and shifts inline timestamps. External caption text is served only to the selected receiver by the existing private gateway.

## Timing and state

The UI offers half-second steps, five-second steps, reset and a coarse slider up to +/-300 seconds. The delay is saved per film/episode, source and caption. SubtitleWindow provides 21 immutable half-second track variants within +/-5 seconds of its center, allowing fine changes through active track IDs. Coarse changes outside that window coalesce before rebuilding the stream at the retained position. Burned overlays use VLC's subtitle delay API.

Requests arriving during subtitle acknowledgements retain queued seeks. Latest choices and timing are applied after acknowledgements; stale downloads and source generations cannot publish into later selections. Failed subtitle changes do not overwrite the last functioning source while downloading an alternative.

Supported indexed MKV text tracks are extracted by the exact selected subtitle ordinal with a 12-second preparation deadline. Unsupported compression, missing indexes, graphical subtitles and incomplete cue metadata can require the overlay fallback. Indexed extraction is best effort and is not a guarantee of complete captions for arbitrary MKV files.

Out-of-range or completed saved positions restart instead of clamping playback to the final second. Unscoped old per-file resume keys are not migrated into a new content identity. Actual raw receiver time must advance before an autoplay LOAD is considered started; paused loads do not require movement. Persistent overlay buffering triggers explicit recovery without the failed subtitle. Other persistent local buffering has a bounded retry and a visible error rather than endless automatic reloads.

## Diagnostics and acceptance

The local ten-minute diagnostic report still excludes credentials, URLs, titles and subtitle content. New events include track codecs, catalogue/download stages and the requested delay. Numeric raw receiver position is recorded separately from the estimated position.

Physical iPhone UI, long locked-screen playback and synchronization of privately sourced content remain user acceptance checks. The protocol test does not certify the exact private video or subtitle release. Keep the phone powered and on the receiver network for local serving/conversion. See THIRD_PARTY_NOTICES.md for pinned LGPL media dependencies and relinking information.


## Ripresa locale 2026-11-04 - build25 in verifica
Branch fix/playback-recovery-20261103, sorgente 67ea62b49940220bef0e4c2995551d8bc0f3fc59.
Nuovo nativo build24 41799917489 fallito su caption_ass_seek,128/210 frame.
Log scaricato work/build24-native conferma same PTS su ~24fps dopo seek.
VLC cadenza esplicita estesa a interi standard riconosciuti oltre NTSC; FFmpeg invariato.
Test aggiornati 24/25 e non standard; versione0.8.1 build25.
CI produzione41818164978, nativo41818164931: controllare entrambi prima di consegna.
Issue1 aggiornata CB021 IN_CORSO. Nessuna nuova verifica fisica.

## Build27 in verifica - 2026-11-04
HEAD9683dca2c99cf5fe80c99d8c5d60ad5ff9de4465; stesso branch/PR.
CB009/021: cattura25 gap iniziale0.80s, framecontinui dopo. Riproduzione locale
FFmpeg packetcopy seek3.25:primaimmagine0.792s. Nuovo originalOverlay perAACstereo
senzaaudioRepair usaVLC seekaccurato sulfileoriginale, evita normalizzazionecopy.
ASS/SRTseek framegate98percento (precedente90). Nuoviworkflow41820877481/41820877421
in corso. Build26preferenze include aspetto+resetmiratoserie/lingue con testisolamento;
run26annullati perché superati. Nessuna nuovaIPA consegnata ovalidazionefisica.

## Build28 in verifica
HEAD692623cf50410a7a95f132922ec5451c54b8a700.
Build27 native41820877421 FAILED gateway1 hardwareH26464/96frames.
NewASS/SRTseek213/210 andall6pixelchecksPASS with98percentgate.
HEVC/EAC3normalizedseek still192/210; unresolveddifferentpath.
Engine nowinspectsformat ifoptionalvideo absent beforeVLCchain; appmetadatareuse.
Build28CIpending; do notdeliver27asfullyvalidated. FT003features included.
