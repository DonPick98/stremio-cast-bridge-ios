# Servizio facoltativo per i sottotitoli estratti

Componente separato dal bridge Stremio esistente. Non e' pubblicato e nessun indirizzo funzionante e' incluso nella IPA. Puo' essere integrato dal proprietario del Site o distribuito come Worker Cloudflare con D1, usando i normali strumenti dell'account proprietario. Non richiede link del film o chiavi Real-Debrid.

Contratto implementato dall'app:

- POST all'endpoint HTTPS configurato, ad esempio https://servizio.example/subtitles, con `Authorization: Bearer <chiave>` e corpo WebVTT (massimo 1 MB).
- Risposta 201 JSON `{ "url": "https://servizio.example/vtt/<id>.vtt", "expires": <secondi Unix> }`. L'URL deve essere HTTPS sul medesimo host del POST e scadere entro 24 ore.
- GET anonimo del WebVTT con CORS. Chi conosce l'indirizzo casuale puo' leggere il testo fino alla scadenza. Il testo e' memorizzato nel database del servizio; non e' cifrato dall'app. Nessun link video o manifest deve essere registrato.

Per distribuire: creare un Worker con entrypoint worker.mjs, un database D1 con binding DB e applicare schema.sql al database remoto. Creare un segreto UPLOAD_TOKEN casuale (32-150 caratteri URL-safe) tramite la gestione segreti del provider; non aggiungerlo al repository. Pubblicare con HTTPS. Nell'app, Configura add-on > servizio sottotitoli, inserire l'endpoint /subtitles e la chiave. La chiave viene conservata nel portachiavi. La procedura e l'eventuale disponibilita' del piano gratuito vanno confermate nell'account di hosting scelto; questa chat non ha distribuito il servizio.

Conservazione: massimo 100 file contemporanei da 1 MB, validita' 24 ore; i GET negano sempre accesso ai file scaduti. La cancellazione fisica dei record scaduti avviene al successivo upload. Per la rimozione periodica anche senza nuovi upload configurare una pulizia pianificata del database nel provider.

Il servizio e' un componente facoltativo gia' implementato e testato localmente; non risolve la copertura degli indici MKV, PGS, effetti ASS o il cambio audio. Prima dell'uso finale serve un collaudo iPhone -> servizio -> Chromecast con il telefono bloccato.
