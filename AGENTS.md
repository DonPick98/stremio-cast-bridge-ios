# Cast Bridge — istruzioni per agenti e nuove sessioni

## Registro canonico e ripresa del lavoro

Leggi e aggiorna il registro condiviso prima di lavorare e prima di terminare:
https://github.com/DonPick98/stremio-cast-bridge-ios/issues/1

Quella issue è la fonte canonica dei problemi e del loro stato, comune a tutti i branch.
Non assumere che la memoria della chat o un vecchio checkpoint descrivano lo stato corrente.
Non creare liste indipendenti che possano divergere dal registro.

## All'inizio di ogni sessione

1. Leggi la versione corrente della issue #1, questo file e HANDOFF.md.
2. Verifica branch, HEAD e versione/build nel progetto Xcode. Al checkpoint del
   2026-11-03, native/embedded-media-engine contiene 0.7.1 (18), mentre main
   contiene 0.7.0 (17). I titoli del README e i checkpoint storici possono essere vecchi.
3. Individua gli ID CB-xxx coinvolti; aggiorna il loro stato e annota branch,
   obiettivo e verifiche previste quando inizi il lavoro.
4. Se lavori su un nuovo branch, conserva questo file e il riferimento al registro.
   Verifica nuovamente la baseline prima di applicare una diagnosi storica.

## Durante il lavoro e prima di terminare

- Aggiungi ogni nuovo problema con il prossimo ID CB-xxx disponibile. Mantieni gli
  ID esistenti; collega duplicati e cause comuni senza moltiplicare lo stesso errore.
- Per ogni voce indica priorità, versione/commit, sintomo, riproduzione o timestamp,
  fatti osservati, ipotesi separate, punti del codice e criteri di accettazione.
- Aggiorna indice e dettaglio della voce insieme. Usa gli stati APERTO, IN_ANALISI,
  IN_CORSO, IMPLEMENTATO_DA_VERIFICARE, VERIFICATO, BLOCCATO o RIAPERTO.
- Prima di terminare, registra la modifica, commit/PR, controlli realmente eseguiti,
  risultati, limiti, verifiche residue e il prossimo passo. Aggiorna HANDOFF.md se
  cambiano checkpoint, build consegnata o istruzioni utili a riprendere il lavoro.
- Una patch o una build riuscita non equivalgono a una correzione verificata.
  Usa IMPLEMENTATO_DA_VERIFICARE finché manca il collaudo necessario. Spunta una
  voce solo quando i suoi criteri pertinenti sono soddisfatti con evidenza adeguata.
- Conserva problemi risolti, soluzione ed evidenze. Riapri una voce se ricompare;
  non cancellare problemi irrisolti e non riscrivere la storia come se fossero risolti.
- Rileggi la issue subito prima di aggiornarla. Integra le modifiche intervenute
  da altre sessioni, preservando tutte le voci e le relative evidenze. Serializza
  le scritture; non inviare un vecchio body che sovrascriva lavoro più recente.
- Se l'accesso GitHub non permette l'aggiornamento, dichiaralo esplicitamente e
  lascia un handoff locale con gli ID e gli aggiornamenti da riportare. Non dire
  che il registro è stato aggiornato se la scrittura non è riuscita.
- Nel resoconto finale indica gli ID trattati, cosa è stato verificato e cosa resta
  aperto. Queste istruzioni non richiedono ulteriori conferme per il lavoro già
  autorizzato dall'utente.

## Requisiti da preservare

- Il normale cambio app e il blocco schermo durante un video devono mantenere la
  trasmissione o recuperare automaticamente interruzioni recuperabili, conservando
  posizione, audio, sottotitoli e intenzione play/pausa. Distinguere esecuzione in
  background, permanenza in RAM, connessione Cast e salute del produttore.
- Il log storico non prova una terminazione per memoria. Una Live Activity non
  garantisce esecuzione continua; distinguere ActivityKit dai controlli Now Playing.
- Mantenere Chromecast esistente e Default Media Receiver gratuito CC1AD845.
  Nessun servizio a pagamento o registrazione Cast a pagamento come prerequisito.
- Preservare video e OpenSubtitles funzionanti. Un cambio traccia fallito deve
  conservare o ripristinare la riproduzione precedente.
- Non pubblicare URL personali, chiavi Real-Debrid, certificati, profili, titoli
  o testo dei sottotitoli nei log, nelle issue o nei commit. Usare codici e metriche.
- L'utente usa Windows e sideload. Distinguere test locali, CI, simulatore e
  collaudo su iPhone/Chromecast reali. Non dichiarare una IPA o una prova TV senza
  averne verificato l'esistenza o l'esecuzione.
- L'aggiornamento del registro non autorizza pubblicazioni, deploy o modifiche
  estranee al lavoro richiesto.

## Prompt di passaggio riutilizzabile

> Riprendi Cast Bridge leggendo AGENTS.md, la issue #1 corrente e HANDOFF.md.
> Verifica branch/commit/versione; aggiorna gli ID coinvolti all'inizio del lavoro.
> Aggiungi nuovi problemi con evidenze e priorità, distinguendo fatti da ipotesi.
> Prima di terminare aggiorna stato, commit/PR, controlli eseguiti, risultati e
> prossimo passo. Non segnare verificato ciò che attende collaudo; conserva la
> storia e integra gli aggiornamenti delle altre sessioni senza sovrascriverli.
