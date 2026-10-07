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
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
      ),
      home: const MifareHomePage(),
    );
  }
}

class MifareHomePage extends StatefulWidget {
  const MifareHomePage({super.key});

  @override
  State<MifareHomePage> createState() => _MifareHomePageState();
}

class _MifareHomePageState extends State<MifareHomePage> {
  static const List<String> _defaultKeys = [
    'FFFFFFFFFFFF',
    'A0A1A2A3A4A5',
    'D3F7D3F7D3F7',
    'B0B1B2B3B4B5',
    '4D3A99C351DD',
    '000000000000',
  ];

  final TextEditingController _keyController = TextEditingController();

  String _status = 'PRONTO';
  String _uid = '';
  String _technology = '';
  String _standard = '';
  String _ndef = '';

  bool _reading = false;

  int _authenticatedSectors = 0;
  int _readBlocks = 0;

  final Map<int, List<String>> _sectorLines = {};

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  List<String> get _keys {
    final keys = <String>[..._defaultKeys];

    final custom = _keyController.text
        .trim()
        .replaceAll(' ', '')
        .replaceAll(':', '')
        .toUpperCase();

    if (custom.length == 12 && RegExp(r'^[0-9A-F]{12}$').hasMatch(custom)) {
      if (!keys.contains(custom)) {
        keys.insert(0, custom);
      }
    }

    return keys;
  }

  Future<void> _startRead() async {
    if (_reading) return;

    setState(() {
      _reading = true;
      _status = 'ATTESA TAG NFC...';
      _uid = '';
      _technology = '';
      _standard = '';
      _ndef = '';
      _authenticatedSectors = 0;
      _readBlocks = 0;
      _sectorLines.clear();
    });

    try {
      final tag = await FlutterNfcKit.poll(
        timeout: const Duration(seconds: 20),
        androidCheckNDEF: false,
      );

      if (!mounted) return;

      setState(() {
        _uid = tag.id;
        _technology = tag.type.toString();
        _standard = tag.standard;
        _ndef = tag.ndefAvailable == true ? 'Disponibile' : 'Non disponibile';
        _status = 'TAG RILEVATO';
      });

      if (tag.type != NFCTagType.mifare_classic) {
        if (mounted) {
          setState(() {
            _status = 'TAG NON MIFARE CLASSIC';
          });
        }
        return;
      }

      await _readMifareClassic();
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'ERRORE';
          _sectorLines[-1] = ['${e.runtimeType}: $e'];
        });
      }
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

  Future<void> _readMifareClassic() async {
    for (int sector = 0; sector < 16; sector++) {
      if (!mounted) return;

      final lines = <String>[];

      bool authenticated = false;
      String? authMethod;
      String? usedKey;

      for (final key in _keys) {
        try {
          final result = await FlutterNfcKit.authenticateSector(
            sector,
            keyA: key,
          );

          if (result) {
            authenticated = true;
            authMethod = 'Key A';
            usedKey = key;
            break;
          }
        } catch (_) {}

        try {
          final result = await FlutterNfcKit.authenticateSector(
            sector,
            keyB: key,
          );

          if (result) {
            authenticated = true;
            authMethod = 'Key B';
            usedKey = key;
            break;
          }
        } catch (_) {}
      }

      if (!authenticated) {
        lines.add('AUTENTICAZIONE FALLITA');
        _sectorLines[sector] = lines;

        if (mounted) {
          setState(() {});
        }

        continue;
      }

      _authenticatedSectors++;

      lines.add('AUTENTICATO');
      lines.add('Metodo: $authMethod');
      lines.add('Chiave: $usedKey');

      bool sectorOk = true;

      for (int block = sector * 4; block < sector * 4 + 4; block++) {
        try {
          final data = await FlutterNfcKit.readBlock(block);

          final hex = data
              .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
              .join(' ');

          lines.add('Block $block:');
          lines.add(hex);

          _readBlocks++;
        } catch (e) {
          sectorOk = false;
          lines.add('Block $block: ERRORE');
          lines.add('${e.runtimeType}: $e');
          break;
        }
      }

      if (sector == 2) {
        lines.add('');
        lines.add('*** SETTORE 2 - DATI DI INTERESSE ***');
      }

      if (sector == 3) {
        lines.add('');
        lines.add('*** SETTORE 3 - DATI DI INTERESSE ***');
      }

      if (!sectorOk) {
        lines.add('Lettura settore interrotta al primo errore.');
      }

      _sectorLines[sector] = lines;

      if (mounted) {
        setState(() {});
      }
    }

    if (mounted) {
      setState(() {
        _status = 'LETTURA COMPLETATA';
      });
    }
  }

  Widget _infoCard() {
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
            const SizedBox(height: 12),
            if (_uid.isNotEmpty) Text('UID: $_uid'),
            if (_technology.isNotEmpty)
              Text('Tecnologia: $_technology'),
            if (_standard.isNotEmpty) Text('Standard: $_standard'),
            if (_ndef.isNotEmpty) Text('NDEF: $_ndef'),
            const SizedBox(height: 10),
            Text('Settori autenticati: $_authenticatedSectors / 16'),
            Text('Blocchi letti: $_readBlocks / 64'),
          ],
        ),
      ),
    );
  }

  Widget _keyCard() {
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
            const Text(
              'Inserisci una chiave MIFARE Classic di 6 byte '
              '(12 caratteri HEX), se ne possiedi una autorizzata.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _keyController,
              enabled: !_reading,
              maxLength: 12,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Esempio: FFFFFFFFFFFF',
                counterText: '',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectorCard(int sector, List<String> lines) {
    final important = sector == 2 || sector == 3;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        initiallyExpanded: important,
        title: Text(
          'Settore ${sector + 1}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: important ? Colors.blue : null,
          ),
        ),
        subtitle: Text(
          important ? 'SETTORE DI INTERESSE' : 'MIFARE Classic',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              lines.join('\n'),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
        ],
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
            child: ListView(
              padding: const EdgeInsets.all(12),
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
                  'Lettura e analisi NFC',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 12),
                _infoCard(),
                const SizedBox(height: 8),
                _keyCard(),
                const SizedBox(height: 8),
                for (final entry in _sectorLines.entries)
                  if (entry.key >= 0)
                    _sectorCard(entry.key, entry.value),
                if (_sectorLines.containsKey(-1))
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SelectableText(
                        _sectorLines[-1]!.join('\n'),
                      ),
                    ),
                  ),
                const SizedBox(height: 90),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton.icon(
                  onPressed: _reading ? null : _startRead,
                  icon: Icon(
                    _reading
                        ? Icons.hourglass_top
                        : Icons.contactless,
                  ),
                  label: Text(
                    _reading ? 'ATTESA TAG...' : 'CERCA TAG NFC',
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
