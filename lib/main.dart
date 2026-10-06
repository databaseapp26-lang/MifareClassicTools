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
      home: const MifareHomePage(),
    );
  }
}

class BlockData {
  final int sector;
  final int block;
  final String keyType;
  final String key;
  final String data;
  final String? error;

  const BlockData({
    required this.sector,
    required this.block,
    required this.keyType,
    required this.key,
    required this.data,
    this.error,
  });

  bool get success => error == null;
}

class SectorResult {
  final int sector;
  final bool authenticated;
  final String keyType;
  final String key;
  final List<BlockData> blocks;

  const SectorResult({
    required this.sector,
    required this.authenticated,
    required this.keyType,
    required this.key,
    required this.blocks,
  });

  int get successfulBlocks =>
      blocks.where((block) => block.success).length;
}

class MifareHomePage extends StatefulWidget {
  const MifareHomePage({super.key});

  @override
  State<MifareHomePage> createState() => _MifareHomePageState();
}

class _MifareHomePageState extends State<MifareHomePage> {
  static const List<String> _knownKeys = [
    'FFFFFFFFFFFF',
    'A0A1A2A3A4A5',
    'D3F7D3F7D3F7',
    'B0B1B2B3B4B5',
    '4D3A99C351DD',
    '000000000000',
  ];

  bool _reading = false;
  String _status = 'PRONTO';
  String? _uid;
  NFCTag? _tag;

  final List<SectorResult> _sectors = [];

  int get _authenticatedSectors =>
      _sectors.where((sector) => sector.authenticated).length;

  int get _readBlocks =>
      _sectors.fold(0, (sum, sector) => sum + sector.successfulBlocks);

  int get _totalBlocks => 64;

  Future<void> _readTag() async {
    if (_reading) {
      return;
    }

    setState(() {
      _reading = true;
      _status = 'RICERCA TAG...';
      _uid = null;
      _tag = null;
      _sectors.clear();
    });

    try {
      final tag = await FlutterNfcKit.poll(
        timeout: const Duration(seconds: 20),
        androidCheckNDEF: false,
      );

      _tag = tag;
      _uid = tag.id;

      setState(() {
        _status = 'TAG RILEVATO';
      });

      await _scanTag();
    } catch (e) {
      setState(() {
        _status = 'ERRORE';
      });

      _showMessage('Errore durante la lettura:\n$e');
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

  Future<void> _scanTag() async {
    final List<SectorResult> results = [];

    for (int sector = 0; sector < 16; sector++) {
      if (!mounted) {
        return;
      }

      setState(() {
        _status = 'SCANSIONE SETTORE ${sector + 1} / 16...';
      });

      SectorResult? result;

      // Prima proviamo tutte le chiavi come Key A.
      for (final key in _knownKeys) {
        try {
          final authenticated = await FlutterNfcKit.authenticateSector(
            sector,
            keyA: key,
          );

          if (authenticated) {
            result = await _readSectorBlocks(
              sector: sector,
              keyType: 'Key A',
              key: key,
            );
            break;
          }
        } catch (_) {}
      }

      // Se Key A non funziona, proviamo Key B.
      if (result == null) {
        for (final key in _knownKeys) {
          try {
            final authenticated = await FlutterNfcKit.authenticateSector(
              sector,
              keyB: key,
            );

            if (authenticated) {
              result = await _readSectorBlocks(
                sector: sector,
                keyType: 'Key B',
                key: key,
              );
              break;
            }
          } catch (_) {}
        }
      }

      // Nessuna chiave conosciuta ha funzionato.
      result ??= SectorResult(
        sector: sector,
        authenticated: false,
        keyType: '-',
        key: '-',
        blocks: const [],
      );

      results.add(result);

      if (mounted) {
        setState(() {
          _sectors
            ..clear()
            ..addAll(results);
        });
      }
    }

    if (mounted) {
      setState(() {
        _status = 'LETTURA COMPLETATA';
      });
    }
  }

  Future<SectorResult> _readSectorBlocks({
    required int sector,
    required String keyType,
    required String key,
  }) async {
    final List<BlockData> blocks = [];

    final int firstBlock = sector * 4;
    final int lastBlock = firstBlock + 3;

    for (int block = firstBlock; block <= lastBlock; block++) {
      try {
        final data = await FlutterNfcKit.readBlock(block);

        blocks.add(
          BlockData(
            sector: sector,
            block: block,
            keyType: keyType,
            key: key,
            data: _formatBytes(data),
          ),
        );
      } catch (e) {
        blocks.add(
          BlockData(
            sector: sector,
            block: block,
            keyType: keyType,
            key: key,
            data: '',
            error: e.toString(),
          ),
        );
      }
    }

    return SectorResult(
      sector: sector,
      authenticated: true,
      keyType: keyType,
      key: key,
      blocks: blocks,
    );
  }

  String _formatBytes(dynamic data) {
    if (data is List<int>) {
      return data
          .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(' ');
    }

    if (data is String) {
      return data;
    }

    return data.toString();
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 145,
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

  Widget _buildBlock(BlockData block) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(
          color: block.success
              ? Colors.green.withValues(alpha: 0.4)
              : Colors.red.withValues(alpha: 0.4),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Block ${block.block}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          if (block.success)
            SelectableText(
              block.data,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
              ),
            )
          else
            SelectableText(
              'ERRORE: ${block.error}',
              style: const TextStyle(
                color: Colors.red,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSector(SectorResult sector) {
    final readable = sector.successfulBlocks;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SETTORE ${sector.sector + 1}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            _infoRow(
              'Stato',
              sector.authenticated
                  ? 'AUTENTICATO'
                  : 'AUTENTICAZIONE FALLITA',
            ),
            if (sector.authenticated) ...[
              _infoRow('Metodo', sector.keyType),
              _infoRow('Chiave', sector.key),
              _infoRow('Blocchi letti', '$readable / 4'),
              const SizedBox(height: 4),
              ...sector.blocks.map(_buildBlock),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tag = _tag;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tools'),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'MIFARE Classic 1K',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Lettura e strumenti NFC',
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
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: _status == 'ERRORE'
                                  ? Colors.red
                                  : Colors.blue,
                            ),
                          ),
                          const SizedBox(height: 12),

                          if (tag != null) ...[
                            _infoRow(
                              'UID',
                              tag.id,
                            ),
                            _infoRow(
                              'Tecnologia',
                              tag.type.toString(),
                            ),
                            _infoRow(
                              'Standard',
                              tag.standard.toString(),
                            ),
                            _infoRow(
                              'NDEF',
                              tag.ndefAvailable == true
                                  ? 'Disponibile'
                                  : 'Non disponibile',
                            ),
                          ],

                          if (_sectors.isNotEmpty) ...[
                            const Divider(height: 24),
                            _infoRow(
                              'Settori autenticati',
                              '$_authenticatedSectors / 16',
                            ),
                            _infoRow(
                              'Blocchi letti',
                              '$_readBlocks / $_totalBlocks',
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  if (_sectors.isNotEmpty)
                    ..._sectors.map(_buildSector),

                  if (_sectors.isEmpty && !_reading)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'Premi il pulsante qui sotto per cercare '
                          'un tag MIFARE Classic 1K.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),

          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _reading ? null : _readTag,
                  child: Text(
                    _reading ? 'LETTURA IN CORSO...' : 'CERCA TAG NFC',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
