import 'package:flutter/material.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';

import 'known_keys.dart';

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
  // CHIAVI PUBBLICHE / CONOSCIUTE
  //
  // Nessun cracking o brute force.
  // ============================================================

  static const List<String> _knownKeys = [
    'FFFFFFFFFFFF',
    '000000000000',
    'A0A1A2A3A4A5',
    'B0B1B2B3B4B5',
    'D3F7D3F7D3F7',
    '4D3A99C351DD',
    'A0B0C0D0E0F0',
    'A1B1C1D1E1F1',
    'AABBCCDDEEFF',
    '714C5C886E97',
    '587EE5F9350F',
    '1A982C7E459A',
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

  // ------------------------------------------------------------
  // DUMP A
  //
  // Viene mantenuto in memoria.
  // Non modifica la card.
  // ------------------------------------------------------------

  Map<int, List<int>>? _dumpA;
  DateTime? _dumpATime;

  // ============================================================
  // LIFECYCLE
  // ============================================================

  @override
  void dispose() {
    _extraKeyController.dispose();
    super.dispose();
  }

  // ============================================================
  // UTILITA'
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

    final extra = _normalizeKey(
      _extraKeyController.text,
    );

    if (_isValidKey(extra) && !keys.contains(extra)) {
      keys.add(extra);
    }

    return keys;
  }

  String _hex(List<int> data) {
    return data
        .map(
          (b) => b
              .toRadixString(16)
              .padLeft(2, '0')
              .toUpperCase(),
        )
        .join(' ');
  }

  String _hexCompact(List<int> data) {
    return data
        .map(
          (b) => b
              .toRadixString(16)
              .padLeft(2, '0')
              .toUpperCase(),
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

  // ============================================================
  // VALORI NUMERICI
  // ============================================================

  int _u16Le(List<int> data, int offset) {
    return data[offset] |
        (data[offset + 1] << 8);
  }

  int _u16Be(List<int> data, int offset) {
    return (data[offset] << 8) |
        data[offset + 1];
  }

  int _u32Le(List<int> data, int offset) {
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
  }

  int _u32Be(List<int> data, int offset) {
    return (data[offset] << 24) |
        (data[offset + 1] << 16) |
        (data[offset + 2] << 8) |
        data[offset + 3];
  }

  // ============================================================
  // VALUE BLOCK MIFARE
  // ============================================================

  bool _looksLikeValueBlock(List<int> data) {
    if (data.length != 16) {
      return false;
    }

    final value = data.sublist(0, 4);
    final inverse = data.sublist(4, 8);
    final valueCopy = data.sublist(8, 12);

    for (int i = 0; i < 4; i++) {
      if ((value[i] ^ inverse[i]) != 0xFF) {
        return false;
      }

      if (value[i] != valueCopy[i]) {
        return false;
      }
    }

    final address = data[12];
    final addressInverse = data[13];
    final addressCopy = data[14];
    final addressCopyInverse = data[15];

    final addressValid =
        ((address ^ addressInverse) & 0xFF) == 0xFF &&
        address == addressCopy &&
        ((addressCopy ^ addressCopyInverse) & 0xFF) == 0xFF;

    return addressValid;
  }

  int _valueBlockLittleEndian(List<int> data) {
    return _u32Le(data, 0);
  }

  // ============================================================
  // RICERCA DI POSSIBILI VALORI
  //
  // Non dichiara automaticamente "questo è il saldo".
  // Evidenzia solo candidati matematicamente interessanti.
  // ============================================================

  List<String> _findNumericCandidates(
    List<int> data,
  ) {
    final result = <String>[];

    if (data.length != 16) {
      return result;
    }

    // ----------------------------------------------------------
    // 16 bit
    // ----------------------------------------------------------

    for (int offset = 0; offset <= 14; offset++) {
      final le = _u16Le(data, offset);
      final be = _u16Be(data, offset);

      if (le <= 100000) {
        final euros = le / 100.0;

        if (le >= 1 && le <= 100000) {
          result.add(
            'offset $offset: '
            '16-bit LE=$le '
            '(${euros.toStringAsFixed(2)} € se centesimi)',
          );
        }
      }

      if (be <= 100000 && be >= 1) {
        final euros = be / 100.0;

        result.add(
          'offset $offset: '
          '16-bit BE=$be '
          '(${euros.toStringAsFixed(2)} € se centesimi)',
        );
      }
    }

    // ----------------------------------------------------------
    // 32 bit
    // ----------------------------------------------------------

    for (int offset = 0; offset <= 12; offset++) {
      final le = _u32Le(data, offset);
      final be = _u32Be(data, offset);

      // Limite volutamente conservativo.
      if (le >= 1 && le <= 10000000) {
        final euros = le / 100.0;

        result.add(
          'offset $offset: '
          '32-bit LE=$le '
          '(${euros.toStringAsFixed(2)} € se centesimi)',
        );
      }

      if (be >= 1 && be <= 10000000) {
        final euros = be / 100.0;

        result.add(
          'offset $offset: '
          '32-bit BE=$be '
          '(${euros.toStringAsFixed(2)} € se centesimi)',
        );
      }
    }

    return result;
  }

  // ============================================================
  // COMPLEMENTI
  // ============================================================

  List<String> _findComplementPatterns(
    List<int> data,
  ) {
    final result = <String>[];

    if (data.length != 16) {
      return result;
    }

    for (int offset = 0; offset <= 12; offset++) {
      final a = data.sublist(
        offset,
        offset + 4,
      );

      for (int other = offset + 4;
          other <= 12;
          other++) {
        final b = data.sublist(
          other,
          other + 4,
        );

        bool inverse = true;

        for (int i = 0; i < 4; i++) {
          if ((a[i] ^ b[i]) != 0xFF) {
            inverse = false;
            break;
          }
        }

        if (inverse) {
          result.add(
            'Complemento 32-bit: '
            'offset $offset ↔ offset $other',
          );
        }
      }
    }

    return result;
  }

  // ============================================================
  // ANALISI BLOCCO
  // ============================================================

  String _blockAnalysis(
    int blockNumber,
    List<int> data,
  ) {
    final lines = <String>[];

    if (_isAllZero(data)) {
      lines.add(
        'Blocco completamente vuoto',
      );
    }

    // ----------------------------------------------------------
    // Value Block
    // ----------------------------------------------------------

    if (_looksLikeValueBlock(data)) {
      final value = _valueBlockLittleEndian(data);

      lines.add(
        '★ VALUE BLOCK MIFARE RICONOSCIUTO',
      );

      lines.add(
        'Valore raw LE: $value',
      );

      lines.add(
        'Possibile importo: '
        '${(value / 100).toStringAsFixed(2)} € '
        'se il formato usa centesimi',
      );

      lines.add(
        'Address byte: '
        '${data[12].toRadixString(16).padLeft(2, '0').toUpperCase()}',
      );
    }

    // ----------------------------------------------------------
    // Candidati numerici
    // ----------------------------------------------------------

    final candidates = _findNumericCandidates(
      data,
    );

    if (candidates.isNotEmpty) {
      lines.add(
        'Possibili valori numerici:',
      );

      // Limitiamo la visualizzazione per non riempire
      // completamente lo schermo con falsi positivi.
      final shown = candidates.take(8);

      lines.addAll(shown);
    }

    // ----------------------------------------------------------
    // Complementi
    // ----------------------------------------------------------

    final complements =
        _findComplementPatterns(data);

    if (complements.isNotEmpty) {
      lines.addAll(complements.take(5));
    }

    // ----------------------------------------------------------
    // ASCII
    // ----------------------------------------------------------

    final ascii = _ascii(data);

    if (ascii.replaceAll('.', '').isNotEmpty) {
      lines.add(
        'ASCII: $ascii',
      );
    }

    // ----------------------------------------------------------
    // TRAILER
    // ----------------------------------------------------------

    if (blockNumber % 4 == 3) {
      if (data.length == 16) {
        lines.add(
          'Sector Trailer',
        );

        // NON mostriamo Key A come se fosse leggibile.
        lines.add(
          'Key A: non leggibile in chiaro '
          '(campo protetto)',
        );

        final access = data.sublist(6, 9);

        lines.add(
          'Access: ${_hex(access)}',
        );

        final gpb = data[9];

        lines.add(
          'GPB: '
          '${gpb.toRadixString(16).padLeft(2, '0').toUpperCase()}',
        );

        // Key B può essere non leggibile a seconda
        // della configurazione.
        lines.add(
          'Key B: non visualizzata come chiave '
          'in chiaro',
        );

        lines.add(
          _decodeAccessBits(data),
        );
      }
    }

    if (lines.isEmpty) {
      return 'Nessuna analisi speciale';
    }

    return lines.join('\n');
  }

  // ============================================================
  // ACCESS BITS
  // ============================================================

  String _decodeAccessBits(
    List<int> block,
  ) {
    if (block.length != 16) {
      return 'Dati insufficienti';
    }

    final b6 = block[6];
    final b7 = block[7];
    final b8 = block[8];

    // I tre byte vengono mostrati sempre in HEX.
    //
    // Non usiamo qui una formula semplificata per dichiarare
    // arbitrariamente C1/C2/C3.
    //
    // Questo evita interpretazioni errate del trailer.

    final c1c2c3 = _extractAccessGroups(
      b6,
      b7,
      b8,
    );

    return 'Access bits: '
        '${b6.toRadixString(16).padLeft(2, '0').toUpperCase()} '
        '${b7.toRadixString(16).padLeft(2, '0').toUpperCase()} '
        '${b8.toRadixString(16).padLeft(2, '0').toUpperCase()}\n'
        'C1/C2/C3: $c1c2c3';
  }

  String _extractAccessGroups(
    int b6,
    int b7,
    int b8,
  ) {
    // Rappresentazione diagnostica dei bit.
    //
    // La utilizziamo come supporto e non come prova
    // del significato economico del settore.

    final bits6 = b6
        .toRadixString(2)
        .padLeft(8, '0');

    final bits7 = b7
        .toRadixString(2)
        .padLeft(8, '0');

    final bits8 = b8
        .toRadixString(2)
        .padLeft(8, '0');

    return '$bits6 $bits7 $bits8';
  }

  // ============================================================
  // LETTURA SETTORE
  // ============================================================

  Future<SectorResult> _readSector(
    int sector,
  ) async {
    String? usedKey;
    String? usedKeyType;

    // ----------------------------------------------------------
    // Key A
    // ----------------------------------------------------------

    for (final key in _allKeys()) {
      try {
        final ok =
            await FlutterNfcKit.authenticateSector(
          sector,
          keyA: key,
        );

        if (ok) {
          usedKey = key;
          usedKeyType = 'Key A';
          break;
        }
      } catch (_) {}

      // --------------------------------------------------------
      // Key B
      // --------------------------------------------------------

      try {
        final ok =
            await FlutterNfcKit.authenticateSector(
          sector,
          keyB: key,
        );

        if (ok) {
          usedKey = key;
          usedKeyType = 'Key B';
          break;
        }
      } catch (_) {}
    }

    if (usedKey == null) {
      return SectorResult(
        sector: sector,
        authenticated: false,
        key: null,
        keyType: null,
        blocks: const [],
        errors: const [
          'Nessuna chiave conosciuta accettata',
        ],
      );
    }

    // ----------------------------------------------------------
    // Lettura singoli blocchi
    // ----------------------------------------------------------

    final blocks = <BlockResult>[];
    final errors = <String>[];

    final firstBlock = sector * 4;

    for (int offset = 0; offset < 4; offset++) {
      final blockIndex =
          firstBlock + offset;

      try {
        final data =
            await FlutterNfcKit.readBlock(
          blockIndex,
        );

        blocks.add(
          BlockResult(
            blockIndex: blockIndex,
            data: List<int>.from(data),
            error: null,
          ),
        );

        _readBlocks++;
      } catch (e) {
        final error =
            _cleanError(e);

        errors.add(
          'Blocco $blockIndex: $error',
        );

        blocks.add(
          BlockResult(
            blockIndex: blockIndex,
            data: null,
            error: error,
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

  String _cleanError(
    Object error,
  ) {
    final text = error.toString();

    if (text.contains(
      'Communication error',
    )) {
      return 'Errore di comunicazione NFC';
    }

    if (text.contains(
      'Transceive failed',
    )) {
      return 'Transceive fallito';
    }

    return text;
  }

  // ============================================================
  // COSTRUZIONE DUMP
  // ============================================================

  Map<int, List<int>> _createDump() {
    final dump = <int, List<int>>{};

    for (final sector in _sectors) {
      for (final block in sector.blocks) {
        if (block.data != null) {
          dump[block.blockIndex] =
              List<int>.from(block.data!);
        }
      }
    }

    return dump;
  }

  // ============================================================
  // SALVA DUMP A
  // ============================================================

  void _saveDumpA() {
    final dump = _createDump();

    if (dump.isEmpty) {
      _showMessage(
        'Non ci sono blocchi letti da salvare.',
      );
      return;
    }

    setState(() {
      _dumpA = dump;
      _dumpATime = DateTime.now();
    });

    _showMessage(
      'DUMP A salvato: ${dump.length} blocchi.',
    );
  }

  // ============================================================
  // CONFRONTO DUMP A / LETTURA ATTUALE
  // ============================================================

  List<DiffBlock> _compareDumps() {
    final previous = _dumpA;

    if (previous == null) {
      return [];
    }

    final current = _createDump();

    final indexes = <int>{
      ...previous.keys,
      ...current.keys,
    }.toList()
      ..sort();

    final differences = <DiffBlock>[];

    for (final blockIndex in indexes) {
      final a = previous[blockIndex];
      final b = current[blockIndex];

      if (a == null || b == null) {
        differences.add(
          DiffBlock(
            blockIndex: blockIndex,
            before: a,
            after: b,
          ),
        );
        continue;
      }

      if (!_listsEqual(a, b)) {
        differences.add(
          DiffBlock(
            blockIndex: blockIndex,
            before: a,
            after: b,
          ),
        );
      }
    }

    return differences;
  }

  bool _listsEqual(
    List<int> a,
    List<int> b,
  ) {
    if (a.length != b.length) {
      return false;
    }

    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }

    return true;
  }

  String _diffBytes(
    List<int> before,
    List<int> after,
  ) {
    final changed = <String>[];

    final length =
        before.length < after.length
            ? before.length
            : after.length;

    for (int i = 0; i < length; i++) {
      if (before[i] != after[i]) {
        changed.add(
          'byte $i: '
          '${before[i].toRadixString(16).padLeft(2, '0').toUpperCase()} '
          '→ '
          '${after[i].toRadixString(16).padLeft(2, '0').toUpperCase()}',
        );
      }
    }

    return changed.join('\n');
  }

  // ============================================================
  // SCANSIONE
  // ============================================================

  Future<void> _scanTag() async {
    if (_reading) {
      return;
    }

    setState(() {
      _reading = true;
      _status =
          'Avvicina il tag NFC...';
      _tag = null;
      _sectors.clear();
      _authenticatedSectors = 0;
      _readBlocks = 0;
    });

    try {
      final availability =
          await FlutterNfcKit.nfcAvailability;

      if (availability !=
          NFCAvailability.available) {
        throw Exception(
          'NFC non disponibile sul dispositivo',
        );
      }

      final tag =
          await FlutterNfcKit.poll(
        timeout:
            const Duration(seconds: 20),
        androidCheckNDEF: false,
        readIso14443A: true,
        readIso14443B: false,
        readIso18092: false,
        readIso15693: false,
      );

      if (tag.type !=
          NFCTagType.mifare_classic) {
        setState(() {
          _tag = tag;
          _status =
              'Tag rilevato, ma non è una MIFARE Classic';
        });

        return;
      }

      setState(() {
        _tag = tag;
        _status =
            'MIFARE Classic rilevata';
      });

      // --------------------------------------------------------
      // 16 settori
      // --------------------------------------------------------

      for (int sector = 0;
          sector < 16;
          sector++) {
        if (!mounted) {
          return;
        }

        setState(() {
          _status =
              'Analisi settore '
              '${sector + 1} / 16...';
        });

        final result =
            await _readSector(sector);

        _sectors.add(result);

        if (result.authenticated) {
          _authenticatedSectors++;
        }

        if (mounted) {
          setState(() {});
        }
      }

      setState(() {
        _status =
            'LETTURA COMPLETATA';
      });
    } catch (e) {
      setState(() {
        _status =
            'Errore: ${_cleanError(e)}';
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
  // MESSAGGI
  // ============================================================

  void _showMessage(
    String message,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    final differences =
        _compareDumps();

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
              child:
                  SingleChildScrollView(
                padding:
                    const EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  130,
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
                      const SizedBox(height: 14),
                      _buildDumpControls(),
                    ],

                    if (differences.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _buildDifferenceCard(
                        differences,
                      ),
                    ],

                    if (_sectors.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      const Text(
                        'SETTORI',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._sectors.map(
                        (sector) =>
                            _buildSectorCard(
                          sector,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // --------------------------------------------------
            // Pulsante NFC
            // --------------------------------------------------

            Container(
              padding:
                  const EdgeInsets.fromLTRB(
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
                    offset:
                        Offset(0, -3),
                    color:
                        Color(0x22000000),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child:
                    ElevatedButton.icon(
                  onPressed: _reading
                      ? null
                      : _scanTag,
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

  // ============================================================
  // HEADER
  // ============================================================

  Widget _buildHeaderCard() {
    return Card(
      elevation: 1,
      child: Padding(
        padding:
            const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: const [
            Text(
              'MIFARE Classic 1K',
              style: TextStyle(
                fontSize: 24,
                fontWeight:
                    FontWeight.bold,
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

  // ============================================================
  // STATUS
  // ============================================================

  Widget _buildStatusCard() {
    final isError =
        _status.startsWith('Errore');

    return Card(
      elevation: 1,
      child: Padding(
        padding:
            const EdgeInsets.all(18),
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
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _status,
                    style:
                        const TextStyle(
                      fontSize: 16,
                      fontWeight:
                          FontWeight.w600,
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

  // ============================================================
  // INFO TAG
  // ============================================================

  Widget _buildTagInfoCard() {
    final tag = _tag!;

    return Card(
      elevation: 1,
      child: Padding(
        padding:
            const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const Text(
              'INFORMAZIONI TAG',
              style: TextStyle(
                fontSize: 17,
                fontWeight:
                    FontWeight.bold,
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

  // ============================================================
  // SUMMARY
  // ============================================================

  Widget _buildSummaryCard() {
    final percentage =
        (_readBlocks / 64 * 100)
            .round();

    return Card(
      elevation: 1,
      child: Padding(
        padding:
            const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const Text(
              'RIEPILOGO',
              style: TextStyle(
                fontSize: 17,
                fontWeight:
                    FontWeight.bold,
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
              '$percentage%',
            ),
            const SizedBox(height: 14),
            TextField(
              controller:
                  _extraKeyController,
              textCapitalization:
                  TextCapitalization.characters,
              decoration:
                  const InputDecoration(
                labelText:
                    'Chiave aggiuntiva',
                hintText:
                    'FFFFFFFFFFFF',
                border:
                    OutlineInputBorder(),
                helperText:
                    'Inserisci solo una chiave MIFARE autorizzata da 6 byte',
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // DUMP CONTROLS
  // ============================================================

  Widget _buildDumpControls() {
    final hasDump =
        _dumpA != null;

    return Card(
      elevation: 1,
      child: Padding(
        padding:
            const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children: [
            const Text(
              'ANALISI DUMP',
              style: TextStyle(
                fontSize: 17,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasDump
                  ? 'DUMP A presente: '
                    '${_dumpA!.length} blocchi'
                  : 'Nessun DUMP A salvato.',
              style: const TextStyle(
                color: Colors.black54,
              ),
            ),
            if (_dumpATime != null) ...[
              const SizedBox(height: 4),
              Text(
                'Salvato alle '
                '${_dumpATime!.hour.toString().padLeft(2, '0')}:'
                '${_dumpATime!.minute.toString().padLeft(2, '0')}:'
                '${_dumpATime!.second.toString().padLeft(2, '0')}',
                style:
                    const TextStyle(
                  color: Colors.black54,
                ),
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed:
                  _reading
                      ? null
                      : _saveDumpA,
              icon:
                  const Icon(Icons.save),
              label: const Text(
                'SALVA QUESTA LETTURA COME DUMP A',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Per confrontare due stati della card: '
              'salva una prima lettura, poi effettua '
              'una seconda lettura e l\'app evidenzierà '
              'i blocchi modificati.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // DIFFERENZE
  // ============================================================

  Widget _buildDifferenceCard(
    List<DiffBlock> differences,
  ) {
    return Card(
      elevation: 1,
      child: Padding(
        padding:
            const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const Text(
              '★ DIFFERENZE DUMP A → LETTURA ATTUALE',
              style: TextStyle(
                fontSize: 17,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${differences.length} blocchi differenti',
              style: const TextStyle(
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 12),

            ...differences.map(
              (diff) {
                final before =
                    diff.before;
                final after =
                    diff.after;

                return Container(
                  margin:
                      const EdgeInsets.only(
                    bottom: 10,
                  ),
                  padding:
                      const EdgeInsets.all(
                    12,
                  ),
                  decoration:
                      BoxDecoration(
                    borderRadius:
                        BorderRadius.circular(
                      12,
                    ),
                    color: Colors.indigo
                        .withOpacity(0.06),
                  ),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                    children: [
                      Text(
                        'Block ${diff.blockIndex}',
                        style:
                            const TextStyle(
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                      const SizedBox(
                        height: 6,
                      ),
                      if (before != null)
                        SelectableText(
                          'A: ${_hex(before)}',
                          style:
                              const TextStyle(
                            fontFamily:
                                'monospace',
                            fontSize: 12,
                          ),
                        ),
                      if (after != null)
                        SelectableText(
                          'B: ${_hex(after)}',
                          style:
                              const TextStyle(
                            fontFamily:
                                'monospace',
                            fontSize: 12,
                          ),
                        ),
                      if (before != null &&
                          after != null) ...[
                        const SizedBox(
                          height: 6,
                        ),
                        Text(
                          _diffBytes(
                            before,
                            after,
                          ),
                          style:
                              const TextStyle(
                            fontFamily:
                                'monospace',
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(
                          height: 6,
                        ),
                        const Text(
                          'Questo blocco è cambiato: '
                          'analizzarlo prima di attribuirgli '
                          'un significato economico.',
                          style:
                              TextStyle(
                            fontSize: 11,
                            fontWeight:
                                FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // SUMMARY ROW
  // ============================================================

  Widget _summaryRow(
    IconData icon,
    String label,
    String value,
  ) {
    return Padding(
      padding:
          const EdgeInsets.only(
        bottom: 10,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label),
          ),
          Text(
            value,
            style:
                const TextStyle(
              fontWeight:
                  FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // INFO ROW
  // ============================================================

  Widget _infoRow(
    String label,
    String value,
  ) {
    return Padding(
      padding:
          const EdgeInsets.only(
        bottom: 8,
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 125,
            child: Text(
              label,
              style:
                  const TextStyle(
                color:
                    Colors.black54,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style:
                  const TextStyle(
                fontWeight:
                    FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SETTORE
  // ============================================================

  Widget _buildSectorCard(
    SectorResult sector,
  ) {
    final title =
        'Settore ${sector.sector + 1}';

    if (!sector.authenticated) {
      return Card(
        margin:
            const EdgeInsets.only(
          bottom: 10,
        ),
        child: ExpansionTile(
          leading: const Icon(
            Icons.lock_outline,
          ),
          title: Text(
            title,
            style:
                const TextStyle(
              fontWeight:
                  FontWeight.bold,
            ),
          ),
          subtitle: const Text(
            'AUTENTICAZIONE FALLITA',
          ),
          children: [
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(
                16,
                0,
                16,
                16,
              ),
              child: Align(
                alignment:
                    Alignment.centerLeft,
                child: Text(
                  sector.errors.isEmpty
                      ? 'Nessuna chiave conosciuta accettata.'
                      : sector.errors
                          .join('\n'),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      margin:
          const EdgeInsets.only(
        bottom: 10,
      ),
      child: ExpansionTile(
        initiallyExpanded:
            sector.sector == 0,
        leading: const Icon(
          Icons.lock_open,
        ),
        title: Text(
          title,
          style:
              const TextStyle(
            fontWeight:
                FontWeight.bold,
          ),
        ),
        subtitle: Text(
          'AUTENTICATO • '
          '${sector.keyType ?? ''} • '
          '${sector.blocks.where(
                (b) => b.data != null,
              ).length}/4 blocchi',
        ),
        children: [
          Padding(
            padding:
                const EdgeInsets.fromLTRB(
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
                  (block) =>
                      _buildBlockCard(
                    block,
                  ),
                ),
                if (sector.errors
                    .isNotEmpty) ...[
                  const SizedBox(
                    height: 8,
                  ),
                  Text(
                    sector.errors
                        .join('\n'),
                    style:
                        const TextStyle(
                      color:
                          Colors.redAccent,
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

  // ============================================================
  // DETTAGLIO
  // ============================================================

  Widget _detailLine(
    String label,
    String value,
  ) {
    return Padding(
      padding:
          const EdgeInsets.only(
        bottom: 6,
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style:
                  const TextStyle(
                color:
                    Colors.black54,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style:
                  const TextStyle(
                fontWeight:
                    FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BLOCCO
  // ============================================================

  Widget _buildBlockCard(
    BlockResult block,
  ) {
    final data = block.data;

    if (data == null) {
      return Container(
        margin:
            const EdgeInsets.only(
          bottom: 8,
        ),
        padding:
            const EdgeInsets.all(12),
        decoration:
            BoxDecoration(
          borderRadius:
              BorderRadius.circular(
            12,
          ),
          color: Colors.black
              .withOpacity(0.04),
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Text(
              'Block ${block.blockIndex}',
              style:
                  const TextStyle(
                fontWeight:
                    FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              block.error ??
                  'Blocco non leggibile',
              style:
                  const TextStyle(
                color:
                    Colors.redAccent,
              ),
            ),
          ],
        ),
      );
    }

    final analysis =
        _blockAnalysis(
      block.blockIndex,
      data,
    );

    return Container(
      margin:
          const EdgeInsets.only(
        bottom: 8,
      ),
      padding:
          const EdgeInsets.all(12),
      decoration:
          BoxDecoration(
        borderRadius:
            BorderRadius.circular(
          12,
        ),
        color: Colors.black
            .withOpacity(0.04),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            'Block ${block.blockIndex}',
            style:
                const TextStyle(
              fontWeight:
                  FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            _hex(data),
            style:
                const TextStyle(
              fontFamily:
                  'monospace',
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 5),
          SelectableText(
            _hexCompact(data),
            style:
                const TextStyle(
              fontFamily:
                  'monospace',
              fontSize: 11,
              color:
                  Colors.black54,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            analysis,
            style:
                const TextStyle(
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

class DiffBlock {
  final int blockIndex;
  final List<int>? before;
  final List<int>? after;

  const DiffBlock({
    required this.blockIndex,
    required this.before,
    required this.after,
  });
}
