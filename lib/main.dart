List<String> _authorizedKeysForTesting() {
  final keys = <String>{};

  // Chiavi comuni già integrate nell'app.
  for (final key in _knownKeys) {
    final normalized = _normalizeKey(key);

    if (_isValidKey(normalized)) {
      keys.add(normalized);
    }
  }

  // Chiave inserita manualmente dall'utente.
  final extra = _normalizeKey(_extraKeyController.text);

  if (_isValidKey(extra)) {
    keys.add(extra);
  }

  return keys.toList()..sort();
}
