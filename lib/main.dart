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
      home: const HomePage(),
    );
  }
}

class FoundKey {
  const FoundKey({
    required this.sector,
    required this.type,
    required this.key,
  });

  final int sector;
  final String type;
  final String key;

  String get storageValue => '$sector|$type|$key';

  static FoundKey? fromStorage(String value) {
    final parts = value.split('|');
    if (parts.length != 3) return null;
    final sector = int.tryParse(parts[0]);
    if (sector == null || (parts[1] != 'A' && parts[1] != 'B')) return null;
    return FoundKey(sector: sector, type: parts[1], key: parts[2]);
  }
}

class _HomePageState extends State<HomePage> {
  NFCTag? _tag;
  bool _sessionOpen = false;
  bool _busy = false;
  bool _cancelRequested = false;

  List<String> _candidateKeys = <String>[];
  final List<FoundKey> _foundKeys = <FoundKey>[];

  String _status = 'Pronto. Carico il database chiavi...';
  int _attempts = 0;
  int _totalAttempts = 0;
  int _currentSector = 0;
  String _currentKey = '';

  @override
  void initState() {
    super.initState();
    _loadCandidates();
    _loadSavedResults();
  }

  Future<void> _loadCandidates() async {
    try {
      final text = await rootBundle.loadString('assets/keys/authorized.keys');
      final keys = <String>{};

      for (final raw in text.split(RegExp(r'\r?\n'))) {
        var line = raw.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        line = line.replaceAll(RegExp(r'[\s:\-]'), '').toUpperCase();
        if (RegExp(r'^[0-9A-F]{12}$').hasMatch(line)) {
          keys.add(line);
        }
      }

      final list = keys.toList()..sort();
      if (!mounted) return;

      setState(() {
        _candidateKeys = list;
        _status = 'Pronto: ${list.length} chiavi candidate caricate.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Errore caricamento chiavi: $e');
    }
  }

  Future<void> _loadSavedResults() async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList('found_keys') ?? <String>[];
    final restored = values
        .map(FoundKey.fromStorage)
        .whereType<FoundKey>()
        .toList();

    if (!mounted) return;
    setState(() {
      _foundKeys
        ..clear()
        ..addAll(restored);
    });
  }

