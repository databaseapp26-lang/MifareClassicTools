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

  // Chiavi già trovate sul tag 90140ABA.
  // Questa versione esegue solo autenticazione e lettura: NON scrive nulla.
  static const _knownKeys = <_FoundKey>[
    _FoundKey('90140ABA', 0, 'A', 'A0A1A2A3A4A5'),
    _FoundKey('90140ABA', 1, 'B', '8FD0A4F256E9'),
    _FoundKey('90140ABA', 2, 'B', 'AAFB06045877'),
    _FoundKey('90140ABA', 3, 'A', 'E4D2770A89BE'),
    _FoundKey('90140ABA', 4, 'A', '1999A3554A55'),
    _FoundKey('90140ABA', 5, 'A', 'FC00018778F7'),
    _FoundKey('90140ABA', 6, 'B', '1B61B2E78C75'),
    _FoundKey('90140ABA', 7, 'A', '26940B21FF5D'),
    _FoundKey('90140ABA', 8, 'B', '888888888888'),
    _FoundKey('90140ABA', 9, 'A', 'EE0042F88840'),
    _FoundKey('90140ABA', 10, 'B', '6F4B6D644178'),
    _FoundKey('90140ABA', 11, 'B', '434F4D4D4F42'),
    _FoundKey('90140ABA', 12, 'A', '64E3C10394C2'),
    _FoundKey('90140ABA', 13, 'B', 'EE0042F88840'),
    _FoundKey('90140ABA', 14, 'A', 'FC00018778F7'),
    _FoundKey('90140ABA', 15, 'B', '75CCB59C9BED'),
  ];

  bool _running = false;
  String _status = 'Pronto. Premi "Leggi tag".';
  String _uid = '';
  final List<_SectorDump> _sectors = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MIFARE Classic Tools')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 10),
            if (_uid.isNotEmpty) Text('UID: $_uid'),
            if (_running) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _running ? null : _readTag,
              child: const Text('Leggi tag'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _running ? null : _clearResults,
              child: const Text('Pulisci risultati'),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ListView.builder(
                itemCount: _sectors.length,
                itemBuilder: (context, index) {
                  return _sectorCard(_sectors[index]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectorCard(_SectorDump sector) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Settore ${sector.sector} — Key ${sector.type} ${sector.key}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              '${sector.readableBlocks}/4 blocchi letti',
              style: TextStyle(
                color: sector.readableBlocks == 4
                    ? Colors.green.shade700
                    : Colors.orange.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            for (final block in sector.blocks)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Text(
                  'Blocco ${block.block}: ${block.hex}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _clearResults() {
    setState(() {
      _sectors.clear();
      _uid = '';
      _status = 'Risultati cancellati. Premi "Leggi tag".';
    });
  }

  Future<List<_FoundKey>> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? const [];

    return raw.map((s) {
      final p = s.split('|');
      if (p.length != 4) {
        return const _FoundKey('', -1, '', '');
      }
      return _FoundKey(
        p[0],
        int.tryParse(p[1]) ?? -1,
        p[2],
        p[3],
      );
    }).where((e) => e.uid.isNotEmpty && e.sector >= 0).toList();
  }

  Future<void> _readTag() async {
    if (_running) return;

    setState(() {
      _running = true;
      _status = 'Controllo NFC...';
      _uid = '';
      _sectors.clear();
    });

    try {
      final availability = await FlutterNfcKit.nfcAvailability;
      if (availability != NFCAvailability.available) {
        throw StateError('NFC non disponibile o disabilitato.');
      }

      setState(() {
        _status = 'Avvicina il MIFARE Classic al telefono...';
      });

      final tag = await FlutterNfcKit.poll(
        timeout: const Duration(seconds: 30),
        androidPlatformSound: false,
        androidCheckNDEF: false,
      );

      if (tag.type != NFCTagType.mifare_classic) {
        throw StateError(
          'Tag rilevato: ${tag.type.name}. Serve un MIFARE Classic.',
        );
      }

      final uid = tag.id.toUpperCase();
      final sectors = _sectorCount(tag);

      setState(() {
        _uid = uid;
        _status = 'UID $uid — lettura di $sectors settori...';
      });

      final saved = await _loadSaved();

      for (var sector = 0; sector < sectors; sector++) {
        final candidates = <_FoundKey>[];

        for (final item in saved) {
          if (item.uid == uid && item.sector == sector) {
            if (!candidates.any(
              (x) => x.type == item.type && x.key == item.key,
            )) {
              candidates.add(item);
            }
          }
        }

        for (final item in _knownKeys) {
          if (item.uid == uid && item.sector == sector) {
            if (!candidates.any(
              (x) => x.type == item.type && x.key == item.key,
            )) {
              candidates.add(item);
            }
          }
        }

        if (candidates.isEmpty) {
          setState(() {
            _status = 'Settore $sector: nessuna chiave disponibile.';
          });
          continue;
        }

        _FoundKey? workingKey;

        for (final candidate in candidates) {
          if (await _authenticate(
            sector,
            candidate.type,
            candidate.key,
          )) {
            workingKey = candidate;
            break;
          }
        }

        if (workingKey == null) {
          setState(() {
            _status = 'Settore $sector: autenticazione fallita.';
          });
          continue;
        }

        final blocks = <_BlockDump>[];
        var readable = 0;
        final firstBlock = sector * 4;

        for (var offset = 0; offset < 4; offset++) {
          final blockNumber = firstBlock + offset;

          try {
            final data = await FlutterNfcKit.readBlock(blockNumber);
            final hex = _toHex(data);
            blocks.add(_BlockDump(blockNumber, hex));
            readable++;
          } catch (_) {
            blocks.add(_BlockDump(blockNumber, 'ERRORE LETTURA'));
          }
        }

        final result = _SectorDump(
          sector,
          workingKey.type,
          workingKey.key,
          readable,
          blocks,
        );

        if (mounted) {
          setState(() {
            _sectors.add(result);
            _status =
                'Letto settore $sector/$sectors — $readable/4 blocchi.';
          });
        }
      }

      if (mounted) {
        final totalBlocks = _sectors.fold<int>(
          0,
          (sum, item) => sum + item.readableBlocks,
        );

        setState(() {
          _status =
              'Lettura terminata: ${_sectors.length}/$sectors settori, '
              '$totalBlocks/${sectors * 4} blocchi leggibili.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'Errore: $e';
        });
      }
    } finally {
      try {
        await FlutterNfcKit.finish();
      } catch (_) {}

      if (mounted) {
        setState(() {
          _running = false;
        });
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
    final sak = (tag.sak ?? '').replaceAll('0x', '').toUpperCase();
    if (sak == '18') return 40;
    return 16;
  }

  String _toHex(Iterable<int> data) {
    return data
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
  }
}

class _FoundKey {
  final String uid;
  final int sector;
  final String type;
  final String key;

  const _FoundKey(this.uid, this.sector, this.type, this.key);
}

class _SectorDump {
  final int sector;
  final String type;
  final String key;
  final int readableBlocks;
  final List<_BlockDump> blocks;

  const _SectorDump(
    this.sector,
    this.type,
    this.key,
    this.readableBlocks,
    this.blocks,
  );
}

class _BlockDump {
  final int block;
  final String hex;

  const _BlockDump(this.block, this.hex);
}
