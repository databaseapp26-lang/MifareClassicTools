import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';

void main() {
  runApp(const MifareClassicToolsApp());
}

class MifareClassicToolsApp extends StatelessWidget {
  const MifareClassicToolsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tools',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
      ),
      home: const MifareReaderPage(),
    );
  }
}

class MifareReaderPage extends StatefulWidget {
  const MifareReaderPage({super.key});

  @override
  State<MifareReaderPage> createState() => _MifareReaderPageState();
}

class _MifareReaderPageState extends State<MifareReaderPage> {
  static const List<String> _knownKeys = [
    'FFFFFFFFFFFF',
    'A0A1A2A3A4A5',
    'D3F7D3F7D3F7',
    'B0B1B2B3B4B5',
    '4D3A99C351DD',
    '000000000000',
  ];

  String _status = 'PRONTO';
  bool _reading = false;

  String _uid = '';
  String _technology = '';
  String _standard = '';
  String _ndef = '';

  int _authenticatedSectors = 0;
  int _readableSectors = 0;
  int _readBlocks = 0;

  final List<Map<String, dynamic>> _sectors = [];

  Future<void> _scanTag() async {
    if (_reading) return;

    setState(() {
      _reading = true;
      _status = 'RICERCA TAG NFC...';

      _uid = '';
      _technology = '';
      _standard = '';
      _ndef = '';

      _authenticatedSectors = 0;
      _readableSectors = 0;
      _readBlocks = 0;

      _sectors.clear();
    });

    try {
      final tag = await FlutterNfcKit.poll(
        timeout: const Duration(seconds: 20),
        androidCheckNDEF: false,
      );

      if (tag.type != NFCTagType.mifare_classic) {
        setState(() {
          _status = 'TAG NON COMPATIBILE';
          _uid = tag.id;
          _technology = tag.type.toString();
        });
        return;
      }

      setState(() {
        _status = 'TAG RILEVATO';
        _uid = tag.id;
        _technology = tag.type.toString();
        _standard = tag.standard;
        _ndef = tag.ndefAvailable == true
            ? 'Disponibile'
            : 'Non disponibile';
      });

      await _readAllSectors();
    } catch (e) {
      setState(() {
        _status = 'ERRORE';
      });

      _showError(e.toString());
    } finally {
      try {
        await FlutterNfcKit.finish();
      } catch (_) {}

      if (mounted) {
        setState(() {
          _reading = false;
        });
      }
    }
  }

  Future<void> _readAllSectors() async {
    for (int sector = 0; sector < 16; sector++) {
      if (!mounted) return;

      setState(() {
        _status = 'LETTURA SETTORE ${sector + 1} / 16...';
      });

      await _readSectorByBlocks(sector);
    }

    if (!mounted) return;

    setState(() {
      _status = 'LETTURA COMPLETATA';
    });
  }

  Future<void> _readSectorByBlocks(int sector) async {
    String? authenticatedKey;
    String? authenticatedMethod;

    // Prova prima Key A.
    for (final key in _knownKeys) {
      try {
        final authenticated = await FlutterNfcKit.authenticateSector(
          sector,
          keyA: key,
        );

        if (authenticated) {
          authenticatedKey = key;
          authenticatedMethod = 'Key A';
          break;
        }
      } catch (_) {
        // Prova la chiave successiva.
      }
    }

    // Se Key A non funziona, prova Key B.
    if (authenticatedKey == null) {
      for (final key in _knownKeys) {
        try {
          final authenticated = await FlutterNfcKit.authenticateSector(
            sector,
            keyB: key,
          );

          if (authenticated) {
            authenticatedKey = key;
            authenticatedMethod = 'Key B';
            break;
          }
        } catch (_) {
          // Prova la chiave successiva.
        }
      }
    }

    final sectorResult = <String, dynamic>{
      'sector': sector,
      'authenticated': authenticatedKey != null,
      'key': authenticatedKey,
      'method': authenticatedMethod,
      'blocks': <Map<String, dynamic>>[],
    };

    if (authenticatedKey == null) {
      sectorResult['error'] = 'Autenticazione fallita';

      if (mounted) {
        setState(() {
          _sectors.add(sectorResult);
        });
      }

      return;
    }

    _authenticatedSectors++;

    // IMPORTANTE:
    // dopo authenticateSector leggiamo subito i blocchi
    // del settore, uno alla volta.
    final int firstBlock = sector * 4;

    bool sectorFullyReadable = true;

    for (int offset = 0; offset < 4; offset++) {
      final int blockIndex = firstBlock + offset;

      try {
        final data = await FlutterNfcKit.readBlock(blockIndex);

        final hex = _bytesToHex(data);

        (sectorResult['blocks'] as List<Map<String, dynamic>>).add({
          'index': blockIndex,
          'success': true,
          'data': hex,
        });

        _readBlocks++;
      } catch (e) {
        sectorFullyReadable = false;

        (sectorResult['blocks'] as List<Map<String, dynamic>>).add({
          'index': blockIndex,
          'success': false,
          'error': e.toString(),
        });

        // Se un blocco fallisce, fermiamo questo settore.
        // Non martelliamo il tag con altre richieste.
        break;
      }
    }

    if (sectorFullyReadable) {
      _readableSectors++;
    }

    if (mounted) {
      setState(() {
        _sectors.add(sectorResult);
      });
    }
  }

