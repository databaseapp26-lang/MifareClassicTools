import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0F1115),
      ),
      home: const HomePage(),
    );
  }
}

class SectorResult {
  final int sector;
  final String? key;
  final String? method;
  final List<String> blocks;
  final String error;

  const SectorResult({
    required this.sector,
    required this.key,
    required this.method,
    required this.blocks,
    required this.error,
  });

  bool get authenticated => key != null;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  NFCTag? _tag;

  bool _reading = false;
  bool _completed = false;

  String _status = 'PRONTO';
  String _additionalKey = '';

  final List<SectorResult> _sectors = [];

  int get _authenticatedSectors =>
      _sectors.where((sector) => sector.authenticated).length;

  int get _blocksRead =>
      _sectors.fold<int>(0, (sum, sector) => sum + sector.blocks.length);

  int get _totalBlocks => 64;

  Future<void> _startReading() async {
    if (_reading) return;

    setState(() {
      _reading = true;
      _completed = false;
      _status = 'AVVICINA UNA MIFARE CLASSIC';
      _tag = null;
      _sectors.clear();
    });

    try {
      final tag = await FlutterNfcKit.poll(
        timeout: const Duration(seconds: 20),
        androidCheckNDEF: false,
        readIso14443A: true,
        readIso14443B: false,
        readIso15693: false,
        readIso18092: false,
      );

      if (tag.type != NFCTagType.mifare_classic) {
        setState(() {
          _status = 'TAG NON MIFARE CLASSIC';
          _tag = tag;
        });
        return;
      }

      setState(() {
        _tag = tag;
        _status = 'TAG RILEVATO';
      });

      await _readAllSectors();
    } catch (e) {
      setState(() {
        _status = 'ERRORE: $e';
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

  Future<void> _readAllSectors() async {
    for (int sector = 0; sector < 16; sector++) {
      if (!mounted) return;

      setState(() {
        _status = 'Analisi settore ${sector + 1} / 16...';
      });

      final result = await _readSector(sector);

      if (!mounted) return;

      setState(() {
        _sectors.add(result);
      });
    }

    if (!mounted) return;

    setState(() {
      _completed = true;
      _status = 'LETTURA COMPLETATA';
    });
  }

  Future<SectorResult> _readSector(int sector) async {
    String additionalKey = _normalizeKey(_additionalKey);

    final keys = <String>[
      if (additionalKey.isNotEmpty) additionalKey,
      ...publicMifareKeys,
    ].toSet().toList();

    String? acceptedKey;
    String? acceptedMethod;

    for (final key in keys) {
      if (!_isValidKey(key)) continue;

      try {
        await FlutterNfcKit.authenticateSector(
          sector,
          keyA: key,
        );

        acceptedKey = key;
        acceptedMethod = 'Key A';
        break;
      } catch (_) {
        // Prova la chiave successiva.
      }
    }

    if (acceptedKey == null) {
      for (final key in keys) {
        if (!_isValidKey(key)) continue;

        try {
          await FlutterNfcKit.authenticateSector(
            sector,
            keyB: key,
          );

          acceptedKey = key;
          acceptedMethod = 'Key B';
          break;
        } catch (_) {
          // Prova la chiave successiva.
        }
      }
    }

    if (acceptedKey == null) {
      return SectorResult(
        sector: sector,
        key: null,
        method: null,
        blocks: const [],
        error: 'Autenticazione non riuscita',
      );
    }

    final firstBlock = sector * 4;
    final blocks = <String>[];

    for (int block = 0; block < 4; block++) {
      final blockIndex = firstBlock + block;

      try {
        final data = await FlutterNfcKit.readBlock(blockIndex);
        blocks.add(_bytesToHex(data));
      } catch (_) {
        // Il blocco può essere protetto anche dopo l'autenticazione.
      }
    }

    return SectorResult(
      sector: sector,
      key: acceptedKey,
      method: acceptedMethod,
      blocks: blocks,
      error: '',
    );
  }

  String _normalizeKey(String value) {
    return value
        .replaceAll(' ', '')
        .replaceAll(':', '')
        .replaceAll('-', '')
        .toUpperCase();
  }

  bool _isValidKey(String key) {
    if (key.length != 12) return false;
    return RegExp(r'^[0-9A-F]{12}$').hasMatch(key);
  }

  String _bytesToHex(dynamic data) {
    if (data is List<int>) {
      return data
          .map((value) => value.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(' ');
    }

    return data.toString();
  }

  String _asciiFromHex(String hex) {
    final parts = hex.split(' ');
    final buffer = StringBuffer();

    for (final part in parts) {
      final value = int.tryParse(part, radix: 16);

      if (value == null) {
        buffer.write('.');
      } else if (value >= 32 && value <= 126) {
        buffer.write(String.fromCharCode(value));
      } else {
        buffer.write('.');
      }
    }

    return buffer.toString();
  }

  bool _isValueBlock(String hex) {
    final bytes = hex
        .split(' ')
        .map((e) => int.tryParse(e, radix: 16))
        .whereType<int>()
        .toList();

    if (bytes.length != 16) return false;

    final value = bytes.sublist(0, 4);
    final inverse = bytes.sublist(4, 8);
    final valueCopy = bytes.sublist(8, 12);
    final address = bytes[12];
    final addressInv = bytes[13];
    final addressCopy = bytes[14];
    final addressInvCopy = bytes[15];

    for (int i = 0; i < 4; i++) {
      if ((value[i] ^ inverse[i]) != 0xFF) {
        return false;
      }

      if (value[i] != valueCopy[i]) {
        return false;
      }
    }

    if ((address ^ addressInv) != 0xFF) return false;
    if (address != addressCopy) return false;
    if (addressInv != addressInvCopy) return false;

    return true;
  }

  int? _valueFromBlock(String hex) {
    if (!_isValueBlock(hex)) return null;

    final bytes = hex
        .split(' ')
        .map((e) => int.tryParse(e, radix: 16))
        .whereType<int>()
        .toList();

    return bytes[0] |
        (bytes[1] << 8) |
        (bytes[2] << 16) |
        (bytes[3] << 24);
  }

  String _sectorTrailerInfo(String hex) {
    final bytes = hex
        .split(' ')
        .map((e) => int.tryParse(e, radix: 16))
        .whereType<int>()
        .toList();

    if (bytes.length != 16) {
      return 'Trailer non disponibile';
    }

    final access =
        '${bytes[6].toRadixString(16).padLeft(2, '0').toUpperCase()} '
        '${bytes[7].toRadixString(16).padLeft(2, '0').toUpperCase()} '
        '${bytes[8].toRadixString(16).padLeft(2, '0').toUpperCase()}';

    return 'Access bits: $access\nGPB: '
        '${bytes[9].toRadixString(16).padLeft(2, '0').toUpperCase()}';
  }

  String _dumpText() {
    final buffer = StringBuffer();

    if (_tag != null) {
      buffer.writeln('MIFARE CLASSIC DUMP');
      buffer.writeln('UID: ${_tag!.id}');
      buffer.writeln('TECHNOLOGY: ${_tag!.type}');
      buffer.writeln('STANDARD: ${_tag!.standard}');
      buffer.writeln('');
    }

    for (final sector in _sectors) {
      buffer.writeln('SECTOR ${sector.sector}');

      if (sector.key != null) {
        buffer.writeln(
          'AUTH: ${sector.method} ${sector.key}',
        );
      } else {
        buffer.writeln('AUTH: FAILED');
      }

      for (int i = 0; i < sector.blocks.length; i++) {
        buffer.writeln(
          'BLOCK ${sector.sector * 4 + i}: ${sector.blocks[i]}',
        );
      }

      buffer.writeln('');
    }

    return buffer.toString();
  }

  Future<void> _copyDump() async {
    await Clipboard.setData(
      ClipboardData(text: _dumpText()),
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Dump copiato negli appunti'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tag = _tag;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tools'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildStatusCard(),
            const SizedBox(height: 12),
            _buildTagCard(tag),
            const SizedBox(height: 12),
            _buildKeyCard(),
            const SizedBox(height: 12),
            _buildProgressCard(),
            const SizedBox(height: 12),
            _buildActionButtons(),
            const SizedBox(height: 16),
            ..._sectors.map(_buildSectorCard),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _status,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _reading
                  ? 'Ricerca/lettura in corso...'
                  : 'Lettura in sola lettura',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTagCard(NFCTag? tag) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: tag == null
            ? const Text('Nessun tag rilevato')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'TAG RILEVATO',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _infoRow('UID', tag.id),
                  _infoRow('Tecnologia', tag.type.toString()),
                  _infoRow('Standard', tag.standard.toString()),
                  _infoRow(
                    'NDEF',
                    tag.ndefAvailable == true
                        ? 'Disponibile'
                        : 'Non disponibile',
                  ),
                  _infoRow('NDEF size', '${tag.ndefCapacity}'),
                ],
              ),
      ),
    );
  }

  Widget _buildKeyCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'CHIAVE AGGIUNTIVA',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              enabled: !_reading,
              onChanged: (value) {
                _additionalKey = value;
              },
              decoration: const InputDecoration(
                hintText: '6 byte HEX, es. A0A1A2A3A4A5',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Chiavi pubbliche disponibili: ${publicMifareKeys.length}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressCard() {
    final percent =
        _totalBlocks == 0 ? 0 : (_blocksRead / _totalBlocks * 100).round();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'COPERTURA LETTURA',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: _blocksRead / _totalBlocks,
            ),
            const SizedBox(height: 10),
            Text(
              'Settori autenticati: $_authenticatedSectors / 16',
            ),
            Text(
              'Blocchi letti: $_blocksRead / 64',
            ),
            Text(
              'Copertura: $percent%',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _reading ? null : _startReading,
            icon: const Icon(Icons.nfc),
            label: Text(
              _reading ? 'LETTURA IN CORSO...' : 'LEGGI MIFARE CLASSIC',
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _sectors.isEmpty ? null : _copyDump,
            icon: const Icon(Icons.copy),
            label: const Text('COPIA DUMP'),
          ),
        ),
      ],
    );
  }

