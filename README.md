# Cast Bridge per iPhone 0.3

Telecomando Stremio / Real-Debrid per Chromecast classico. Installazione con SideStore su iPhone; compilazione senza firma su runner standard macOS di GitHub Actions in repository pubblico, senza credenziali Apple o token personali.

## Riproduzione

L'app riceve un ticket temporaneo da Stremio e recupera le sorgenti con i manifest personali conservati nel portachiavi dell'iPhone. Ogni persona configura Torrentio e/o Comet con il proprio account Real-Debrid.

Il percorso predefinito invia il file originale direttamente al Chromecast. Il telefono non trasferisce il video e puo' essere bloccato. La risoluzione e' quella reale della sorgente selezionata: scegliere una fonte 1080p per avere 1080p senza conversione. L'app non ridimensiona il file originale e non abbassa automaticamente a 720p.

La modalita' compatibilita' e' esplicita e usa la conversione Real-Debrid per audio alternativi o sottotitoli impressi nel video. Preferisce 1080p quando disponibile; puo' avere ritardi e buffering. I sottotitoli esterni WebVTT sono preferiti nel percorso diretto. Il fallback inglese e' fornito dal bridge tramite OpenSubtitles: disponibilita' e sincronizzazione dipendono dal file.

## Controlli

Pausa, ripresa, avanzamento e volume nell'app. Stato Cast effettivo, timeout di avvio e conservazione locale dell'ultimo minutaggio valido per sorgente. Le chiavi di ripresa sono hash dell'identita' del file, senza URL personali. Un cambio di tracce o modalita' ricarica il video dal punto conservato.

La Live Activity mostra titolo, stato e avanzamento. Su iOS 17+ offre pausa/riprendi e salti di 30 secondi tramite AppIntents. Il comando attende la disponibilita' della sessione e l'esito Cast; se fallisce, l'attivita' invita ad aprire l'app. Lo stato viene marcato non aggiornato dopo 60 secondi senza aggiornamenti. Esecuzione a schermo bloccato, riconnessione e autorizzazione iOS richiedono collaudo sul dispositivo; la sola visualizzazione era gia' stata provata tramite SideStore. iOS 16.1 offre visualizzazione senza pulsanti interattivi.

## Installazione e prova

1. Scaricare l'artefatto CastRemote-unsigned dalla build GitHub riuscita, estrarre la IPA e installarla con SideStore.
2. Conservare una copia della versione precedente. Inserire nell'app i propri manifest Torrentio/Comet se necessario.
3. Sul bridge personale scegliere Cast Bridge per iPhone e installare il relativo add-on Stremio.
4. Aprire una sorgente Chromecast da Stremio, collegare la TV, controllare la risoluzione indicata e premere Riproduci sulla TV.
5. Provare un sottotitolo inglese reale, pausa/ripresa, seek e cambio modalita'. Poi bloccare iPhone e provare la Live Activity.

## Stato verificato e lavoro residuo

Le prove dal PC hanno validato video diretto MKV H264/AAC 1080p e sottotitolo WebVTT esterno sul Chromecast dell'utente. Non equivalgono al collaudo della nuova IPA. L'estrazione e l'hosting autonomo dei sottotitoli incorporati non sono ancora implementati; in compatibilita' vengono impressi da Real-Debrid. Il Default Media Receiver non garantisce selezione nativa degli audio incorporati.

Leggere [HANDOFF.md](HANDOFF.md) per risultati, limiti e istruzioni di ripresa da un altro account. Non inserire chiavi o link personali in issue, log o screenshot.
