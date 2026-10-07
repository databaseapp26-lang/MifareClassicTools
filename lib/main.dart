```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const MifareClassicToolsApp());

class MifareClassicToolsApp extends StatelessWidget {
  const MifareClassicToolsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MIFARE Classic Tools',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
      ),
      home: const ScannerPage(),
    );
  }
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  static const _prefsKey = 'mifare_found_keys_v1';

  bool _running = false;
  bool _stopRequested = false;

  List<String> _keys = [];

  final List<_FoundKey> _found = [];

  int _attempts = 0;
  int _totalAttempts = 0;

  String _status = 'Pronto. Premi "Scansiona tag".';

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    try {
      final text =
          await rootBundle.loadString('assets/keys/authorized.keys');

      final keys = <String>{};

      for (final raw in text.split(RegExp(r'\r?\n'))) {
        final k = raw
            .trim()
            .replaceAll(RegExp(r'\s+'), '')
            .toUpperCase();

        if (RegExp(r'^[0-9A-F]{12}$').hasMatch(k)) {
          keys.add(k);
        }
      }

      final saved = await _loadSaved();

      /*
       * ============================================================
       * CHIAVI MIZIP
       * ============================================================
       *
       * Queste sono le chiavi generate dall'algoritmo MiZip
       * per il nostro UID:
       *
       * UID = 90140ABA
       *
       * Settore 0:
       *   Key A = A0A1A2A3A4A5
       *   Key B = B4C132439EEF
       *
       * Settore 1:
       *   Key A = 9906509F19F1
       *   Key B = FB961447D29B
       *
       * Settore 2:
       *   Key A = 3B61C38D023B
       *   Key B = 795D09EA38FB
       *
       * Settore 3:
       *   Key A = 72664B15BC1D
       *   Key B = A0F783625C14
       *
       * Settore 4:
       *   Key A = A16EBD95D484
       *   Key B = BAA9B7332747
       *
       * NON scrivono nulla sul tag.
       * Servono solamente per velocizzare il test di autenticazione.
       * ============================================================
       */

      const miZipKeys = <String>[
        'A0A1A2A3A4A5',
        'B4C132439EEF',

        '9906509F19F1',
        'FB961447D29B',

        '3B61C38D023B',
        '795D09EA38FB',

        '72664B15BC1D',
        'A0F783625C14',

        'A16EBD95D484',
        'BAA9B7332747',
      ];

      /*
       * Ordine delle chiavi:
       *
       * 1. Chiavi già trovate e salvate sul telefono
       * 2. Chiavi MiZip generate per il nostro UID
       * 3. Tutte le altre 2477 chiavi del database
       *
       * In questo modo non perdiamo il database originale.
       */

      final ordered = <String>[];

      for (final savedKey in saved.map((e) => e.key)) {
        if (!ordered.contains(savedKey)) {
          ordered.add(savedKey);
        }
      }

      for (final key in miZipKeys) {
        if (!ordered.contains(key)) {
          ordered.add(key);
        }
      }

      for (final key in keys) {
        if (!ordered.contains(key)) {
          ordered.add(key);
        }
      }

      if (mounted) {
        setState(() {
          _keys = ordered;

          _status =
              'Caricate ${keys.length} chiavi candidate. '
              'Chiavi MiZip prioritarie: ${miZipKeys.length}.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Errore caricamento chiavi: $e');
      }
    }
  }

  Future<List<_FoundKey>> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getStringList(_prefsKey) ?? const [];

    return raw
        .map((s) {
          final p = s.split('|');

          if (p.length != 4) {
            return _FoundKey('', -1, '', '');
          }

          return _FoundKey(
            p[0],
            int.tryParse(p[1]) ?? -1,
            p[2],
            p[3],
          );
        })
        .where(
          (e) => e.key.isNotEmpty && e.sector >= 0,
        )
        .toList();
  }

  Future<void> _saveFound(String uid) async {
    final prefs = await SharedPreferences.getInstance();

    final existing =
        prefs.getStringList(_prefsKey) ?? <String>[];

    final map = <String, String>{};

    for (final item in existing) {
      final p = item.split('|');

      if (p.length == 4) {
        map['${p[0]}|${p[1]}|${p[2]}'] = item;
      }
    }

    for (final f in _found) {
      map['$uid|${f.sector}|${f.type}'] =
          '$uid|${f.sector}|${f.type}|${f.key}';
    }

    await prefs.setStringList(
      _prefsKey,
      map.values.toList(),
    );
  }

  Future<void> _scan() async {
    if (_running) return;

    setState(() {
      _running = true;
      _stopRequested = false;
      _found.clear();
      _attempts = 0;
      _status = 'Controllo NFC...';
    });

    try {
      final availability =
          await FlutterNfcKit.nfcAvailability;

      if (availability != NFCAvailability.available) {
        throw StateError(
          'NFC non disponibile o disabilitato.',
        );
      }

      setState(
        () => _status =
            'Avvicina il MIFARE Classic al telefono...',
      );

      final tag = await FlutterNfcKit.poll(
        timeout: const Duration(seconds: 30),
        androidPlatformSound: false,
        androidCheckNDEF: false,
      );

      if (tag.type != NFCTagType.mifare_classic) {
        throw StateError(
          'Tag rilevato: ${tag.type.name}. '
          'Serve un MIFARE Classic.',
        );
      }

      final uid = tag.id.toUpperCase();

      final sectors = _sectorCount(tag);

      final savedForTag = (await _loadSaved())
          .where(
            (e) =>
                e.uid == uid &&
                e.sector < sectors,
          )
          .toList();

      /*
       * Numero teorico massimo:
       *
       * settori × chiavi × 2
       *
       * perché ogni chiave viene provata come A e come B.
       */

      _totalAttempts =
          sectors * _keys.length * 2;

      setState(() {
        _status =
            'UID $uid — $sectors settori — '
            '${_keys.length} chiavi candidate.';
      });

      /*
       * ============================================================
       * SCANSIONE SETTORI
       * ============================================================
       */

      for (
        var sector = 0;
        sector < sectors && !_stopRequested;
        sector++
      ) {
        final known = savedForTag
            .where(
              (e) => e.sector == sector,
            )
            .toList();

        var sectorFound = false;

        /*
         * ----------------------------------------------------------
         * 1. PRIMA LE CHIAVI GIÀ SALVATE
         * ----------------------------------------------------------
         */

        for (final saved in known) {
          if (_stopRequested) break;

          final ok = await _authenticate(
            sector,
            saved.type,
            saved.key,
          );

          _attempts++;

          if (ok) {
            _found.add(saved);

            sectorFound = true;

            setState(
              () => _status =
                  'Settore $sector: '
                  '${saved.type} ${saved.key} '
                  '(memorizzata)',
            );

            break;
          }
        }

        if (sectorFound) {
          continue;
        }

        /*
         * ----------------------------------------------------------
         * 2. POI LE CHIAVI DEL DATABASE
         *
         * Le prime sono le chiavi MiZip.
         * Successivamente arrivano tutte le altre.
         *
         * Per ogni chiave:
         *   prima Key A
         *   poi Key B
         * ----------------------------------------------------------
         */

        for (final key in _keys) {
          if (_stopRequested || sectorFound) {
            break;
          }

          /*
           * ==========================
           * KEY A
           * ==========================
           */

          final a = await _authenticate(
            sector,
            'A',
            key,
          );

          _attempts++;

          if (a) {
            final f = _FoundKey(
              uid,
              sector,
              'A',
              key,
            );

            _found.add(f);

            await _saveFound(uid);

            sectorFound = true;

            setState(
              () => _status =
                  'Trovata Key A: '
                  'settore $sector → $key',
            );

            break;
          }

          /*
           * ==========================
           * KEY B
           * ==========================
           */

          final b = await _authenticate(
            sector,
            'B',
            key,
          );

          _attempts++;

          if (b) {
            final f = _FoundKey(
              uid,
              sector,
              'B',
              key,
            );

            _found.add(f);

            await _saveFound(uid);

            sectorFound = true;

            setState(
              () => _status =
                  'Trovata Key B: '
                  'settore $sector → $key',
            );

            break;
          }

          /*
           * Aggiorna la UI ogni 10 tentativi.
           */

          if (_attempts % 10 == 0 &&
              mounted) {
            setState(
              () => _status =
                  'Settore $sector — '
                  'tentativi $_attempts / '
                  '$_totalAttempts',
            );
          }
        }

        if (!sectorFound &&
            mounted) {
          setState(
            () => _status =
                'Settore $sector: '
                'nessuna chiave trovata.',
          );
        }
      }

      if (_stopRequested) {
        setState(
          () => _status =
              'Scansione interrotta. '
              'Trovate ${_found.length} chiavi.',
        );
      } else {
        setState(
          () => _status =
              'Scansione terminata. '
              'Trovate ${_found.length} chiavi.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _status = 'Errore: $e',
        );
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

  Future<bool> _authenticate(
    int sector,
    String type,
    String key,
  ) async {
    try {
      if (type == 'A') {
        return await FlutterNfcKit.authenticateSector<String>(
          sector,
          keyA: key,
        );
      }

      return await FlutterNfcKit.authenticateSector<String>(
        sector,
        keyB: key,
      );
    } catch (_) {
      return false;
    }
  }

  int _sectorCount(NFCTag tag) {
    final sak =
        (tag.sak ?? '')
            .replaceAll('0x', '')
            .toUpperCase();

    /*
     * MIFARE Classic 4K:
     * SAK 0x18 → 40 settori.
     *
     * Altri SAK usati dalle Classic 1K/2K:
     * → 16 settori.
     */

    if (sak == '18') {
      return 40;
    }

    return 16;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'MIFARE Classic Tools',
        ),
      ),

      body: Padding(
        padding: const EdgeInsets.all(16),

        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.stretch,

          children: [
            Text(_status),

            const SizedBox(height: 12),

            if (_running)
              LinearProgressIndicator(
                value: _totalAttempts == 0
                    ? null
                    : (_attempts /
                            _totalAttempts)
                        .clamp(0.0, 1.0),
              ),

            const SizedBox(height: 12),

            Text(
              'Chiavi candidate: ${_keys.length}',
            ),

            Text(
              'Chiavi trovate in questa scansione: '
              '${_found.length}',
            ),

            Text(
              'Tentativi: $_attempts'
              '${_totalAttempts == 0 ? '' : ' / $_totalAttempts'}',
            ),

            const SizedBox(height: 20),

            FilledButton(
              onPressed:
                  _running ? null : _scan,

              child: const Text(
                'Scansiona tag',
              ),
            ),

            if (_running) ...[
              const SizedBox(height: 8),

              OutlinedButton(
                onPressed: () {
                  setState(
                    () => _stopRequested = true,
                  );
                },

                child: const Text(
                  'Interrompi',
                ),
              ),
            ],

            const SizedBox(height: 20),

            Expanded(
              child: ListView.builder(
                itemCount: _found.length,

                itemBuilder:
                    (context, index) {
                  final f = _found[index];

                  return ListTile(
                    dense: true,

                    title: Text(
                      'Settore ${f.sector} — '
                      'Key ${f.type}',
                    ),

                    subtitle: Text(
                      f.key,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FoundKey {
  final String uid;
  final int sector;
  final String type;
  final String key;

  const _FoundKey(
    this.uid,
    this.sector,
    this.type,
    this.key,
  );
}
```
