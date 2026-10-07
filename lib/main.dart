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
      title: 'Tools',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MifareClassicPage(),
    );
  }
}

class SectorResult {
  final int sector;
  final bool authenticated;
  final String? key;
  final String? keyType;
  final List<BlockResult> blocks;
  final String? authenticationError;
  final String? trailer;
  final String? accessBits;
  final List<String> analysis;

  const SectorResult({
    required this.sector,
    required this.authenticated,
    required this.key,
    required this.keyType,
    required this.blocks,
    required this.authenticationError,
    required this.trailer,
    required this.accessBits,
    required this.analysis,
  });
}

class BlockResult {
  final int block;
  final String data;
  final bool success;
  final String? error;
  final List<String> analysis;

  const BlockResult({
    required this.block,
    required this.data,
    required this.success,
    required this.error,
    required this.analysis,
  });
}

class MifareClassicPage extends StatefulWidget {
  const MifareClassicPage({super.key});

  @override
  State<MifareClassicPage> createState() => _MifareClassicPageState();
}

class _MifareClassicPageState extends State<MifareClassicPage> {
  bool _reading = false;

  String _status = 'Pronto';
  String _uid = '';
  String _technology = '';
  String _standard = '';
  String _ndef = '';

  int _authenticatedSectors = 0;
  int _readBlocks = 0;

  List<SectorResult> _sectors = [];

  /*
   * SOLO CHIAVI NOTE/CANDIDATE.
   *
   * Non viene effettuato brute-force.
   * Non vengono generate nuove chiavi.
   */
  static const List<String> _knownKeys = [
    // Default MIFARE Classic
    'FFFFFFFFFFFF',
    '000000000000',

    // Chiavi già trovate/testate sul nostro tag
    'A0A1A2A3A4A5',
    'B0B1B2B3B4B5',
    'D3F7D3F7D3F7',
    '4D3A99C351DD',

    // Chiavi comuni pubblicamente note
    'A0B0C0D0E0F0',
    'A1B1C1D1E1F1',
    'AABBCCDDEEFF',
    '714C5C886E97',
    '587EE5F9350F',
    '0000014B5C8E',
    'AABBCCDDEEFF',
    '123456789ABC',
    '123456ABCDEF',
    '010203040506',
    'FEDCBA987654',
    '1A982C7E459A',
    '000000000001',
    'FFFFFFFFFFFF',
  ];