  Future<void> _saveResults() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'found_keys',
      _foundKeys.map((e) => e.storageValue).toList(),
    );
  }

  Future<void> _poll() async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _status = 'Avvicina il tag MIFARE Classic al telefono...';
    });

    try {
      if (_sessionOpen) {
        await FlutterNfcKit.finish();
        _sessionOpen = false;
      }

      final tag = await FlutterNfcKit.poll(
        timeout: const Duration(seconds: 20),
        androidReaderModeFlags: 0x80,
      );

      _tag = tag;
      _sessionOpen = true;

      if (tag.type != NFCTagType.mifare_classic) {
        setState(() {
          _status = 'Tag rilevato, ma non è MIFARE Classic: ${tag.type}';
        });
        return;
      }

      setState(() {
        _status =
            'MIFARE Classic rilevato — ID ${tag.id}. Pronto per la verifica.';
      });
    } catch (e) {
      setState(() => _status = 'Errore NFC: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  int _sectorCountForTag(NFCTag tag) {
    // I valori SAK usati comunemente da MIFARE Classic:
    // 09 = Mini (5 settori), 08/28/88 = 1K (16), 18/38 = 4K (40).
    final sak = (tag.sak ?? '')
        .replaceAll(RegExp(r'[^0-9A-Fa-f]'), '')
        .toUpperCase();
    if (sak == '09') return 5;
    if (sak == '18' || sak == '38') return 40;
    return 16;
  }

  bool _alreadyFound(int sector, String type, String key) {
    return _foundKeys.any(
      (f) => f.sector == sector && f.type == type && f.key == key,
    );
  }

  Future<bool> _tryKey(int sector, String type, String key) async {
    try {
      if (type == 'A') {
        return await FlutterNfcKit.authenticateSector(
          sector,
          keyA: key,
        );
      }
      return await FlutterNfcKit.authenticateSector(
        sector,
        keyB: key,
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> _addFoundKey(int sector, String type, String key) async {
    if (_alreadyFound(sector, type, key)) return;

    _foundKeys.add(FoundKey(sector: sector, type: type, key: key));
    await _saveResults();

    if (mounted) setState(() {});
  }

  Future<void> _runAutomaticScan() async {
    if (_busy) return;

    if (!_sessionOpen || _tag == null) {
      setState(() => _status = 'Prima premi "Rileva tag".');
      return;
    }

    if (_tag!.type != NFCTagType.mifare_classic) {
      setState(() => _status = 'Il tag rilevato non è MIFARE Classic.');
      return;
    }

    if (_candidateKeys.isEmpty) {
      setState(() => _status = 'Nessuna chiave valida caricata.');
      return;
    }

    final sectors = _sectorCountForTag(_tag!);
    _cancelRequested = false;
    _attempts = 0;
    _totalAttempts = sectors * _candidateKeys.length * 2;

    setState(() {
      _busy = true;
      _status =
          'Avvio verifica automatica: $sectors settori × '
          '${_candidateKeys.length} chiavi × Key A/B.';
    });

    try {
      // Prima le Key A, poi le Key B. Non vengono effettuate scritture.
      for (final type in const ['A', 'B']) {
        for (var sector = 0; sector < sectors; sector++) {
          if (_cancelRequested) break;

          _currentSector = sector;

          // Se per un settore abbiamo già una chiave di questo tipo,
          // lo consideriamo risolto e passiamo oltre.
          if (_foundKeys.any((f) => f.sector == sector && f.type == type)) {
            continue;
          }

          var foundForSector = false;

          for (final key in _candidateKeys) {
            if (_cancelRequested) break;

            _currentKey = key;
            _attempts++;

            if (mounted) {
              setState(() {
                _status =
                    'Settore $sector/$sectors — Key $type — '
                    'tentativo $_attempts/$_totalAttempts — $key';
              });
            }

            final ok = await _tryKey(sector, type, key);

            if (ok) {
              foundForSector = true;
              await _addFoundKey(sector, type, key);

              if (mounted) {
                setState(() {
                  _status =
                      'TROVATA: settore $sector — Key $type — $key';
                });
              }

              // Per questo tipo di chiave, una volta trovata la prima
              // candidata valida per il settore, passiamo al settore successivo.
              break;
            }

            // Piccola pausa per non martellare il thread NFC del telefono.
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }

          if (!foundForSector && mounted && !_cancelRequested) {
            setState(() {
              _status =
                  'Settore $sector — nessuna chiave $type trovata '
                  'nella lista.';
            });
          }
        }

        if (_cancelRequested) break;
      }

      if (mounted) {
        setState(() {
          _status = _cancelRequested
              ? 'Scansione interrotta dall\'utente.'
              : 'Scansione terminata. Trovate ${_foundKeys.length} associazioni.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _clearSavedResults() async {
    if (_busy) return;

    _foundKeys.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('found_keys');

    if (mounted) {
      setState(() {
        _status = 'Risultati salvati cancellati.';
      });
    }
  }

  Future<void> _finish() async {
    try {
      if (_sessionOpen) await FlutterNfcKit.finish();
    } catch (_) {
      // La sessione può essere già terminata dal sistema.
    } finally {
      _sessionOpen = false;
      _tag = null;
      if (mounted) {
        setState(() {
          _status = 'Sessione NFC chiusa.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tag = _tag;
    final double progress = _totalAttempts == 0
        ? 0.0
        : (_attempts / _totalAttempts).clamp(0.0, 1.0).toDouble();

    return Scaffold(
      appBar: AppBar(
        title: const Text('MIFARE Classic Tools'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Stato',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(_status),
                  if (tag != null) ...[
                    const SizedBox(height: 8),
                    Text('Tipo: ${tag.type}'),
                    Text('ID: ${tag.id}'),
                    Text('Standard: ${tag.standard}'),
                    Text('SAK: ${tag.sak ?? "n/d"}'),
                    Text('Chiavi candidate: ${_candidateKeys.length}'),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _poll,
            icon: const Icon(Icons.nfc),
            label: const Text('1. Rileva tag'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy || !_sessionOpen ? null : _runAutomaticScan,
            icon: const Icon(Icons.manage_search),
            label: const Text('2. Prova automaticamente le chiavi'),
          ),
          if (_busy) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => setState(() => _cancelRequested = true),
              icon: const Icon(Icons.stop),
              label: const Text('Interrompi scansione'),
            ),
          ],
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : _finish,
            child: const Text('Chiudi sessione NFC'),
          ),
          const Divider(height: 32),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Chiavi trovate e salvate',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Cancella risultati salvati',
                onPressed: _busy ? null : _clearSavedResults,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_foundKeys.isEmpty)
            const Text('Nessuna associazione salvata.')
          else
            ..._foundKeys.map(
              (found) => Card(
                child: ListTile(
                  leading: const Icon(Icons.key),
                  title: Text(
                    'Settore ${found.sector} — Key ${found.type}',
                  ),
                  subtitle: Text(found.key),
                ),
              ),
            ),
          const SizedBox(height: 20),
          const Text(
            'La procedura usa solo autenticazione in lettura: non scrive '
            'dati sul tag. Le associazioni trovate vengono salvate '
            'localmente sul telefono.',
          ),
        ],
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}
