# Preparare la IPA da Windows

Il file `.github/workflows/build-ios.yml` prepara una compilazione su un
computer macOS fornito da GitHub Actions. Si avvia solo manualmente. Il progetto
va caricato come contenuto principale di un repository separato: non inserire
nel repository collegamenti personali agli add-on, chiavi Real-Debrid, password
o certificati Apple.

Una volta eseguito il flusso dalla scheda **Actions**, l'archivio
`CastRemote-unsigned` contiene `CastRemote-unsigned.ipa`. La IPA è senza firma:
non si installa direttamente e va firmata con il proprio account Apple tramite
uno strumento compatibile, per esempio AltStore Classic o Sideloadly. La
compatibilità della firma con questa specifica IPA deve ancora essere provata.
Ogni persona deve usare il proprio account e la propria configurazione.

La compilazione e la riproduzione su iPhone e Chromecast non sono ancora state
verificate. Con AltStore Classic le app installate scadono dopo sette giorni e
devono essere aggiornate; il rinnovo richiede AltServer sul computer. Per i
repository privati GitHub Actions usa la quota inclusa nell'account e l'uso
oltre tale quota può essere a pagamento; i runner standard per repository
pubblici sono gratuiti. Controllare la quota prima di eseguire il flusso.

Riferimenti: [runner GitHub](https://docs.github.com/en/actions/reference/runners/github-hosted-runners),
[costi Actions](https://docs.github.com/en/billing/concepts/product-billing/github-actions),
[AltStore Classic](https://faq.altstore.io/altstore-classic/your-altstore).