  Future<void> _startRead() async {
    if (_reading) return;

    setState(() {
      _reading = true;
      _status = 'In attesa del tag NFC...';
      _uid = '';
      _technology = '';
      _standard = '';
      _ndef = '';
      _authenticatedSectors = 0;
      _readBlocks = 0;
      _sectors = [];
    });

    try {
      final tag = await FlutterNfcKit.poll(
        timeout: const Duration(seconds: 30),
        androidCheckNDEF: false,
      );

      if (tag.type != NFCTagType.mifare_classic) {
        setState(() {
          _status = 'TAG NON COMPATIBILE';
          _uid = tag.id;
          _technology = tag.type.toString();
          _standard = tag.standard;
          _ndef = tag.ndefAvailable == true
              ? 'Disponibile'
              : 'Non disponibile';
        });

        await FlutterNfcKit.finish(
          iosAlertMessage: 'Tag non compatibile',
        );

        return;
      }

      setState(() {
        _status = 'TAG RILEVATO — analisi in corso...';
        _uid = tag.id;
        _technology = tag.type.toString();
        _standard = tag.standard;
        _ndef = tag.ndefAvailable == true
            ? 'Disponibile'
            : 'Non disponibile';
      });

      final results = <SectorResult>[];

      for (int sector = 0; sector < 16; sector++) {
        if (!mounted) return;

        setState(() {
          _status = 'Analisi settore ${sector + 1} / 16...';
        });

        final result = await _readSectorWithKnownKeys(sector);
        results.add(result);

        if (result.authenticated) {
          _authenticatedSectors++;
        }

        _readBlocks += result.blocks.where((b) => b.success).length;

        if (mounted) {
          setState(() {
            _sectors = List<SectorResult>.from(results);
          });
        }
      }

      final interesting = _findInterestingSectors(results);

      setState(() {
        _status = interesting.isEmpty
            ? 'LETTURA COMPLETATA'
            : 'LETTURA COMPLETATA — DATI INTERESSANTI TROVATI';
      });
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

  Future<SectorResult> _readSectorWithKnownKeys(int sector) async {
    String? foundKey;
    String? foundKeyType;

    /*
     * Prima proviamo Key A, poi Key B.
     *
     * Non modifichiamo il tag.
     */
    for (final key in _knownKeys) {
      try {
        final ok = await FlutterNfcKit.authenticateSector(
          sector,
          keyA: key,
        );

        if (ok == true) {
          foundKey = key;
          foundKeyType = 'Key A';
          break;
        }
      } catch (_) {
        // Continuiamo con la chiave successiva.
      }
    }

    if (foundKey == null) {
      for (final key in _knownKeys) {
        try {
          final ok = await FlutterNfcKit.authenticateSector(
            sector,
            keyB: key,
          );

          if (ok == true) {
            foundKey = key;
            foundKeyType = 'Key B';
            break;
          }
        } catch (_) {
          // Continuiamo con la chiave successiva.
        }
      }
    }

    if (foundKey == null) {
      return SectorResult(
        sector: sector,
        authenticated: false,
        key: null,
        keyType: null,
        blocks: const [],
        authenticationError: 'Nessuna chiave conosciuta accettata',
        trailer: null,
        accessBits: null,
        analysis: const [],
      );
    }

    final blocks = <BlockResult>[];

    /*
     * MIFARE Classic 1K:
     *
     * settore 0 -> blocchi 0,1,2,3
     * settore 1 -> blocchi 4,5,6,7
     * ...
     * settore 15 -> blocchi 60,61,62,63
     */
    final firstBlock = sector * 4;

    for (int offset = 0; offset < 3; offset++) {
      final blockNumber = firstBlock + offset;

      try {
        final raw = await FlutterNfcKit.readBlock(blockNumber);
        final hex = _toHex(raw);

        blocks.add(
          BlockResult(
            block: blockNumber,
            data: hex,
            success: true,
            error: null,
            analysis: _analyzeBlock(raw),
          ),
        );
      } catch (e) {
        blocks.add(
          BlockResult(
            block: blockNumber,
            data: '',
            success: false,
            error: e.toString(),
            analysis: const [],
          ),
        );

        /*
         * Se un blocco dati fallisce, non continuiamo a martellare
         * il tag: passiamo direttamente al settore successivo.
         */
        break;
      }
    }

    /*
     * Proviamo anche a leggere il sector trailer.
     *
     * Le chiavi A/B normalmente non sono restituite come dati leggibili:
     * NXP documenta che quando vengono lette restituiscono zeri logici.
     * Ci interessano soprattutto access bits e GPB.
     */
    String? trailer;
    String? accessBits;

    try {
      final trailerBlock = firstBlock + 3;
      final rawTrailer = await FlutterNfcKit.readBlock(trailerBlock);

      trailer = _toHex(rawTrailer);

      if (rawTrailer.length >= 9) {
        final bytes = rawTrailer;

        accessBits =
            '${_byteHex(bytes[6])} '
            '${_byteHex(bytes[7])} '
            '${_byteHex(bytes[8])}';

        blocks.add(
          BlockResult(
            block: trailerBlock,
            data: trailer,
            success: true,
            error: null,
            analysis: [
              'SECTOR TRAILER',
              'Access bits: $accessBits',
              'GPB: ${_byteHex(bytes[9])}',
            ],
          ),
        );
      }
    } catch (e) {
      /*
       * Il trailer può non essere leggibile anche quando
       * i blocchi dati lo sono. Non consideriamo questo
       * un errore dell'intero settore.
       */
    }

    final analysis = <String>[];

    for (final block in blocks) {
      analysis.addAll(
        block.analysis.map(
          (item) => 'Blocco ${block.block}: $item',
        ),
      );
    }

    if (accessBits != null) {
      analysis.add('Access bits rilevati: $accessBits');
    }

    return SectorResult(
      sector: sector,
      authenticated: true,
      key: foundKey,
      keyType: foundKeyType,
      blocks: blocks,
      authenticationError: null,
      trailer: trailer,
      accessBits: accessBits,
      analysis: analysis,
    );
  }

  List<String> _analyzeBlock(List<int> bytes) {
    final result = <String>[];

    if (bytes.length != 16) {
      result.add('Lunghezza inattesa: ${bytes.length} byte');
      return result;
    }

    /*
     * Riconoscimento MIFARE Value Block.
     *
     * Struttura documentata da NXP:
     *
     * value
     * ~value
     * value
     * address
     * ~address
     * address
     * ~address
     */
    if (_isValueBlock(bytes)) {
      final value = _decodeSignedLittleEndian32(bytes, 0);
      final address = bytes[12];

      result.add('POSSIBILE VALUE BLOCK');
      result.add('Valore grezzo: $value');
      result.add('Address: 0x${_byteHex(address)}');

      return result;
    }

    /*
     * Cerchiamo anche pattern evidenti:
     * - tutti zero
     * - ripetizioni
     * - ASCII
     */
    if (bytes.every((b) => b == 0)) {
      result.add('Blocco completamente a zero');
    }

    if (_hasRepeatedPattern(bytes)) {
      result.add('Contiene pattern ripetuti');
    }

    final ascii = _extractPrintableAscii(bytes);

    if (ascii.isNotEmpty) {
      result.add('ASCII: $ascii');
    }

    return result;
  }

  bool _isValueBlock(List<int> b) {
    if (b.length != 16) return false;

    final v0 = b[0];
    final v1 = b[1];
    final v2 = b[2];
    final v3 = b[3];

    final n0 = b[4];
    final n1 = b[5];
    final n2 = b[6];
    final n3 = b[7];

    final v20 = b[8];
    final v21 = b[9];
    final v22 = b[10];
    final v23 = b[11];

    final address = b[12];
    final notAddress = b[13];
    final address2 = b[14];
    final notAddress2 = b[15];

    final valueCopyMatches =
        v0 == v20 &&
        v1 == v21 &&
        v2 == v22 &&
        v3 == v23;

    final complementMatches =
        n0 == (0xFF ^ v0) &&
        n1 == (0xFF ^ v1) &&
        n2 == (0xFF ^ v2) &&
        n3 == (0xFF ^ v3);

    final addressMatches =
        notAddress == (0xFF ^ address) &&
        address2 == address &&
        notAddress2 == (0xFF ^ address);

    return valueCopyMatches &&
        complementMatches &&
        addressMatches;
  }

  int _decodeSignedLittleEndian32(List<int> b, int offset) {
    final unsigned =
        b[offset] |
        (b[offset + 1] << 8) |
        (b[offset + 2] << 16) |
        (b[offset + 3] << 24);

    if ((unsigned & 0x80000000) != 0) {
      return unsigned - 0x100000000;
    }

    return unsigned;
  }

  bool _hasRepeatedPattern(List<int> bytes) {
    if (bytes.length < 4) return false;

    for (int size = 1; size <= 4; size++) {
      if (bytes.length % size != 0) continue;

      final pattern = bytes.sublist(0, size);
      bool matches = true;

      for (int i = size; i < bytes.length; i++) {
        if (bytes[i] != pattern[i % size]) {
          matches = false;
          break;
        }
      }

      if (matches) return true;
    }

    return false;
  }

  String _extractPrintableAscii(List<int> bytes) {
    final chars = <int>[];

    for (final b in bytes) {
      if (b >= 32 && b <= 126) {
        chars.add(b);
      } else {
        chars.add(32);
      }
    }

    final value = utf8.decode(
      chars,
      allowMalformed: true,
    ).trim();

    if (value.replaceAll(' ', '').length < 3) {
      return '';
    }

    return value;
  }

  List<SectorResult> _findInterestingSectors(
    List<SectorResult> sectors,
  ) {
    return sectors.where((sector) {
      return sector.analysis.any(
        (text) =>
            text.contains('VALUE BLOCK') ||
            text.contains('Valore grezzo'),
      );
    }).toList();
  }

  String _toHex(List<int> bytes) {
    return bytes
        .map(_byteHex)
        .join(' ');
  }

  String _byteHex(int value) {
    return value.toRadixString(16).padLeft(2, '0').toUpperCase();
  }

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Widget _infoCard(String title, String value) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 125,
              child: Text(
                title,
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
      ),
    );
  }

