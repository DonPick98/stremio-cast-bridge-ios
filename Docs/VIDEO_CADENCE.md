# Framerate sorgente e conversione

La segnalazione fisica43 mostra HEVC1080 con fps non rilevati e lieve scattosità.
La metadata iniziale leggeva soltanto i campi framerate/denominatore di VLC.
Se VLC restituisce0, il dato non veniva recuperato. Questo non dimostra da solo
che FFmpeg stesse producendo30fps: fps delle statistiche è velocità di lavoro,
mentre fps_modepassthrough conserva i timestamp ricevuti dal demuxer.

45 aggiunge FFprobe solo quando il datoVLC è mancante/non valido. Usa la libreria
già inclusa, prima traccia video non copertina, conferma codec/dimensioni contro
VLC, legge avg_frame_rate e r_frame_rate razionali senza inventare valori.
FormatoJSON limitato64KiB, probe8MiB/analyzeduration3s, rwtimeout5s e deadline8s;
annullamento e rilascio processo/audio owner sempre gestiti. Non scansiona il
film intero e non sostituisce audio o sottotitoli. Fallimento lascia fpssconosciuti
senza bloccare la riproduzione; nessun URL o metadato testuale nei nuovi log.
La cache sorgente esistente conserva il risultato per cambi traccia/seek.

Il valore si propaga a UI, diagnostica e parametri di conversione. avg/nominale
non concordanti o uno solo presente non autorizzano il filtroCFR di VLC: non
basta un numero medio per provare cadenza fissa. Il flag fixedCadence autorizza
solo il percorso già previsto con valori concordanti, non certifica ogniPTS.
FFmpeg resta passthrough. Il GOP di circa2s ora arrotonda:23.976→48frame,
29.97→60,59.94→120 entro limiti di risoluzione, invece di troncare a47/59.

Regressioni:24000/1001, frazioni nulle/negative/nonfinite, JSONtroppogrande,
copertine, codec/dimensioni diversi, avg/nominale discordanti, nessunCFRimplicito,
GOP arrotondato. Probe nativo deve misurare fixture reale HEVC1080NTSC con libreria
inclusa. Gate esterni immagine-per-immagine/seek non allentati. Il caso originale
rimane da collaudare: riconoscere il valore non prova assenza di scatti sul TV.

Fonti primarie:
- https://ffmpeg.org/ffprobe.html
- https://ffmpeg.org/doxygen/trunk/structAVStream.html
- https://ffmpeg.org/ffmpeg.html (fps_modepassthrough)
