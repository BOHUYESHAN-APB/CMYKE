import 'package:flutter_test/flutter_test.dart';

import 'package:cmyke/core/services/streaming_text_chunker.dart';

void main() {
  group('StreamingTextChunker', () {
    test('yields chunks on punctuation boundaries', () {
      final chunker = StreamingTextChunker(minChunkChars: 4, maxChunkChars: 32);

      final chunks1 = chunker.pushDelta('你好，这是第一句。这里');
      final chunks2 = chunker.pushDelta('是第二句！最后一句');
      final tail = chunker.flush();

      expect(chunks1, ['你好，这是第一句。']);
      expect(chunks2, ['这里是第二句！']);
      expect(tail, ['最后一句']);
    });

    test('forces cut when text exceeds max chunk length', () {
      final chunker = StreamingTextChunker(minChunkChars: 8, maxChunkChars: 12);

      final chunks = chunker.pushDelta('abcdefghijklmnopqrstuvwxyz');

      expect(chunks, ['abcdefghijkl', 'mnopqrstuvwx']);
      expect(chunker.flush(), ['yz']);
    });

    test('does not emit tiny fragments before flush', () {
      final chunker = StreamingTextChunker(
        minChunkChars: 10,
        maxChunkChars: 40,
      );

      final chunks = chunker.pushDelta('短句');

      expect(chunks, isEmpty);
      expect(chunker.flush(), ['短句']);
    });
  });
}
