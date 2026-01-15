import '../models/chat_message.dart';
import '../models/memory_record.dart';

class TokenEstimator {
  static const int _messageOverhead = 4;

  static int estimateMessages(Iterable<ChatMessage> messages) {
    var total = 0;
    for (final message in messages) {
      final content = message.content.trim();
      if (content.isEmpty) {
        continue;
      }
      total += estimateText(content) + _messageOverhead;
    }
    return total;
  }

  static int estimateRecords(Iterable<MemoryRecord> records) {
    var total = 0;
    for (final record in records) {
      final content = record.content.trim();
      if (content.isEmpty) {
        continue;
      }
      total += estimateText(content);
    }
    return total;
  }

  static int estimateText(String text) {
    if (text.isEmpty) {
      return 0;
    }
    var tokens = 0;
    var asciiRun = 0;
    for (final rune in text.runes) {
      if (_isWhitespace(rune)) {
        tokens += _flushAscii(asciiRun);
        asciiRun = 0;
        continue;
      }
      if (_isCjk(rune)) {
        tokens += _flushAscii(asciiRun);
        asciiRun = 0;
        tokens += 1;
        continue;
      }
      if (_isAsciiWord(rune)) {
        asciiRun += 1;
        if (asciiRun >= 4) {
          tokens += 1;
          asciiRun = 0;
        }
        continue;
      }
      tokens += _flushAscii(asciiRun);
      asciiRun = 0;
      tokens += 1;
    }
    tokens += _flushAscii(asciiRun);
    return tokens;
  }

  static int _flushAscii(int run) {
    if (run <= 0) {
      return 0;
    }
    return (run + 3) ~/ 4;
  }

  static bool _isWhitespace(int rune) {
    return rune == 0x20 ||
        rune == 0x0A ||
        rune == 0x0D ||
        rune == 0x09;
  }

  static bool _isAsciiWord(int rune) {
    return (rune >= 0x30 && rune <= 0x39) ||
        (rune >= 0x41 && rune <= 0x5A) ||
        (rune >= 0x61 && rune <= 0x7A);
  }

  static bool _isCjk(int rune) {
    return (rune >= 0x4E00 && rune <= 0x9FFF) ||
        (rune >= 0x3400 && rune <= 0x4DBF) ||
        (rune >= 0x20000 && rune <= 0x2A6DF) ||
        (rune >= 0x2A700 && rune <= 0x2B73F) ||
        (rune >= 0x2B740 && rune <= 0x2B81F) ||
        (rune >= 0x2B820 && rune <= 0x2CEAF) ||
        (rune >= 0xF900 && rune <= 0xFAFF);
  }
}
