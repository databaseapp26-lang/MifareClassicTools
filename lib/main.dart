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

  Future<void> _scanNfc() async {
    if (_scanning) {
      return;
    }

    setState(() {
      _scanning = true;
      _status = 'Avvicina il tag NFC...';
      _tagInfo = '';
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

      setState(() {
        _status = 'TAG RILEVATO';

        _tagInfo = '''
Tipo tecnologia:
${tag.type}

ID / UID:
${tag.id}

Standard:
${tag.standard}

NDEF:
${tag.ndefAvailable ? 'Disponibile' : 'Non disponibile'}

Dimensione:
${tag.ndefCapacity}

Tipo NDEF:
${tag.ndefType}
''';
      });
    } catch (e) {
      setState(() {
        _status = 'Errore';
        _tagInfo = e.toString();
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
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),

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

              const SizedBox(height: 35),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
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
                        const SizedBox(height: 20),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SelectableText(
                            _tagInfo,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const Spacer(),

              SizedBox(
                height: 56,
                child: FilledButton.icon(
                  onPressed: _scanning ? null : _scanNfc,
                  icon: Icon(
                    _scanning
                        ? Icons.hourglass_top
                        : Icons.contactless,
                  ),
                  label: Text(
                    _scanning
                        ? 'RICERCA IN CORSO...'
                        : 'CERCA TAG NFC',
                  ),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
