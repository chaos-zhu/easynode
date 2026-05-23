import 'dart:convert';
import 'dart:typed_data';

class TextSniffResult {
  const TextSniffResult({
    required this.malformedUtf8,
    required this.text,
  });

  final bool malformedUtf8;
  final String text;
}

TextSniffResult sniffAndDecode(Uint8List bytes) {
  var malformed = false;
  try {
    utf8.decode(bytes);
  } on FormatException {
    malformed = true;
  }

  final text = utf8.decode(bytes, allowMalformed: true);
  return TextSniffResult(
    malformedUtf8: malformed,
    text: text,
  );
}
