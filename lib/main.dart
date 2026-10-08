import 'package:flutter/material.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';

void main() => runApp(const KeyVerificationApp());

class KeyVerificationApp extends StatelessWidget {
  const KeyVerificationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MIFARE Key Verification',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
      ),
      home: const VerificationPage(),
    );
  }
}

class VerificationPage extends StatefulWidget {
  const VerificationPage({super.key});

  @override
  State<VerificationPage> createState() => _VerificationPageState();
}

class _VerificationPageState extends State<VerificationPage> {
  static const String expectedUid = '90140ABA';

  static const List<_Candidate> candidates = [
    _Candidate(0, 'A', 'A0A1A2A3A4A5'),
    _Candidate(1, 'B', '8FD0A4F256E9'),
    _Candidate(2, 'B', 'AAFB06045877'),
    _Candidate(3, 'A', 'E4D2770A89BE'),
    _Candidate(4, 'A', '1999A3554A55'),
    _Candidate(5, 'A', 'FC00018778F7'),
    _Candidate(6, 'B', '1B61B2E78C75'),
    _Candidate(7, 'A', '26940B21FF5D'),
    _Candidate(8, 'B', '888888888888'),
    _Candidate(9, 'A', 'EE0042F88840'),
    _Candidate(10, 'B', '6F4B6D644178'),
    _Candidate(11, 'B', '434F4D4D4F42'),
    _Candidate(12, 'A', '64E3C10394C2'),
    _Candidate(13, 'B', 'EE0042F88840'),
    _Candidate(14, 'A', 'FC00018778F7'),
    _Candidate(15, 'B', '75CCB59C9BED'),
  ];

  bool _running = false;
  String _status = 'Pronto. Premi "Verifica 16 chiavi".';
  String _uid = '';
  final List<_Result> _results = [];

  @override
  Widget build(BuildContext context) {
    final okCount = _results.where((r) => r.ok).length;
    final failCount = _results.where((r) => !r.ok).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verifica 16 chiavi'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 10),
            if (_uid.isNotEmpty)
              Text(
                'UID: $_uid',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            if (_results.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Risultati: $okCount OK — $failCount FALLITE',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
            const SizedBox(height: 12),
            if (_running) const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (context, index) {
                  final r = _results[index];
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        r.ok ? Icons.check_circle : Icons.cancel,
                        color: r.ok
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                      ),
                      title: Text(
                        'Settore ${r.sector} — Key ${r.type}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${r.key}\n${r.message}',
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                  );
                },
              ),
            ),
            FilledButton(
              onPressed: _running ? null : _verifyAll,
              child: const Text('VERIFICA 16 CHIAVI'),
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
      _status = 'Pronto. Premi "Verifica 16 chiavi".';
      _uid = '';
      _results.clear();
    });
  }

  Future<void> _verifyAll() async {
    if (_running) return;

    setState(() {
      _running = true;
      _status = 'Avvicina il tag...';
      _uid = '';
      _results.clear();
    });

    try {
      final availability = await FlutterNfcKit.nfcAvailability;
      if (availability != NFCAvailability.available) {
        throw StateError('NFC non disponibile o disabilitato.');
      }

      final firstTag = await FlutterNfcKit.poll(
        timeout: const Duration(seconds: 30),
        androidPlatformSound: false,
        androidCheckNDEF: false,
      );

      final uid = firstTag.id.toUpperCase();

      if (uid != expectedUid) {
        throw StateError(
          'UID diverso. Atteso $expectedUid, rilevato $uid.',
        );
      }

      if (firstTag.type != NFCTagType.mifare_classic) {
        throw StateError(
          'Tag rilevato come ${firstTag.type.name}, non MIFARE Classic.',
        );
      }

      setState(() {
        _uid = uid;
        _status =
            'Tag corretto. Inizio verifica: 1 settore alla volta...';
      });

      await FlutterNfcKit.finish();

      for (var i = 0; i < candidates.length; i++) {
        if (!mounted) return;

        final c = candidates[i];

        setState(() {
          _status =
              'Prova ${i + 1}/${candidates.length}: '
              'Settore ${c.sector} — Key ${c.type} — ${c.key}\n'
              'Avvicina/tieni il tag sul telefono.';
        });

        final tag = await FlutterNfcKit.poll(
          timeout: const Duration(seconds: 15),
          androidPlatformSound: false,
          androidCheckNDEF: false,
        );

        final currentUid = tag.id.toUpperCase();

        if (currentUid != expectedUid) {
          await _safeFinish();
          throw StateError(
            'UID cambiato. Atteso $expectedUid, rilevato $currentUid.',
          );
        }

        if (tag.type != NFCTagType.mifare_classic) {
          await _safeFinish();
          throw StateError(
            'Tag non MIFARE Classic durante la prova ${i + 1}.',
          );
        }

        bool authenticated = false;
        String message = '';

        try {
          if (c.type == 'A') {
            authenticated =
                await FlutterNfcKit.authenticateSector<String>(
              c.sector,
              keyA: c.key,
            );
          } else {
            authenticated =
                await FlutterNfcKit.authenticateSector<String>(
              c.sector,
              keyB: c.key,
            );
          }

          message = authenticated
              ? 'AUTH OK'
              : 'AUTH FALLITA';
        } catch (e) {
          message = 'ERRORE AUTH: $e';
        }

        if (mounted) {
          setState(() {
            _results.add(
              _Result(
                c.sector,
                c.type,
                c.key,
                authenticated,
                message,
              ),
            );
          });
        }

        await _safeFinish();

        // Piccola pausa per permettere al telefono di chiudere
        // completamente la sessione NFC prima della prova successiva.
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }

      if (mounted) {
        final ok = _results.where((r) => r.ok).length;
        final fail = _results.where((r) => !r.ok).length;

        setState(() {
          _status =
              'Verifica terminata: $ok AUTH OK, $fail AUTH FALLITE. '
              'Nessuna scrittura eseguita.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'Test interrotto: $e';
        });
      }
    } finally {
      await _safeFinish();

      if (mounted) {
        setState(() => _running = false);
      }
    }
  }

  Future<void> _safeFinish() async {
    try {
      await FlutterNfcKit.finish();
    } catch (_) {}
  }
}

class _Candidate {
  final int sector;
  final String type;
  final String key;

  const _Candidate(this.sector, this.type, this.key);
}

class _Result {
  final int sector;
  final String type;
  final String key;
  final bool ok;
  final String message;

  const _Result(
    this.sector,
    this.type,
    this.key,
    this.ok,
    this.message,
  );
}
