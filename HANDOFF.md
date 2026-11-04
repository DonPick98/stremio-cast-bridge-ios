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

