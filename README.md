# Cast Bridge per iPhone — prototipo

Progetto SwiftUI per un telecomando Google Cast dedicato al bridge Stremio. La compilazione Xcode su GitHub Actions è riuscita e ha prodotto una IPA senza firma. La firma, l'installazione e la riproduzione su iPhone e Chromecast devono ancora essere provate sul dispositivo.

## Cosa fa il prototipo

- Riceve un ticket temporaneo senza credenziali tramite schema iOS, lo invia al bridge via HTTPS e aggiorna le sorgenti sul telefono, rispettando i collegamenti vincolati alla rete.
- Legge i metadati del file dall’account Real-Debrid della configurazione personale conservata nel portachiavi dell’iPhone. Per trovare un file può aggiungere un torrent e selezionare quel file nell’account.
- Preseleziona l’audio predefinito indicato da Real-Debrid e i sottotitoli nella lingua configurata se presenti: inglese, italiano o disattivati. Un pulsante avvia la riproduzione; i menu per correggere audio, sottotitoli e qualità sono apribili su richiesta. L’audio predefinito non identifica con certezza la lingua originale.
- Usa uno stream HLS preparato da Real-Debrid con l’audio scelto e, se richiesto, i sottotitoli incorporati nel video. La scelta successiva invia un nuovo caricamento al Chromecast cercando di mantenere la posizione: funzionamento, tempi e compatibilità devono essere verificati sul dispositivo.
- Consente connessione Cast, avvio, pausa, avanzamento e volume. Se manca un sottotitolo inglese integrato, prova prima un WebVTT fornito dalla sorgente e poi il collegamento WebVTT del bridge ricavato da OpenSubtitles. Il risultato dipende dalla disponibilità e dalla sincronizzazione del sottotitolo per quel file.

Il Chromecast legge lo stream direttamente dalla rete; il telefono funge da telecomando. Continuità con iPhone bloccato, codec, ricerca della posizione e tracce devono essere collaudati realmente.

## Installare da Windows

La compilazione gratuita nel repository pubblico produce `CastRemote-unsigned.ipa`. Il file va firmato con il proprio account Apple e installato tramite uno strumento come AltStore Classic o Sideloadly; questa procedura non è ancora stata verificata con la IPA specifica. Dettagli in [BUILD-WINDOWS.md](BUILD-WINDOWS.md).

## Aprire e firmare su Mac

Servono macOS, Xcode compatibile con Google Cast 4.8.6, CocoaPods e un iPhone con iOS 16 o successivo. La versione SDK è fissata nel Podfile. Google considera CocoaPods deprecato dopo la 4.8.6; la migrazione a Swift Package Manager è da verificare su Mac.

1. Copiare questa cartella su un Mac, aprire il Terminale nella cartella ed eseguire pod install.
2. Aprire CastRemote.xcworkspace in Xcode. In Signing & Capabilities scegliere il proprio team Apple e un identificativo di pacchetto unico.
3. Selezionare l’iPhone, compilare e installare. Consentire l’accesso alla rete locale quando richiesto. La distribuzione ad altri dispositivi richiede un percorso di firma e installazione appropriato, e potrebbe richiedere rinnovi; questo progetto non include certificati, profili o credenziali.
4. Nell’app, aprire Configura add-on e incollare una volta i propri collegamenti personali di Torrentio e/o Comet configurati con Real-Debrid. Ogni persona usa i propri collegamenti. Nella pagina del bridge scegliere «Cast Bridge per iPhone» come app di riproduzione e creare il proprio add-on Stremio.
5. Aprire una sorgente Chromecast dall’add-on in Stremio, collegare il Chromecast e premere «Riproduci sulla TV». Se necessario, aprire il pannello per correggere audio, sottotitoli e qualità. Verificare immagine, dialoghi, pause, avanzamento, cambio traccia e funzionamento con telefono bloccato.

## Sicurezza del prototipo

Il ticket è un collegamento temporaneo e contiene solo i metadati necessari a cercare il contenuto: non concede la chiave Real-Debrid né i collegamenti personali degli add-on. Al primo utilizzo l’utente salva i propri collegamenti nel portachiavi dell’iPhone; l’app ricava la chiave sul dispositivo e la usa per le richieste Real-Debrid, senza inviarla al bridge. Non inserire collegamenti personali in log, segnalazioni o screenshot. Lo schema URL personalizzato può essere rivendicato da un’altra app: una futura versione con Universal Links può rendere più affidabile l’apertura della nostra app.

## Verifica ancora necessaria

Il progetto Xcode e le firme SDK hanno superato la compilazione su GitHub Actions. Firma, installazione e tutte le funzioni richiedono una prova reale. Google Cast standard non garantisce la scelta diretta delle tracce incorporate in qualsiasi MKV; qui il meccanismo proposto è la conversione di Real-Debrid, non la selezione nativa delle tracce sul ricevitore.
