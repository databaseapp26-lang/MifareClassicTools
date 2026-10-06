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
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
        ),
        useMaterial3: true,
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
  bool _scanning = false;
  String _status = 'Pronto';
  String _tagInfo = '';
  String _dump = '';

  // Chiavi note/default.
  // Non viene effettuato alcun brute-force.
  static const List<String> _knownKeys = [
    'FFFFFFFFFFFF',
    'A0A1A2A3A4A5',
    'D3F7D3F7D3F7',
    'B0B1B2B3B4B5',
    '4D3A99C351DD',
    '000000000000',
  ];

  Future<void> _scanNfc() async {
    if (_scanning) {
      return;
    }

    setState(() {
      _scanning = true;
      _status = 'Avvicina il tag NFC...';
      _tagInfo = '';
      _dump = '';
    });

    try {
      final availability = await FlutterNfcKit.nfcAvailability;

      if (availability != NFCAvailability.available) {
        setState(() {
          _status = 'NFC non disponibile';
          _tagInfo = 'Controlla che NFC sia attivo sul telefono.';
        });
        return;
      }

      final tag = await FlutterNfcKit.poll(
        timeout: const Duration(seconds: 20),
        androidCheckNDEF: false,
      );

      if (tag.type != NFCTagType.mifare_classic) {
        setState(() {
          _status = 'TAG NON SUPPORTATO';
          _tagInfo = '''
Tipo rilevato:
${tag.type}

UID:
${tag.id}

Questa versione è dedicata a MIFARE Classic.
''';
        });
        return;
      }

      setState(() {
        _status = 'MIFARE CLASSIC RILEVATO';
        _tagInfo = '''
Tipo tecnologia:
${tag.type}

UID:
${tag.id}

Standard:
${tag.standard}

NDEF:
${tag.ndefAvailable == true ? 'Disponibile' : 'Non disponibile'}

Lettura memoria:
IN CORSO...
''';
      });

      final StringBuffer result = StringBuffer();

      result.writeln('MIFARE CLASSIC 1K');
      result.writeln('UID: ${tag.id}');
      result.writeln('');
      result.writeln('16 SETTORI / 64 BLOCCHI');
      result.writeln('========================================');
      result.writeln('');

      int readableSectors = 0;

      for (int sector = 0; sector < 16; sector++) {
        bool authenticated = false;
        String? workingKey;
        String keyType = '';

        result.writeln('SETTORE $sector');
        result.writeln('----------------------------------------');

        // Prova prima con Key A.
        for (final key in _knownKeys) {
          try {
            await FlutterNfcKit.authenticateSector(
              sector,
              keyA: key,
            );

            authenticated = true;
            workingKey = key;
            keyType = 'Key A';
            break;
          } catch (_) {
            // Prova la chiave successiva.
          }
        }

        // Se Key A non funziona, prova Key B.
        if (!authenticated) {
          for (final key in _knownKeys) {
            try {
              await FlutterNfcKit.authenticateSector(
                sector,
                keyB: key,
              );

              authenticated = true;
              workingKey = key;
              keyType = 'Key B';
              break;
            } catch (_) {
              // Prova la chiave successiva.
            }
          }
        }

        if (!authenticated) {
          result.writeln('❌ AUTENTICAZIONE FALLITA');
          result.writeln('Nessuna chiave conosciuta ha funzionato.');
          result.writeln('');
          continue;
        }

        readableSectors++;

        result.writeln('✅ AUTENTICATO');
        result.writeln('Metodo: $keyType');
        result.writeln('Chiave: $workingKey');
        result.writeln('');

        try {
          final data = await FlutterNfcKit.readSector(sector);

          // Un settore Classic normalmente contiene 64 byte:
          // 4 blocchi × 16 byte.
          for (int blockInSector = 0;
              blockInSector < 4;
              blockInSector++) {
            final start = blockInSector * 16;
            final end = start + 16;

            if (end > data.length) {
              break;
            }

            final block = data.sublist(start, end);
            final absoluteBlock = (sector * 4) + blockInSector;

            result.writeln(
              'Blocco $absoluteBlock'
              '${blockInSector == 3 ? ' (TRAILER)' : ''}:',
            );

            result.writeln(_bytesToHex(block));
            result.writeln('');
          }
        } catch (e) {
          result.writeln('❌ ERRORE LETTURA SETTORE');
          result.writeln(e.toString());
          result.writeln('');
        }

        result.writeln('');
      }

      result.writeln('========================================');
      result.writeln(
        'SETTORI LEGGIBILI: $readableSectors / 16',
      );

      setState(() {
        _status = readableSectors == 16
            ? 'LETTURA COMPLETATA'
            : 'LETTURA PARZIALE';

        _tagInfo = '''
Tipo tecnologia:
${tag.type}

UID:
${tag.id}

Standard:
${tag.standard}

NDEF:
${tag.ndefAvailable == true ? 'Disponibile' : 'Non disponibile'}

Settori leggibili:
$readableSectors / 16
''';

        _dump = result.toString();
      });
    } catch (e) {
      setState(() {
        _status = 'ERRORE';
        _tagInfo = e.toString();
        _dump = '';
      });
    } finally {
      try {
        await FlutterNfcKit.finish();
      } catch (_) {}

      if (mounted) {
        setState(() {
          _scanning = false;
        });
      }
    }
  }

  String _bytesToHex(List<int> bytes) {
    return bytes
        .map(
          (byte) => byte
              .toRadixString(16)
              .padLeft(2, '0')
              .toUpperCase(),
        )
        .join(' ');
  }

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
                  20,
                  20,
                  20,
                  20,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.contactless,
                      size: 80,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'MIFARE Classic 1K',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Lettura e strumenti NFC',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 25),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _status,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (_tagInfo.isNotEmpty) ...[
                              const SizedBox(height: 18),
                              SelectableText(
                                _tagInfo,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (_dump.isNotEmpty) ...[
                      const SizedBox(height: 15),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: SelectableText(
                            _dump,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                20,
                8,
                20,
                20,
              ),
              child: SizedBox(
                height: 56,
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _scanning ? null : _scanNfc,
                  icon: Icon(
                    _scanning
                        ? Icons.hourglass_top
                        : Icons.contactless,
                  ),
                  label: Text(
                    _scanning
                        ? 'LETTURA IN CORSO...'
                        : 'LEGGI TAG NFC',
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
