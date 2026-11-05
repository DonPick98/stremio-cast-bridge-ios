# Sincronizzazione libreria Stremio

Implementazione indipendente del protocollo pubblicato da Stremio/stremio-core,
revisione3417c2e7ed45cdbfd86b3226f69814c2dc4947ad. Riferimenti primari:
- src/types/api/request.rs, response.rs e fetch_api.rs;
- src/unit_tests/serde/auth_request.rs (type Login, email/password/facebook=false);
- src/types/library/library_item.rs (millisecondi, video_id, _mtime, removed/temp);
- stremio-watched-bitfield/src/{watched_bitfield,bitfield8}.rs (anchor, little-endian bits, zlib/base64).
Base: https://github.com/Stremio/stremio-core/tree/3417c2e7ed45cdbfd86b3226f69814c2dc4947ad

## Comportamento

Accesso email/password, token solo nel Keychain AfterFirstUnlockThisDeviceOnly.
Password non salvata né inviata al bridge/add-on/diagnostica. Sync disattivata fino
ad abilitazione esplicita; riconnessione non abilita automaticamente. Si supportano
movie IMDb e serie IMDb con episodi canonici. Non si importano l'intera libreria,
account da altre app o credenziali da link. Per account soloSSO occorre un accesso
email/password valido; Apple/Facebook/QR non sono implementati.

In uscita si usa lastConfirmedPosition della sessione TV posseduta, ogni60s e
su pausa/background/stop/cambio sorgente. Target seek, progresso UI predetto e
buffering non sostituiscono il clock confermato. Visto soltanto su fine naturale
con posizione vicina alla durata; non su semplice seek o timeout. Il titolo è
inviato solo all'API di libreria dell'account, mai alla diagnostica.

La lettura del punto remoto avviene alla selezione della sorgente e richiede
video_id corrispondente, _mtime più recente e nessuna modifica locale in coda.
Progressi locali storici senza timestamp vengono conservati: non se ne presume
l'anzianità. Si può disattivare l'import del punto remoto separatamente. I visti
esistenti sono conservati e aggiornati nell'account, non c'è ancora un browser
completo della libreria o un'azione manuale visto/nonvisto in Cast Bridge.

## Integrità e offline

Fetch singolo libraryItem prima di ogni Put. Campi sconosciuti, appartenenza alla
libreria, notifiche e watched remoti sono preservati. Nuove voci removed=true e
temp=true per Continua a guardare senza aggiunta automatica ai preferiti.
Bitfield little-endian, zlib livello6, parsing da destra per ID con colon; anchor
non trovato/catalogo parziale che perderebbe bit impostati blocca la modifica.
Catalogo completo include speciali anche se nascosti nella navigazione del player.

Outbox fino32 eventi, coalescenza pervideo senza perdere episodi conclusi,
protezione file UntilFirstUserAuthentication, percorso SHA256(accountID), massimo
2MiB. Una conferma obsoleta non elimina l'evento sostituito. Le ricevute dello
stato scritto sono persistenti: permettono di inviare più episodi offline senza
scambiare il nostro _mtime di upload per un conflitto da altro dispositivo.
Sono accettate solo se lo stato remoto coincide esattamente con la ricevuta.

Uno stato remoto più recente e diverso resta in conflitto: non viene sovrascritto.
Il pulsante MantieniStremio ignora soltanto gli eventi bloccati, con conferma.
Le altre voci continuano. Retry-After429 rispettato (secondi1–3600); altri errori
hanno backoff60s–15min. Riavvio/nuova riproduzione permettono un nuovo tentativo,
non c'è promessa di esecuzione persistente iOS. Nessuna sincronizzazione avviene
dopo disabilitazione/cambio account; la generazione invalida callback precedenti.
Una richiesta già accettata dal server non può essere annullata retroattivamente.
La disconnessione elimina token e coda dell'account corrente suquesto iPhone,
senza cancellare la libreria remota.

L'API non espone un Put condizionale/CAS nel contratto esaminato. Il confronto
_mtime è best-effort: una modifica fra Get e Put rimane una possibile corsa.
Non dichiarare sincronizzazione atomica fra dispositivi. Non copiare valori o
errori grezzi dell'API nei log/issue. Test usano esclusivamente identità sintetiche.

## Verifica necessaria

Testcore/URLProtocol per formato upstream, roundtrip, shift, conflitti, unità,
coalescenza, completamenti, idempotenza, ricevute e Login/Get/Put. Testnoncredenziali
non certificano il contratto effettivamente distribuito dal servizio. Richiesti
build/link iPhone, test Keychain/fileprotetto, un account di test autorizzato,
dueepisodi offline, conflitto con altro dispositivo, disabilitazione durante rete,
ripresa film/episodio e nessuna modifica ai preferiti. FT004 resta da verificare;
nessun account reale è stato usato nello sviluppo qui documentato.
