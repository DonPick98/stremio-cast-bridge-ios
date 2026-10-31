# Cast Bridge per iPhone 0.6

Cast Bridge apre sulla TV le sorgenti Stremio del proprio account Real-Debrid. La 0.6 integra MobileVLCKit di VideoLAN: l'iPhone legge le tracce reali e adatta automaticamente audio e video al Chromecast, senza server domestici o scelta manuale dei codec.

## Riproduzione

- MP4 H.264 con audio stereo compatibile: invio diretto quando i metadati lo consentono.
- H.264 in altri contenitori: adattamento del contenitore, conservando il video originale; audio incompatibile convertito in AAC stereo.
- Video incompatibile o sottotitoli incorporati: conversione H.264 tramite encoder Apple, con ripiego automatico VP8/Vorbis. Conversione fino a 1920x1080 a 30 fps.
- Audio alternativo: selezione della traccia originale prima dell'adattamento. Il Chromecast riceve la traccia scelta.
- TrueHD/MLP: componente FFmpeg integrato per i decoder assenti nel pacchetto iOS VLC; passa al motore video tramite una FIFO privata, senza scrivere l'intero film.
- Sottotitoli incorporati: rendering nel video sull'iPhone, senza hosting. Preferenze di carattere, dimensione, colore, contorno e sfondo per le tracce testuali; le immagini PGS non possono cambiare carattere.
- WebVTT esterno: traccia testo Cast, conservata in memoria e riallineata al punto scelto dopo i salti.

Prima di inviare un flusso adattato viene controllata la presenza sia di audio sia di video compatibili. I tentativi automatici sono limitati. File non disponibili, collegamenti rifiutati dal provider, DRM, file danneggiati e limiti hardware non sono risolti dalla conversione.

Il percorso normale evita la precedente conversione HLS Real-Debrid. La risoluzione delle sorgenti mantiene avanzamento, attese limitate, cache in memoria, distanziamento delle richieste e gestione distinta degli errori HTTP/RD.

## Telefono e controlli

Durante l'adattamento l'iPhone deve restare acceso sulla stessa rete Wi-Fi della TV. Il film non viene scaricato interamente: il trasferimento usa buffer limitati. Chiudere forzatamente l'app interrompe questo percorso.

Il background segue il meccanismo di riproduzione remota di VLC per iOS: sessione audio e riproduttore ausiliario silenzioso soltanto durante un flusso locale attivo, arrestati alla fine o alla disconnessione. L'SDK Cast e' configurato per il background. La prova su simulatore non certifica da sola il funzionamento a schermo bloccato su un iPhone reale.

Pausa, ripresa, volume, seek e cambio traccia nell'app. I salti nel flusso adattato rigenerano la conversione dal punto richiesto e conservano la pausa. Posizione e durata si riferiscono sempre al film originale.

La Live Activity mostra durata e avanzamento; su iOS 17+ offre pausa/riprendi, +/-30 secondi e 11 punti di salto toccabili. Non e' un cursore trascinabile. iOS 16.1 offre visualizzazione senza pulsanti interattivi.

Preferenze sottotitoli con anteprima e salvataggio automatico sul dispositivo. Dimensioni del file a destra nella scheda e nell'elenco sorgenti, quando dichiarate dall'add-on. UI minimale e icona dedicate.

## Installazione

Ogni persona configura il proprio manifest Torrentio e/o Comet; i dati personali sono conservati nel portachiavi dell'iPhone.

1. Scaricare l'artefatto CastRemote-unsigned della build riuscita ed estrarre la IPA.
2. Installarla con SideStore, conservando la versione precedente.
3. Aprire una sorgente dal bridge Stremio, collegare il Chromecast e premere Riproduci sulla TV.
4. Collaudare lo stesso MKV AC3, cambio tracce, salti, pausa e Live Activity dopo il blocco dello schermo.

L'estrattore WebVTT e SubtitleService restano funzioni avanzate facoltative. I sottotitoli incorporati renderizzati dal nuovo motore non richiedono quel servizio o modifiche al Site.

## Sviluppo

build-ios.yml compila app e Live Activity per iPhone senza firma. native-engine-probe.yml esercita l'effettivo motore iOS su simulatore con 25 combinazioni sintetiche, gateway HTTP e trasferimento in background. Le prove sono escluse dalle build di produzione.

Risultati e limiti: [HANDOFF.md](HANDOFF.md). Compilazione: [BUILD-WINDOWS.md](BUILD-WINDOWS.md). Sorgenti e licenza del motore: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