  String _bytesToHex(List<int> bytes) {
    return bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
  }

  void _showError(String message) {
    if (!mounted) return;

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Errore'),
          content: SingleChildScrollView(
            child: Text(message),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(value),
          ),
        ],
      ),
    );
  }

  Widget _buildSectorCard(Map<String, dynamic> sector) {
    final int sectorIndex = sector['sector'] as int;
    final bool authenticated = sector['authenticated'] as bool;
    final String? key = sector['key'] as String?;
    final String? method = sector['method'] as String?;

    final blocks =
        sector['blocks'] as List<Map<String, dynamic>>;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SETTORE ${sectorIndex + 1}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),

            if (authenticated) ...[
              const Text(
                '✅ AUTENTICATO',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (method != null)
                Text('Metodo: $method'),
              if (key != null)
                Text('Chiave: $key'),
            ] else ...[
              const Text(
                '❌ AUTENTICAZIONE FALLITA',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],

            const SizedBox(height: 10),

            if (blocks.isEmpty && authenticated)
              const Text('Nessun blocco letto.'),

            for (final block in blocks) ...[
              const Divider(),
              Text(
                'BLOCCO ${block['index']}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),

              if (block['success'] == true)
                SelectableText(
                  block['data'] as String,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                )
              else
                Text(
                  '❌ ERRORE LETTURA\n${block['error']}',
                  style: const TextStyle(
                    fontSize: 12,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tools'),
      ),

      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'MIFARE Classic 1K',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 4),

                    const Text(
                      'Lettura e diagnostica NFC',
                      style: TextStyle(
                        fontSize: 16,
                      ),
                    ),

                    const SizedBox(height: 16),

                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _status,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),

                            const SizedBox(height: 10),

                            if (_uid.isNotEmpty)
                              _infoRow('UID', _uid),

                            if (_technology.isNotEmpty)
                              _infoRow(
                                'Tecnologia',
                                _technology,
                              ),

                            if (_standard.isNotEmpty)
                              _infoRow(
                                'Standard',
                                _standard,
                              ),

                            if (_ndef.isNotEmpty)
                              _infoRow(
                                'NDEF',
                                _ndef,
                              ),

                            if (_technology.isNotEmpty) ...[
                              const Divider(),

                              _infoRow(
                                'Settori autenticati',
                                '$_authenticatedSectors / 16',
                              ),

                              _infoRow(
                                'Settori leggibili',
                                '$_readableSectors / 16',
                              ),

                              _infoRow(
                                'Blocchi letti',
                                '$_readBlocks / 64',
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    if (_sectors.isNotEmpty) ...[
                      const Text(
                        'RISULTATO LETTURA',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 10),

                      for (final sector in _sectors)
                        _buildSectorCard(sector),
                    ],

                    if (_sectors.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(
                          top: 30,
                          bottom: 30,
                        ),
                        child: Center(
                          child: Text(
                            'Avvia una scansione per leggere il tag.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Pulsante sempre visibile.
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                boxShadow: const [
                  BoxShadow(
                    blurRadius: 8,
                    offset: Offset(0, -2),
                    color: Colors.black12,
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _reading ? null : _scanTag,
                  icon: Icon(
                    _reading
                        ? Icons.hourglass_top
                        : Icons.nfc,
                  ),
                  label: Text(
                    _reading
                        ? 'LETTURA IN CORSO...'
                        : 'CERCA TAG NFC',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
