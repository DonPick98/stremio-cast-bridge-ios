# CB014 — ridurre lavoro evitabile, build46

La schermata del5novembre assegna12% delconsumo del periodo aCastBridge, con10min
foreground/58minbackground. Non misura12punti/ora né prova un eccesso. Nessuno
screenshot/titolo privato nel repository. Nessuna percentuale di risparmio promessa.

## Modifiche attive

- Health/recovery polling resta1s, monitorproducer e timeout invariati. Timer con
  tolleranza100ms per coalescenza di sistema, non un ritardo del video.
- NowPlaying: clock regolare aggiornato ogni2s foreground/10s background;
  iOS interpola elapsed/rate. Stato, titolo, durata, dispositivo, loading e salti
  di clock pubblicati subito. Pausa stabile non genera heartbeat inutili.
  Comandi/seek espliciti e lifecycle/interruzioni invalidano la coalescenza,
  compresi seek minimi in pausa. Stop/clear immediati. Sessione audio invariata.
- Diagnostica: eventi ordinari raggruppati2s anziché300ms; flush invariati senza
  dati nuovi non riscrivono il file. Errori/recuperi/memorywarning/interruzioneaudio
  persistiti subito, lifecycle e copia forzano flush. Si possono perdere fino a2s
  di ultimi eventi ordinari se il processo viene ucciso senza un avviso: non
  riguarda comandi o dati di ripresa. Retention120s/redazione/limiti invariati.
  snapshotenergy.writes conta write riuscite dell'app per sessione, non I/O fisico.
- Codec, risoluzione, bitrate, framerate, sottotitoli e flusso di rete invariati.

## Esperimento decoder, escluso dalla produzione

Solo CAST_ENGINE_TESTING può richiedere -hwaccelvideotoolbox su fixtureHEVC10bit
1080NTSC per4s, confronto con decodingbaseline e identico encoder/filtri/output.
CPUtime riguarda l'intero processo di simulazione e include altre attività; ordine
fisso/cold-warmcache e host introducono rumore. Il flag dichiara richiesta API,
non prova impiego del decoderhardware. Nessuna scelta automatica da questi dati.

Verifier indipendente:96frame attesi e identità/PTS contro sorgente, maxgap1.5frame;
se decoder richiesto produce output, stessi controlli e SSIM>=0.98 vsbaseline.
Se indisponibile si registra unavailable, non un successo hardware. Prima di
abilitarlo sul telefono servono energia A/B e prove PGS/testo/seek/background,
con fallback sicuro. Pipeline release continua a usare il decoder validato.

## Verifiche e limiti

Policy test: minuto regolare background61→7 pubblicazioni, pausa senza scritture,
seek/resume/controlli/lifecycle immediati. Persistence test: coalescenza, nessuna
riscrittura senza cambi, errori immediati e annullamento flush obsoleto.
Il numero di chiamate evitato non è una misura di batteria risparmiata.

Nativo45 non ha prodotto report a causa di simctlopenurl timeout60. Ora raccolta
artefatti con trapEXIT anche al fallimento, transizione fuoriapp limitata20s;
l'asserzione nativa offscreen rimane obbligatoria, mai ignorata per renderla verde.
I gatecodec/frame/seek restano; CB009/021125ms giàaperto distinto da questo lavoro.

A/B fisico: stessa sorgente/tracce/durata/rete, batteria e temperatura iniziali,
assenza ricarica, medesimo schermo/altreapp e condizioniLowPower. Confrontare45/46
prima gli overhead, poi decoder solo dopo i gate. Verificare nessun lavoro dopo
stop/fine e corretti controlli sotto pausa/seek/interruzioni. Nessuna prova fisica
qui disponibile: CB014 resta IMPLEMENTATO_DA_VERIFICARE dopo build/test.


## Esito build 46

Commit 9127bdd: build iPhone e policy/SDK passati. Il confronto sintetico dei
pubblicatori produce 7 chiamate invece di 61 in un minuto regolare in background;
non equivale a una riduzione analoga del consumo totale.

Nativo 41993979995: H264 offscreen 65.184s e 7.54 MB, pausa/ripresa/cleanup e
controlli nativi passati. Probe framerate 23.976023976 passato. Trial decoder:
96 frame in entrambi, identità/PTS corretti, SSIM 1. CPU simulatore 5.726s/4.073s,
non estrapolare a batteria iPhone. Il decoder di produzione resta invariato.
La suite complessiva fallisce al vecchio seek di CB-009/021 (212/210 frame,
gap 125.125ms). La prova fisica A/B richiesta sopra rimane aperta.
