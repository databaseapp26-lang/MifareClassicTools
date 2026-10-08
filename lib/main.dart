import 'package:flutter/material.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';

void main() => runApp(const MifareClassicToolsApp());

class MifareClassicToolsApp extends StatelessWidget {
  const MifareClassicToolsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MIFARE Classic Tools',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
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
            const SizedBox(height: 12),
            if (_running) const LinearProgressIndicator(),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _running ? null : _readTag,
              child: const Text('Leggi tag'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _running ? null : _clearResults,
              child: const Text('Pulisci risultati'),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: _sectors.length,
                itemBuilder: (context, index) {
                  final s = _sectors[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Settore ${s.sector} — Key ${s.type} ${s.key}',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 5),
                          Text('${s.readableBlocks}/4 blocchi letti',
                              style: TextStyle(
                                color: s.readableBlocks == 4
                                    ? Colors.green.shade700
                                    : Colors.orange.shade800,
                                fontWeight: FontWeight.w600,
                              )),
                          const SizedBox(height: 8),
                          for (final b in s.blocks)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 7),
                              child: Text('Blocco ${b.block}: ${b.hex}',
                                  style: const TextStyle(
                                      fontFamily: 'monospace', fontSize: 13)),
                            ),
                        ],
                      ),
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

  void _clearResults() {
    setState(() {
      _sectors.clear();
      _uid = '';
      _status = 'Risultati cancellati. Premi "Leggi tag".';
    });
  }

  Future<void> _readTag() async {
    if (_running) return;
    setState(() {
      _running = true;
      _uid = '';
      _sectors.clear();
      _status = 'Avvia lettura...';
    });

    try {
      final availability = await FlutterNfcKit.nfcAvailability;
      if (availability != NFCAvailability.available) {
        throw StateError('NFC non disponibile o disabilitato.');
      }

      setState(() => _status = 'Avvicina il tag...');
      final firstTag = await FlutterNfcKit.poll(
        timeout: const Duration(seconds: 30),
        androidPlatformSound: false,
        androidCheckNDEF: false,
      );
      if (firstTag.type != NFCTagType.mifare_classic) {
        throw StateError('Tag rilevato: ${firstTag.type.name}. Serve un MIFARE Classic.');
      }

      final uid = firstTag.id.toUpperCase();
      final sectorCount = _sectorCount(firstTag);
      setState(() {
        _uid = uid;
        _status = 'UID $uid — lettura settore per settore...';
      });
      await FlutterNfcKit.finish();

      for (var sector = 0; sector < sectorCount; sector++) {
        setState(() => _status =
            'Settore $sector/$sectorCount: avvicina/tieni il tag sul telefono...');

        final tag = await FlutterNfcKit.poll(
          timeout: const Duration(seconds: 12),
          androidPlatformSound: false,
          androidCheckNDEF: false,
        );
        final currentUid = tag.id.toUpperCase();
        if (currentUid != uid) {
          throw StateError('UID cambiato: atteso $uid, rilevato $currentUid.');
        }
        if (tag.type != NFCTagType.mifare_classic) {
          throw StateError('Il tag non è più rilevato come MIFARE Classic.');
        }

        final candidate = _knownKeys.firstWhere(
          (k) => k.uid == uid && k.sector == sector,
          orElse: () => const _FoundKey('', -1, '', ''),
        );
        if (candidate.sector < 0) {
          await FlutterNfcKit.finish();
          continue;
        }

        try {
          final authenticated = candidate.type == 'A'
              ? await FlutterNfcKit.authenticateSector<String>(sector, keyA: candidate.key)
              : await FlutterNfcKit.authenticateSector<String>(sector, keyB: candidate.key);

          if (!authenticated) {
            setState(() => _status =
                'Settore $sector: autenticazione FALLITA con ${candidate.type}.');
            await FlutterNfcKit.finish();
            continue;
          }

          setState(() => _status = 'Settore $sector: autenticazione OK — lettura blocchi...');
          final blocks = <_BlockDump>[];
          var readable = 0;
          final firstBlock = sector * 4;

          for (var offset = 0; offset < 4; offset++) {
            final blockNumber = firstBlock + offset;
            try {
              final data = await FlutterNfcKit.readBlock(blockNumber);
              blocks.add(_BlockDump(blockNumber, _toHex(data)));
              readable++;
            } catch (e) {
              blocks.add(_BlockDump(blockNumber, 'ERRORE LETTURA: $e'));
            }
          }

          if (mounted) {
            setState(() {
              _sectors.add(_SectorDump(sector, candidate.type, candidate.key, readable, blocks));
              _status = 'Settore $sector: $readable/4 blocchi letti. Passaggio al successivo...';
            });
          }
        } finally {
          try {
            await FlutterNfcKit.finish();
          } catch (_) {}
        }
      }

      final totalBlocks = _sectors.fold<int>(0, (sum, item) => sum + item.readableBlocks);
      if (mounted) {
        setState(() => _status =
            'Lettura terminata: ${_sectors.length}/$sectorCount settori, '
            '$totalBlocks/${sectorCount * 4} blocchi leggibili.');
      }
    } catch (e) {
      try { await FlutterNfcKit.finish(); } catch (_) {}
      if (mounted) setState(() => _status = 'Errore: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  int _sectorCount(NFCTag tag) {
    final sak = (tag.sak ?? '').replaceAll('0x', '').toUpperCase();
    return sak == '18' ? 40 : 16;
  }

  String _toHex(Iterable<int> data) => data
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');
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
  const _SectorDump(this.sector, this.type, this.key, this.readableBlocks, this.blocks);
}

class _BlockDump {
  final int block;
  final String hex;
  const _BlockDump(this.block, this.hex);
}