  Widget _buildSectorCard(SectorResult sector) {
    return Card(
      child: ExpansionTile(
        title: Text(
          'Settore ${sector.sector + 1}',
        ),
        subtitle: Text(
          sector.authenticated
              ? '${sector.method} • ${sector.blocks.length}/4 blocchi'
              : 'Autenticazione non riuscita',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (sector.authenticated) ...[
                  Text(
                    'Chiave accettata: ${sector.key}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text('Metodo: ${sector.method}'),
                  const SizedBox(height: 12),
                ],
                if (!sector.authenticated)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Nessuna delle chiavi pubbliche/autorizzate disponibili '
                      'ha consentito l\'autenticazione di questo settore.',
                    ),
                  ),
                ...List.generate(
                  sector.blocks.length,
                  (index) {
                    final blockNumber = sector.sector * 4 + index;
                    final hex = sector.blocks[index];
                    final value = _valueFromBlock(hex);

                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: Colors.black26,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'BLOCK $blockNumber',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            hex,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'ASCII: ${_asciiFromHex(hex)}',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                            ),
                          ),
                          if (_isValueBlock(hex)) ...[
                            const SizedBox(height: 6),
                            Text(
                              'VALUE BLOCK valido: $value',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                          if (blockNumber % 4 == 3) ...[
                            const SizedBox(height: 6),
                            Text(
                              _sectorTrailerInfo(hex),
                              style: const TextStyle(
                                fontFamily: 'monospace',
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
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(
              '$label:',
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
}
