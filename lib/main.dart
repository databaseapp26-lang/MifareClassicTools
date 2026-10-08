import 'package:flutter/material.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';

void main() => runApp(const MifareClassicToolsApp());

class MifareClassicToolsApp extends StatelessWidget {
  const MifareClassicToolsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MIFARE Classic - Test Settore 1',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
      ),
      home: const Sector1TestPage(),
    );
  }
}

class Sector1TestPage extends StatefulWidget {
  const Sector1TestPage({super.key});

  @override
  State<Sector1TestPage> createState() => _Sector1TestPageState();
}

class _Sector1TestPageState extends State<Sector1TestPage> {
  static const String expectedUid = '90140ABA';
  static const int sector = 1;
  static const String keyType = 'B';
  static const String key = '8FD0A4F256E9';

  bool _running = false;
  String _status = 'Pronto. Premi "Test Settore 1".';
  String _uid = '';
  bool? _authOk;
  final List<String> _blocks = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test Settore 1'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _status,
              style: const TextStyle(fontSize: 17),
            ),
            const SizedBox(height: 14),
            if (_uid.isNotEmpty)
              Text(
                'UID: $_uid',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            const SizedBox(height: 8),
            const Text(
              'Settore: 1\n'
              'Tipo chiave: B\n'
              'Chiave: 8FD0A4F256E9',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 14),
            if (_authOk != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    _authOk!
                        ? 'AUTH OK — la Key B funziona per il Settore 1.'
                        : 'AUTH FALLITA — la Key B non è stata accettata dal Settore 1.',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _authOk!
                          ? Colors.green.shade700
                          : Colors.red.shade700,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            if (_blocks.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  itemCount: _blocks.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _blocks[index],
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 14,
                        ),
                      ),
                    );
                  },
                ),
              )
            else
              const Spacer(),
            if (_running) const LinearProgressIndicator(),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _running ? null : _testSector1,
              child: const Text('TEST SETTORE 1'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _running ? null : _clear,
              child: const Text('PULISCI'),
            ),
          ],
        ),
      ),
    );
  }

  void _clear() {
    setState(() {
      _status = 'Pronto. Premi "Test Settore 1".';
      _uid = '';
      _authOk = null;
      _blocks.clear();
    });
  }

  Future<void> _testSector1() async {
    if (_running) return;

    setState(() {
      _running = true;
      _status = 'Controllo NFC...';
      _uid = '';
      _authOk = null;
      _blocks.clear();
    });

    try {
      final availability = await FlutterNfcKit.nfcAvailability;

      if (availability != NFCAvailability.available) {
        throw StateError('NFC non disponibile o disabilitato.');
      }

      setState(() => _status = 'Avvicina il tag al telefono...');

      final tag = await FlutterNfcKit.poll(
        timeout: const Duration(seconds: 30),
        androidPlatformSound: false,
        androidCheckNDEF: false,
      );

      final uid = tag.id.toUpperCase();
      setState(() => _uid = uid);

      if (uid != expectedUid) {
        throw StateError(
          'UID diverso da quello atteso. '
          'Atteso $expectedUid, rilevato $uid.',
        );
      }

      if (tag.type != NFCTagType.mifare_classic) {
        throw StateError(
          'Tag rilevato come ${tag.type.name}, non MIFARE Classic.',
        );
      }

      setState(() {
        _status =
            'Tag corretto. Autenticazione Settore 1 con Key B...';
      });

      bool authenticated = false;

      try {
        authenticated = await FlutterNfcKit.authenticateSector<String>(
          sector,
          keyB: key,
        );
      } catch (e) {
        setState(() {
          _status = 'Errore durante authenticateSector: $e';
        });
        rethrow;
      }

      setState(() {
        _authOk = authenticated;
        _status = authenticated
            ? 'AUTH OK. Ora leggo i blocchi 4, 5, 6, 7...'
            : 'AUTH FALLITA. Nessuna scrittura eseguita.';
      });

      if (!authenticated) {
        return;
      }

      for (var block = 4; block <= 7; block++) {
        try {
          final data = await FlutterNfcKit.readBlock(block);
          final hex = data
              .map(
                (b) => b
                    .toRadixString(16)
                    .padLeft(2, '0')
                    .toUpperCase(),
              )
              .join(' ');

          if (mounted) {
            setState(() {
              _blocks.add('Blocco $block: $hex');
            });
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _blocks.add('Blocco $block: ERRORE LETTURA: $e');
            });
          }
        }
      }

      if (mounted) {
        setState(() {
          _status =
              'Test terminato. AUTH ${authenticated ? "OK" : "FALLITA"}. '
              'Nessuna scrittura eseguita.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (_authOk != true) {
            _status = 'Errore/test fallito: $e';
          }
        });
      }
    } finally {
      try {
        await FlutterNfcKit.finish();
      } catch (_) {}

      if (mounted) {
        setState(() => _running = false);
      }
    }
  }
}
