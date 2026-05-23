import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

class TextSniffResult {
  const TextSniffResult({
    required this.isBinary,
    required this.malformedUtf8,
    required this.text,
  });

  final bool isBinary;
  final bool malformedUtf8;
  final String text;
}

TextSniffResult sniffAndDecode(Uint8List bytes) {
  final probeLen = math.min(8192, bytes.length);
  for (var i = 0; i < probeLen; i++) {
    if (bytes[i] == 0) {
      return const TextSniffResult(
        isBinary: true,
        malformedUtf8: false,
        text: '',
      );
    }
  }

  var malformed = false;
  try {
    utf8.decode(bytes);
  } on FormatException {
    malformed = true;
  }

  final text = utf8.decode(bytes, allowMalformed: true);
  return TextSniffResult(
    isBinary: false,
    malformedUtf8: malformed,
    text: text,
  );
}
