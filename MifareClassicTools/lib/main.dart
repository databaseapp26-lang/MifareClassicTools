import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';

void main() => runApp(const MifareClassicToolsApp());

class MifareClassicToolsApp extends StatelessWidget {
  const MifareClassicToolsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MIFARE Classic Tools',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
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
  NFCTag? _tag;
  bool _sessionOpen = false;
  bool _busy = false;
  String _status = 'Pronto. Premi "Rileva tag".';
  String _result = '';

  final _sectorController = TextEditingController(text: '0');
  final _keyController = TextEditingController(text: 'FFFFFFFFFFFF');
  String _keyType = 'A';

  @override
  void dispose() {
    _sectorController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  String _normalizeKey(String value) =>
      value.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toUpperCase();

  Future<void> _poll() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _result = '';
      _status = 'Avvicina il tag MIFARE Classic al telefono...';
    });
    try {
      if (_sessionOpen) {
        await FlutterNfcKit.finish();
        _sessionOpen = false;
      }
      final tag = await FlutterNfcKit.poll(
        androidReaderModeFlags: 0x80,
      );
      _tag = tag;
      _sessionOpen = true;
      setState(() {
        _status = 'Tag rilevato: ${tag.type} — ID ${tag.id}';
      });
    } catch (e) {
      setState(() => _status = 'Errore NFC: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifySelectedKey() async {
    if (_busy) return;
    if (!_sessionOpen || _tag == null) {
      setState(() => _status = 'Prima rileva il tag.');
      return;
    }

    final key = _normalizeKey(_keyController.text);
    final sector = int.tryParse(_sectorController.text.trim());
    if (!RegExp(r'^[0-9A-F]{12}$').hasMatch(key)) {
      setState(() => _status = 'Chiave non valida: servono 12 caratteri HEX.');
      return;
    }
    if (sector == null || sector < 0 || sector > 39) {
      setState(() => _status = 'Settore non valido. Usa un numero da 0 a 39.');
      return;
    }

    setState(() {
      _busy = true;
      _result = '';
      _status = 'Verifica della chiave sul settore $sector...';
    });

    try {
      bool ok;
      if (_keyType == 'A') {
        ok = await FlutterNfcKit.authenticateSector(sector, keyA: key);
      } else {
        ok = await FlutterNfcKit.authenticateSector(sector, keyB: key);
      }
      setState(() {
        _result = ok ? 'VALIDA ✓' : 'NON AUTENTICATA';
        _status = ok
            ? 'La chiave $_keyType $key è stata accettata dal settore $sector.'
            : 'La chiave $_keyType non è stata accettata dal settore $sector.';
      });
    } catch (e) {
      setState(() {
        _result = 'ERRORE';
        _status = 'Errore durante l\'autenticazione: $e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    try {
      if (_sessionOpen) await FlutterNfcKit.finish();
    } finally {
      _sessionOpen = false;
      if (mounted) {
        setState(() {
          _tag = null;
          _result = '';
          _status = 'Sessione NFC chiusa.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tag = _tag;
    return Scaffold(
      appBar: AppBar(title: const Text('MIFARE Classic Tools')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Stato', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(_status),
                  if (tag != null) ...[
                    const SizedBox(height: 8),
                    Text('Tipo: ${tag.type}'),
                    Text('ID: ${tag.id}'),
                    Text('Standard: ${tag.standard}'),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _poll,
            icon: const Icon(Icons.nfc),
            label: const Text('Rileva tag'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : _finish,
            child: const Text('Chiudi sessione NFC'),
          ),
          const Divider(height: 32),
          Text('Verifica di una chiave', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'Questa versione verifica una chiave candidata alla volta. '
            'La lista autorizzata può essere usata per scegliere le candidate senza eseguire un tentativo automatico indiscriminato.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _sectorController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Settore', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'A', label: Text('Key A')),
              ButtonSegment(value: 'B', label: Text('Key B')),
            ],
            selected: {_keyType},
            onSelectionChanged: _busy ? null : (s) => setState(() => _keyType = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _keyController,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]'))],
            decoration: const InputDecoration(
              labelText: 'Chiave (12 caratteri HEX)',
              hintText: 'FFFFFFFFFFFF',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy || !_sessionOpen ? null : _verifySelectedKey,
            icon: const Icon(Icons.verified),
            label: const Text('Verifica chiave'),
          ),
          if (_result.isNotEmpty) ...[
            const SizedBox(height: 20),
            Center(child: Text(_result, style: Theme.of(context).textTheme.headlineSmall)),
          ],
        ],
      ),
    );
  }
}
