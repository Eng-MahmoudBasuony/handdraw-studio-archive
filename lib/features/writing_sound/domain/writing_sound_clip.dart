import 'dart:math' as math;
import 'dart:typed_data';

class WritingSoundClip {
  const WritingSoundClip({required this.sampleRate, required this.samples});

  final int sampleRate;
  final Int16List samples;

  factory WritingSoundClip.fromWave(Uint8List bytes) {
    if (bytes.length < 44 || _ascii(bytes, 0, 4) != 'RIFF') {
      throw const FormatException('Writing sound is not a RIFF wave file.');
    }
    final data = ByteData.sublistView(bytes);
    var cursor = 12;
    int? sampleRate;
    int? channels;
    int? bitsPerSample;
    int? audioFormat;
    int? sampleDataOffset;
    int? sampleDataLength;
    while (cursor + 8 <= bytes.length) {
      final id = _ascii(bytes, cursor, 4);
      final length = data.getUint32(cursor + 4, Endian.little);
      final content = cursor + 8;
      if (content + length > bytes.length) break;
      if (id == 'fmt ' && length >= 16) {
        audioFormat = data.getUint16(content, Endian.little);
        channels = data.getUint16(content + 2, Endian.little);
        sampleRate = data.getUint32(content + 4, Endian.little);
        bitsPerSample = data.getUint16(content + 14, Endian.little);
      } else if (id == 'data') {
        sampleDataOffset = content;
        sampleDataLength = length;
      }
      cursor = content + length + (length.isOdd ? 1 : 0);
    }
    if (audioFormat != 1 ||
        channels == null ||
        channels < 1 ||
        sampleRate == null ||
        bitsPerSample != 16 ||
        sampleDataOffset == null ||
        sampleDataLength == null) {
      throw const FormatException('Writing sound must be 16-bit PCM wave.');
    }
    final frameCount = sampleDataLength ~/ (channels * 2);
    final samples = Int16List(frameCount);
    for (var frame = 0; frame < frameCount; frame++) {
      var mixed = 0;
      for (var channel = 0; channel < channels; channel++) {
        mixed += data.getInt16(
          sampleDataOffset + (frame * channels + channel) * 2,
          Endian.little,
        );
      }
      samples[frame] = (mixed / channels).round();
    }
    return WritingSoundClip(sampleRate: sampleRate, samples: samples);
  }

  double sampleAt(double position) {
    if (samples.isEmpty) return 0;
    final length = samples.length;
    final loopPosition = position % length;
    final crossFade = math.min((sampleRate * 0.025).round(), length ~/ 4);
    final current = _interpolated(loopPosition);
    if (crossFade < 2 || loopPosition < length - crossFade) return current;
    final mix = (loopPosition - (length - crossFade)) / crossFade;
    final fromStart = _interpolated(loopPosition - (length - crossFade));
    return current + (fromStart - current) * mix;
  }

  double _interpolated(double position) {
    final first = position.floor() % samples.length;
    final second = (first + 1) % samples.length;
    final fraction = position - position.floor();
    final a = samples[first] / 32768.0;
    final b = samples[second] / 32768.0;
    return a + (b - a) * fraction;
  }

  static String _ascii(Uint8List bytes, int offset, int length) =>
      String.fromCharCodes(bytes.sublist(offset, offset + length));
}
