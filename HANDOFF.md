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

