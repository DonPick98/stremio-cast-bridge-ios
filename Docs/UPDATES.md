# Aggiornamenti con SideStore

L'app cerca esclusivamente la latest release stabile pubblica di
DonPick98/stremio-cast-bridge-ios. Non usa gli artifact temporanei di Actions e
non installa autonomamente. L'utente preme Aggiorna con SideStore e completa
firma/installazione lì. Schema ufficiale: https://docs.sidestore.io/docs/advanced/url-schema

Una release `v0.8.2`, per esempio, deve contenere una IPA e questo asset
`cast-bridge-update.json` (valori SHA/build e versione devono derivare dall'IPA):

```json
{
  "version": "0.8.2",
  "build": 36,
  "minimumIOS": "16.1",
  "bundleIdentifier": "app.example.castbridge",
  "asset": "CastBridge.ipa",
  "sha256": "<64 cifre esadecimali dello SHA-256 dell'IPA>"
}
```

L'esempio non è un manifest pubblicabile: sostituire hash e numeri con quelli
verificati nell'IPA. Il digest dell'asset restituito da GitHub deve coincidere.
Si controllano URL esatto repository/tag/nome, univocità degli asset, versione e
build numeriche, OS minimo, bundle canonico e dimensioni. Il bundle canonico
rimane quello del progetto anche se il servizio di sideload modifica gli ID di
firma. La continuità dell'installazione dipende da SideStore, account e firma;
va collaudata su iPhone con conservazione dei dati prima di segnare FT005 verificato.
Il confronto digest riguarda i metadati di release, non una verifica locale dei
byte dell'IPA o della firma. Nessuna release è creata da questa implementazione.

Prima di pubblicare: attendere i gate previsti, estrarre e leggere Info.plist di
app/estensione nell'IPA, confrontare versione/build/OS/bundle, calcolare SHA256,
caricare gli asset, verificare il digest GitHub e provare aggiornamento su una
installazione SideStore di test. Conservare possibilità di installazione manuale.

Il controllo automatico è disattivato inizialmente. Quando attivo, avviene in
foreground all'apertura, al massimo ogni24h (anche fra riavvii). Il controllo
manuale è sempre disponibile, con una sola richiesta di verifica alla volta.
Le chiamate non contengono credenziali personali e non scrivono i risultati nei
log di riproduzione. Il tasto installazione è disponibile solo dopo metadati
coerenti. Mancanza rete/404/release legacy incompatibile non offrono una IPA.
