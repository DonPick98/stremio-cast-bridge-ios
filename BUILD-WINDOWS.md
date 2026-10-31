# Compilare la IPA da Windows

La workflow .github/workflows/build-ios.yml compila su un runner macOS di GitHub Actions. Parte al push su main oppure manualmente dalla scheda Actions. Non servono un Mac locale o credenziali Apple su GitHub.

CocoaPods installa Google Cast SDK 4.8.6 e MobileVLCKit 3.7.5. La build usa CastRemote.xcworkspace, schema CastRemote, configurazione Release, SDK iphoneos e firma disattivata. CAST_ENGINE_VALIDATION deve restare vuota nelle build per gli utenti: CAST_ENGINE_TESTING abilita soltanto le prove sul simulatore.

Prima della compilazione vengono eseguiti i test di resolver, handoff, controlli, preferenze, dimensioni, playlist, sottotitoli, servizio facoltativo, gateway HTTP e tempi WebVTT. La prova completa di conversione e background e' separata in native-engine-probe.yml.

L'artefatto CastRemote-unsigned contiene CastRemote-unsigned.ipa, con app, icona, licenza LGPL e PlugIns/CastLiveActivity.appex. Va firmata e installata con SideStore sul proprio iPhone. Le versioni precedenti sono state installate e provate dall'utente; ogni nuova versione richiede il collaudo sul dispositivo.

Non caricare manifest personali, chiavi RD, URL di visione, password, certificati o profili Apple. Le fixture contengono soltanto immagini e toni sintetici. Per ricompilare con VideoLAN modificato, leggere THIRD_PARTY_NOTICES.md.
