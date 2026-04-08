class StreamingTextChunker {
  StreamingTextChunker({this.minChunkChars = 12, this.maxChunkChars = 96})
    : assert(minChunkChars > 0),
      assert(maxChunkChars >= minChunkChars);

  final int minChunkChars;
  final int maxChunkChars;
  final StringBuffer _buffer = StringBuffer();

  String get bufferedText => _buffer.toString();

  bool get hasPendingText => bufferedText.trim().isNotEmpty;

  List<String> pushDelta(String delta) {
    if (delta.isNotEmpty) {
      _buffer.write(delta);
    }
    return _drain(force: false);
  }

  List<String> flush() {
    return _drain(force: true);
  }

  List<String> _drain({required bool force}) {
    var remaining = bufferedText;
    final output = <String>[];

    while (remaining.isNotEmpty) {
      final boundary = _pickBoundary(remaining, force: force);
      if (boundary <= 0) {
        break;
      }
      final chunk = remaining.substring(0, boundary).trim();
      if (chunk.isNotEmpty) {
        output.add(chunk);
      }
      remaining = remaining.substring(boundary).trimLeft();
    }

    _buffer
      ..clear()
      ..write(remaining);
    return output;
  }

  int _pickBoundary(String text, {required bool force}) {
    if (text.isEmpty) {
      return 0;
    }

    final upper = text.length > maxChunkChars ? maxChunkChars : text.length;
    final candidateWindow = text.substring(0, upper);
    final preferred = _lastPreferredBoundary(candidateWindow);

    if (preferred > 0 && (preferred >= minChunkChars || force)) {
      return preferred;
    }

    if (text.length > maxChunkChars) {
      return maxChunkChars;
    }

    if (force) {
      return text.length;
    }

    return 0;
  }

  int _lastPreferredBoundary(String text) {
    var best = -1;

    for (var index = 0; index < text.length; index += 1) {
      final char = text[index];
      if (_isBoundaryChar(char)) {
        best = index + 1;
      }
    }

    return best;
  }

  bool _isBoundaryChar(String char) {
    return char == ' ' ||
        char == '\n' ||
        char == '\t' ||
        char == '。' ||
        char == '！' ||
        char == '？' ||
        char == '，' ||
        char == '；' ||
        char == '：' ||
        char == '.' ||
        char == '!' ||
        char == '?' ||
        char == ',' ||
        char == ';' ||
        char == ':';
  }
}