  Widget _buildSectorCard(SectorResult sector) {
    final hasValueBlock = sector.analysis.any(
      (text) => text.contains('VALUE BLOCK'),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        initiallyExpanded: sector.sector == 0 || hasValueBlock,
        leading: Icon(
          sector.authenticated
              ? (hasValueBlock ? Icons.star : Icons.lock_open)
              : Icons.lock,
        ),
        title: Text(
          'Settore ${sector.sector + 1}',
        ),
        subtitle: sector.authenticated
            ? Text(
                '${sector.keyType}: ${sector.key}',
              )
            : const Text(
                'AUTENTICAZIONE FALLITA',
              ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              16,
              0,
              16,
              16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (sector.authenticated) ...[
                  Text(
                    'AUTENTICATO',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('Metodo: ${sector.keyType}'),
                  Text('Chiave: ${sector.key}'),
                  if (sector.accessBits != null)
                    Text(
                      'Access bits: ${sector.accessBits}',
                    ),
                  const SizedBox(height: 12),
                ] else ...[
                  Text(
                    sector.authenticationError ??
                        'Autenticazione fallita',
                    style: TextStyle(
                      color: Colors.red.shade700,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                for (final block in sector.blocks)
                  _buildBlockCard(block),

                if (sector.analysis.isNotEmpty) ...[
                  const Divider(),
                  const Text(
                    'ANALISI',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final item in sector.analysis)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• $item'),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlockCard(BlockResult block) {
    final interesting = block.analysis.any(
      (x) => x.contains('VALUE BLOCK'),
    );

    return Card(
      color: interesting
          ? Theme.of(context).colorScheme.secondaryContainer
          : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Blocco ${block.block}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Icon(
                  block.success
                      ? Icons.check_circle
                      : Icons.error,
                  size: 20,
                  color: block.success
                      ? Colors.green
                      : Colors.red,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (block.success)
              SelectableText(
                block.data,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
              )
            else
              Text(
                block.error ?? 'Errore sconosciuto',
                style: const TextStyle(
                  color: Colors.red,
                ),
              ),
            if (block.analysis.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final item in block.analysis)
                Text(
                  '→ $item',
                  style: TextStyle(
                    fontWeight: item.contains('VALUE BLOCK')
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummary() {
    final interesting = _findInterestingSectors(_sectors);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'RISULTATO',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Settori autenticati: '
              '$_authenticatedSectors / 16',
            ),
            Text(
              'Blocchi letti: '
              '$_readBlocks / 64',
            ),
            const SizedBox(height: 10),
            if (interesting.isEmpty)
              const Text(
                'Nessun Value Block riconosciuto '
                'nei blocchi accessibili.',
              )
            else ...[
              Text(
                'Settori interessanti: '
                '${interesting.map((s) => s.sector + 1).join(', ')}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'È stato riconosciuto almeno un possibile '
                'Value Block.',
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
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.nfc,
                            size: 48,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'MIFARE Classic 1K',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Diagnostica NFC e analisi memoria',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _status,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _status.contains('ERRORE')
                                  ? Colors.red
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (_uid.isNotEmpty) ...[
                    _infoCard('UID', _uid),
                    _infoCard(
                      'Tecnologia',
                      _technology,
                    ),
                    _infoCard(
                      'Standard',
                      _standard,
                    ),
                    _infoCard(
                      'NDEF',
                      _ndef,
                    ),
                  ],

                  if (_sectors.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _buildSummary(),
                    const SizedBox(height: 8),
                    for (final sector in _sectors)
                      _buildSectorCard(sector),
                  ],

                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),

          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(
                12,
                8,
                12,
                12,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .scaffoldBackgroundColor,
                boxShadow: const [
                  BoxShadow(
                    blurRadius: 8,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed:
                      _reading ? null : _startRead,
                  icon: Icon(
                    _reading
                        ? Icons.hourglass_top
                        : Icons.nfc,
                  ),
                  label: Text(
                    _reading
                        ? 'LETTURA IN CORSO...'
                        : 'CERCA E ANALIZZA TAG NFC',
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
