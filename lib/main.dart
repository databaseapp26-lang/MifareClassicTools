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
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F6FA),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // ============================================================
  // CHIAVI CONOSCIUTE
  //
  // Sono solamente chiavi note/comuni.
  // Non viene effettuato alcun cracking o brute force.
  // ============================================================

  static const List<String> _knownKeys = [
    // Chiavi MIFARE Classic comuni
    'FFFFFFFFFFFF',
    '000000000000',
    'A0A1A2A3A4A5',
    'B0B1B2B3B4B5',
    'D3F7D3F7D3F7',
    '4D3A99C351DD',

    // Chiavi già utilizzate/testate
    'A0B0C0D0E0F0',
    'A1B1C1D1E1F1',
    'AABBCCDDEEFF',
    '714C5C886E97',
    '587EE5F9350F',
    '1A982C7E459A',

    // Altre chiavi pubbliche/comuni
    'A0478CC39091',
    '533CB6C723F6',
    '8FD0A4F256E9',
  ];

  final TextEditingController _extraKeyController =
      TextEditingController();

  bool _reading = false;

  String _status = 'Pronto';

  NFCTag? _tag;

  int _authenticatedSectors = 0;
  int _readBlocks = 0;

  final List<SectorResult> _sectors = [];

  @override
  void dispose() {
    _extraKeyController.dispose();
    super.dispose();
  }

  // ============================================================
  // FUNZIONI UTILI
  // ============================================================

  String _normalizeKey(String value) {
    return value
        .trim()
        .replaceAll(' ', '')
        .replaceAll(':', '')
        .replaceAll('-', '')
        .toUpperCase();
  }

  bool _isValidKey(String key) {
    if (key.length != 12) {
      return false;
    }

    return RegExp(r'^[0-9A-F]{12}$').hasMatch(key);
  }

  List<String> _allKeys() {
    final keys = <String>[
      ..._knownKeys,
    ];

    final extra = _normalizeKey(_extraKeyController.text);

    if (_isValidKey(extra) && !keys.contains(extra)) {
      keys.add(extra);
    }

    return keys;
  }

  String _hex(List<int> data) {
    return data
        .map(
          (b) => b.toRadixString(16).padLeft(2, '0').toUpperCase(),
        )
        .join(' ');
  }

  String _hexCompact(List<int> data) {
    return data
        .map(
          (b) => b.toRadixString(16).padLeft(2, '0').toUpperCase(),
        )
        .join();
  }

  String _ascii(List<int> data) {
    return data
        .map(
          (b) => b >= 32 && b <= 126
              ? String.fromCharCode(b)
              : '.',
        )
        .join();
  }

  bool _isAllZero(List<int> data) {
    return data.every((b) => b == 0);
  }

  bool _looksLikeValueBlock(List<int> data) {
    if (data.length != 16) {
      return false;
    }

    final value0 = data.sublist(0, 4);
    final inverse = data.sublist(4, 8);
    final value1 = data.sublist(8, 12);

    for (int i = 0; i < 4; i++) {
      if ((value0[i] ^ inverse[i]) != 0xFF) {
        return false;
      }

      if (value0[i] != value1[i]) {
        return false;
      }
    }

    return true;
  }

  int _littleEndianValue(List<int> data) {
    if (data.length < 4) {
      return 0;
    }

    return data[0] |
        (data[1] << 8) |
        (data[2] << 16) |
        (data[3] << 24);
  }

  // ============================================================
  // DECODIFICA ACCESS BITS
  //
  // Per un trailer MIFARE Classic:
  // byte 6,7,8 = access bits
  // ============================================================

  String _decodeAccessBits(List<int> block) {
    if (block.length != 16) {
      return 'Dati insufficienti';
    }

    final b6 = block[6];
    final b7 = block[7];
    final b8 = block[8];

    final c1 = [
      (b7 >> 4) & 1,
      (b7 >> 0) & 1,
      (b8 >> 4) & 1,
      (b8 >> 0) & 1,
    ];

    final c2 = [
      (b6 >> 4) & 1,
      (b6 >> 0) & 1,
      (b7 >> 4) & 1,
      (b7 >> 0) & 1,
    ];

    final c3 = [
      (b6 >> 5) & 1,
      (b6 >> 1) & 1,
      (b7 >> 5) & 1,
      (b7 >> 1) & 1,
    ];

    final valid =
        (((b6 ^ b7) & 0x0F) == 0x0F) &&
        (((b7 ^ b8) & 0xF0) == 0xF0);

    if (!valid) {
      return 'Access bits: $b6/$b7/$b8 - configurazione da verificare';
    }

    return 'Access bits: '
        '${b6.toRadixString(16).padLeft(2, '0').toUpperCase()} '
        '${b7.toRadixString(16).padLeft(2, '0').toUpperCase()} '
        '${b8.toRadixString(16).padLeft(2, '0').toUpperCase()}'
        '\n'
        'C1: ${c1.join()}  '
        'C2: ${c2.join()}  '
        'C3: ${c3.join()}';
  }

  String _blockAnalysis(int blockNumber, List<int> data) {
    final lines = <String>[];

    if (_isAllZero(data)) {
      lines.add('Blocco completamente vuoto');
    }

    if (_looksLikeValueBlock(data)) {
      final value = _littleEndianValue(data);

      lines.add('Possibile MIFARE Value Block');
      lines.add('Valore raw little-endian: $value');
    }

    final ascii = _ascii(data);

    if (ascii.replaceAll('.', '').isNotEmpty) {
      lines.add('ASCII: $ascii');
    }

    if (blockNumber % 4 == 3) {
      if (data.length == 16) {
        lines.add('Sector Trailer');

        final keyA = data.sublist(0, 6);
        final access = data.sublist(6, 9);
        final gpb = data[9];
        final keyB = data.sublist(10, 16);

        lines.add('Key A: ${_hex(keyA)}');
        lines.add('Access: ${_hex(access)}');
        lines.add(
          'GPB: ${gpb.toRadixString(16).padLeft(2, '0').toUpperCase()}',
        );
        lines.add('Key B: ${_hex(keyB)}');

        lines.add(_decodeAccessBits(data));
      }
    }

    if (lines.isEmpty) {
      return 'Nessuna analisi speciale';
    }

    return lines.join('\n');
  }

  // ============================================================
  // LETTURA DI UN SETTORE
  //
  // IMPORTANTE:
  // usiamo readBlock() singolarmente.
  // È il metodo che ha funzionato correttamente sul tuo tag.
  // ============================================================

  Future<SectorResult> _readSector(int sector) async {
    String? usedKey;
    String? usedKeyType;

    // ------------------------------------------------------------
    // 1. Tentiamo le chiavi conosciute
    // ------------------------------------------------------------

    for (final key in _allKeys()) {
      try {
        final ok = await FlutterNfcKit.authenticateSector(
          sector,
          keyA: key,
        );

        if (ok) {
          usedKey = key;
          usedKeyType = 'Key A';
          break;
        }
      } catch (_) {
        // Proviamo la chiave successiva.
      }

      try {
        final ok = await FlutterNfcKit.authenticateSector(
          sector,
          keyB: key,
        );

        if (ok) {
          usedKey = key;
          usedKeyType = 'Key B';
          break;
        }
      } catch (_) {
        // Proviamo la chiave successiva.
      }
    }

    if (usedKey == null) {
      return SectorResult(
        sector: sector,
        authenticated: false,
        key: null,
        keyType: null,
        blocks: [],
        errors: const [
          'Nessuna chiave conosciuta accettata',
        ],
      );
    }

    // ------------------------------------------------------------
    // 2. Leggiamo i 4 blocchi singolarmente
    // ------------------------------------------------------------

    final blocks = <BlockResult>[];
    final errors = <String>[];

    final firstBlock = sector * 4;

    for (int offset = 0; offset < 4; offset++) {
      final blockIndex = firstBlock + offset;

      try {
        final data = await FlutterNfcKit.readBlock(blockIndex);

        blocks.add(
          BlockResult(
            blockIndex: blockIndex,
            data: List<int>.from(data),
            error: null,
          ),
        );

        _readBlocks++;
      } catch (e) {
        errors.add(
          'Blocco $blockIndex: ${_cleanError(e)}',
        );

        blocks.add(
          BlockResult(
            blockIndex: blockIndex,
            data: null,
            error: _cleanError(e),
          ),
        );
      }

      if (mounted) {
        setState(() {});
      }
    }

    return SectorResult(
      sector: sector,
      authenticated: true,
      key: usedKey,
      keyType: usedKeyType,
      blocks: blocks,
      errors: errors,
    );
  }

  String _cleanError(Object error) {
    final text = error.toString();

    if (text.contains('Communication error')) {
      return 'Errore di comunicazione NFC';
    }

    if (text.contains('Transceive failed')) {
      return 'Transceive fallito';
    }

    return text;
  }

  // ============================================================
  // AVVIO SCANSIONE
  // ============================================================

  Future<void> _scanTag() async {
    if (_reading) {
      return;
    }

    setState(() {
      _reading = true;
      _status = 'Avvicina il tag NFC...';
      _tag = null;
      _sectors.clear();
      _authenticatedSectors = 0;
      _readBlocks = 0;
    });

    try {
      final availability = await FlutterNfcKit.nfcAvailability;

      if (availability != NFCAvailability.available) {
        throw Exception(
          'NFC non disponibile sul dispositivo',
        );
      }

      final tag = await FlutterNfcKit.poll(
        timeout: const Duration(seconds: 20),
        androidCheckNDEF: false,
        readIso14443A: true,
        readIso14443B: false,
        readIso18092: false,
        readIso15693: false,
      );

      if (tag.type != NFCTagType.mifare_classic) {
        setState(() {
          _tag = tag;
          _status =
              'Tag rilevato, ma non è una MIFARE Classic';
        });

        return;
      }

      setState(() {
        _tag = tag;
        _status = 'MIFARE Classic rilevata';
      });

      // ----------------------------------------------------------
      // Scansione dei 16 settori
      // ----------------------------------------------------------

      for (int sector = 0; sector < 16; sector++) {
        if (!mounted) {
          return;
        }

        setState(() {
          _status =
              'Analisi settore ${sector + 1} / 16...';
        });

        final result = await _readSector(sector);

        _sectors.add(result);

        if (result.authenticated) {
          _authenticatedSectors++;
        }

        if (mounted) {
          setState(() {});
        }
      }

      setState(() {
        _status = 'LETTURA COMPLETATA';
      });
    } catch (e) {
      setState(() {
        _status = 'Errore: ${_cleanError(e)}';
      });
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

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Tools',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  120,
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.stretch,
                  children: [
                    _buildHeaderCard(),
                    const SizedBox(height: 14),
                    _buildStatusCard(),
                    if (_tag != null) ...[
                      const SizedBox(height: 14),
                      _buildTagInfoCard(),
                      const SizedBox(height: 14),
                      _buildSummaryCard(),
                    ],
                    if (_sectors.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      const Text(
                        'SETTORI',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._sectors.map(
                        (sector) =>
                            _buildSectorCard(sector),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // ----------------------------------------------------
            // Pulsante fisso
            // ----------------------------------------------------

            Container(
              padding: const EdgeInsets.fromLTRB(
                16,
                10,
                16,
                16,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .scaffoldBackgroundColor,
                boxShadow: const [
                  BoxShadow(
                    blurRadius: 12,
                    offset: Offset(0, -3),
                    color: Color(0x22000000),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed:
                      _reading ? null : _scanTag,
                  icon: Icon(
                    _reading
                        ? Icons.nfc
                        : Icons.contactless,
                  ),
                  label: Text(
                    _reading
                        ? 'LETTURA IN CORSO...'
                        : 'CERCA E ANALIZZA TAG NFC',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: const [
            Text(
              'MIFARE Classic 1K',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Lettura e analisi NFC',
              style: TextStyle(
                fontSize: 15,
                color: Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final isError = _status.startsWith('Errore');

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Icon(
              isError
                  ? Icons.error_outline
                  : _reading
                      ? Icons.sync
                      : Icons.info_outline,
              size: 30,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  const Text(
                    'STATO',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _status,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTagInfoCard() {
    final tag = _tag!;

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const Text(
              'INFORMAZIONI TAG',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
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
            _infoRow(
              'Dimensione NDEF',
              '${tag.ndefCapacity}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    final readablePercentage =
        (_readBlocks / 64 * 100).round();

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const Text(
              'RIEPILOGO',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 14),
            _summaryRow(
              Icons.lock_open,
              'Settori autenticati',
              '$_authenticatedSectors / 16',
            ),
            _summaryRow(
              Icons.view_module,
              'Blocchi letti',
              '$_readBlocks / 64',
            ),
            _summaryRow(
              Icons.analytics_outlined,
              'Copertura',
              '$readablePercentage%',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _extraKeyController,
              textCapitalization:
                  TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Chiave aggiuntiva',
                hintText: 'FFFFFFFFFFFF',
                border: OutlineInputBorder(),
                helperText:
                    'Inserisci solo una chiave MIFARE autorizzata da 6 byte',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(
    IconData icon,
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 125,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.black54,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectorCard(SectorResult sector) {
    final title =
        'Settore ${sector.sector + 1}';

    if (!sector.authenticated) {
      return Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ExpansionTile(
          leading: const Icon(
            Icons.lock_outline,
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: const Text(
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
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  sector.errors.isEmpty
                      ? 'Nessuna chiave conosciuta accettata.'
                      : sector.errors.join('\n'),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        initiallyExpanded: sector.sector == 0,
        leading: const Icon(
          Icons.lock_open,
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          'AUTENTICATO • '
          '${sector.keyType ?? ''} • '
          '${sector.blocks.where((b) => b.data != null).length}/4 blocchi',
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
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              children: [
                _detailLine(
                  'Metodo',
                  sector.keyType ?? '-',
                ),
                _detailLine(
                  'Chiave',
                  sector.key ?? '-',
                ),
                const SizedBox(height: 8),
                ...sector.blocks.map(
                  (block) => _buildBlockCard(
                    block,
                  ),
                ),
                if (sector.errors.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    sector.errors.join('\n'),
                    style: const TextStyle(
                      color: Colors.redAccent,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailLine(
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.black54,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlockCard(BlockResult block) {
    final data = block.data;

    if (data == null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.black.withOpacity(0.04),
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Text(
              'Block ${block.blockIndex}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              block.error ?? 'Blocco non leggibile',
              style: const TextStyle(
                color: Colors.redAccent,
              ),
            ),
          ],
        ),
      );
    }

    final analysis =
        _blockAnalysis(block.blockIndex, data);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.black.withOpacity(0.04),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            'Block ${block.blockIndex}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            _hex(data),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 5),
          SelectableText(
            _hexCompact(data),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            analysis,
            style: const TextStyle(
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ================================================================
// MODELLI
// ================================================================

class BlockResult {
  final int blockIndex;
  final List<int>? data;
  final String? error;

  const BlockResult({
    required this.blockIndex,
    required this.data,
    required this.error,
  });
}

class SectorResult {
  final int sector;
  final bool authenticated;
  final String? key;
  final String? keyType;
  final List<BlockResult> blocks;
  final List<String> errors;

  const SectorResult({
    required this.sector,
    required this.authenticated,
    required this.key,
    required this.keyType,
    required this.blocks,
    required this.errors,
  });
}
