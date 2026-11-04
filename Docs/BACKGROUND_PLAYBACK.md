# Trasmissione locale in background

La prova fisica 0.8.1(41), 2026-11-04 20:31:36.807 UTC, mostra FFmpeg
AVERROR_EXTERNAL 323 ms dopo il passaggio in background. L'helper audio era attivo.
La ripartenza H26441 viene preparata, ma il log termina prima della conferma TV.
Non dimostra una terminazione dell'app per memoria né la causa specifica VideoToolbox.

## Build43: lavoro dichiarato al sistema

Su iOS26+ una trasmissione locale di durata nota avviata in primo piano richiede
BGContinuedProcessingTask, prima della preparazione del flusso. Lo stesso lavoro
rimane durante seek/cambi traccia/recuperi dello stesso contenuto, con ID univoco
per escludere callback tardive. Strategia fail: nessun video differito in coda.
Il progresso usa solo la posizione confermata dalla TV, non stime o seek richiesti;
non regredisce e non dichiara completamento prima della fine naturale.
La UI di sistema può mostrare il lavoro e permette di annullarlo. Annullamento o
scadenza interrompono il lavoro locale e conservano la posizione: nessuna nuova
richiesta automatica per aggirare la scelta. Un nuovo play esplicito può riprovare.
Nessun titolo o URL personale nel titolo del task o nella diagnostica.

Info.plist abilita processing, mantenendo audio, con namespace consentito
$(PRODUCT_BUNDLE_IDENTIFIER).* e ID costruito dal bundle effettivo. Verificare il
plist dopo firma SideStore: se il namespace non coincide, il task non viene
registrato e il log riporta continued_unavailable/bundle_mismatch.
Non richiede un entitlement GPU assente dal profilo sideload; questo lavoro CPU/
rete non garantisce da solo la disponibilità del codificatore VideoToolbox.

Una lease UIKit, acquisita prima della conversione, copre la transizione e il
recupero. Finisce immediatamente alla scadenza e non si rinnova in ciclo nel
background. Anche preparazione sorgente/episodio/stream e sync Stremio chiudono
ora le proprie lease nella scadenza, prima della cancellazione asincrona.
L'audio resta condiviso per identità: il vecchio producer non rilascia il supporto
acquisito dal successore. Su iOS precedenti26 o in caso di diniego del sistema
resta questo supporto, senza promessa di persistenza indefinita.

## Verifica richiesta

Workflow background-regressions: policy su progresso confermato/NaN/limiti/seek/
recuperi e typecheck dei veri adapter con SDK iOS; build completa separata.
Il probe nativo offscreen di65s usa ora davvero ffmpegH264 anziché copia pacchetti,
con pausa/ripresa/byte tardivi e chiusura. Simulatore non equivale a hardware.
Su iPhone/Chromecast ripetere HEVC1080/AAC6ch con esterni e PGS, passare ad altre
app, bloccare per almeno10min, ripetere cambi foreground/background, controllare
continued_active, scadenze, uscita encoder e avanzamento TV; provare annullamento
nella UI di sistema, stop, seek e cambio traccia. Misurare batteria separatamente.

## Cadenza

fps del log producer è velocità elaborazione, non fps visualizzati. Nel caso41
frames/mediaSeconds è compatibile con circa24fps; mediaSeconds è arrotondato,
non una misura di jitter. Zero drop/dup FFmpeg non dimostra assenza di scatti TV.
Il seek sintetico VLC HEVC/EAC3/ASS ha ancora gap125ms e identità iniziali errate:
CB009/021 resta aperto. Non forzare30fps e non abbassare il gate per farlo passare.

Fonti primarie consultate:
- https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados
- https://developer.apple.com/videos/play/wwdc2025/227/
- https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time
- https://ffmpeg.org/doxygen/8.1/videotoolboxenc_8c_source.html
