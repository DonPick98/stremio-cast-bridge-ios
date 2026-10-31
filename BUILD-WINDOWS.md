# Preparare la IPA da Windows

Il file `.github/workflows/build-ios.yml` prepara una compilazione su un
computer macOS fornito da GitHub Actions. Si avvia solo manualmente. Il progetto
va caricato come contenuto principale di un repository separato: non inserire
nel repository collegamenti personali agli add-on, chiavi Real-Debrid, password
o certificati Apple.

Una volta eseguito il flusso dalla scheda **Actions**, l'archivio
`CastRemote-unsigned` contiene `CastRemote-unsigned.ipa`. La IPA Ã¨ senza firma:
non si installa direttamente e va firmata con il proprio account Apple tramite
uno strumento compatibile, per esempio AltStore Classic o Sideloadly. La
compatibilitÃ  della firma con questa specifica IPA deve ancora essere provata.
Ogni persona deve usare il proprio account e la propria configurazione.

La compilazione Ã¨ riuscita il 31 ottobre 2026: l'artefatto contiene una IPA con
eseguibile iOS e librerie Google Cast. Firma, installazione e riproduzione su
iPhone e Chromecast non sono ancora state verificate. Con AltStore Classic le app installate scadono dopo sette giorni e
devono essere aggiornate; il rinnovo richiede AltServer sul computer. Per i
repository privati GitHub Actions usa la quota inclusa nell'account e l'uso
oltre tale quota puÃ² essere a pagamento; i runner standard per repository
pubblici sono gratuiti. Controllare la quota prima di eseguire il flusso.

Riferimenti: [runner GitHub](https://docs.github.com/en/actions/reference/runners/github-hosted-runners),
[costi Actions](https://docs.github.com/en/billing/concepts/product-billing/github-actions),
[AltStore Classic](https://faq.altstore.io/altstore-classic/your-altstore).


## Prova Live Activity
Installa l’IPA con SideStore e apri Cast Bridge su iPhone con iOS 16.1 o successivo. Premi **Avvia test**, poi blocca l’iPhone: dovrebbe apparire “Test Live Activity attivo”. Su iPhone compatibili verifica anche Dynamic Island. Riapri l’app e premi **Termina test**. Se il test non parte, verifica che le attività in tempo reale siano abilitate nelle impostazioni dell’app e annota il messaggio mostrato. Questa è una prova statica: non controlla la riproduzione. La firma e il funzionamento dell’estensione tramite SideStore vanno verificati sul dispositivo.
