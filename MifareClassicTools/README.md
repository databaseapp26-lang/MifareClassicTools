# MifareClassicTools

Progetto Flutter per Android con supporto NFC MIFARE Classic tramite `flutter_nfc_kit`.

## Build senza installare Flutter sul PC

Il repository è predisposto per GitHub Actions.

1. Carica il contenuto del progetto nel repository GitHub.
2. Vai su **Actions**.
3. Seleziona **Build MIFARE Classic Tools APK**.
4. Premi **Run workflow** oppure fai push su `main`.
5. Al termine apri la run completata e scarica l'artifact **MifareClassicTools-APK**.
6. Estrai l'APK e trasferiscilo sullo smartphone Android.

## Verifica NFC

L'app rileva il tag e permette di verificare una singola chiave Key A o Key B su un settore specifico.

La lista `assets/keys/authorized.keys` viene mantenuta come database di candidate. Non viene eseguito automaticamente un ciclo di tentativi contro il tag.
