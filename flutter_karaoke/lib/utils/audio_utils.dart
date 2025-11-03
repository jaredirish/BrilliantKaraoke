import 'dart:typed_data';

/// Audio processing utilities

/// Combine multiple audio chunks into a single buffer
Uint8List combineAudioChunks(List<Uint8List> chunks) {
  if (chunks.isEmpty) return Uint8List(0);

  final totalLength = chunks.fold<int>(0, (sum, chunk) => sum + chunk.length);
  final combined = Uint8List(totalLength);

  var offset = 0;
  for (final chunk in chunks) {
    combined.setRange(offset, offset + chunk.length, chunk);
    offset += chunk.length;
  }

  return combined;
}

/// Trim audio buffer to a maximum duration
Uint8List trimAudioBuffer(
  Uint8List audioData,
  double maxDurationSeconds,
  int sampleRate,
) {
  final bytesPerSecond = sampleRate * 2; // 16-bit mono = 2 bytes per sample
  final maxBytes = (maxDurationSeconds * bytesPerSecond).floor();

  if (audioData.length <= maxBytes) {
    return audioData;
  }

  // Keep only the last maxBytes
  return Uint8List.sublistView(audioData, audioData.length - maxBytes);
}

/// Calculate audio duration from buffer length
double calculateAudioDuration(int audioLength, int sampleRate) {
  final bytesPerSecond = sampleRate * 2; // 16-bit mono
  return audioLength / bytesPerSecond;
}

/// Create WAV file header for PCM audio
Uint8List createWavHeader(int dataLength, int sampleRate) {
  final header = ByteData(44);

  // Constants for 16-bit mono PCM
  const numChannels = 1;
  const bitsPerSample = 16;
  final byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
  final blockAlign = numChannels * (bitsPerSample ~/ 8);

  // RIFF chunk descriptor (12 bytes)
  header.setUint8(0, 'R'.codeUnitAt(0));
  header.setUint8(1, 'I'.codeUnitAt(0));
  header.setUint8(2, 'F'.codeUnitAt(0));
  header.setUint8(3, 'F'.codeUnitAt(0));
  header.setUint32(4, dataLength + 36, Endian.little);
  header.setUint8(8, 'W'.codeUnitAt(0));
  header.setUint8(9, 'A'.codeUnitAt(0));
  header.setUint8(10, 'V'.codeUnitAt(0));
  header.setUint8(11, 'E'.codeUnitAt(0));

  // fmt sub-chunk (24 bytes)
  header.setUint8(12, 'f'.codeUnitAt(0));
  header.setUint8(13, 'm'.codeUnitAt(0));
  header.setUint8(14, 't'.codeUnitAt(0));
  header.setUint8(15, ' '.codeUnitAt(0));
  header.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
  header.setUint16(20, 1, Endian.little); // AudioFormat (1 = PCM)
  header.setUint16(22, numChannels, Endian.little); // NumChannels
  header.setUint32(24, sampleRate, Endian.little); // SampleRate
  header.setUint32(28, byteRate, Endian.little); // ByteRate
  header.setUint16(32, blockAlign, Endian.little); // BlockAlign
  header.setUint16(34, bitsPerSample, Endian.little); // BitsPerSample

  // data sub-chunk (8 bytes)
  header.setUint8(36, 'd'.codeUnitAt(0));
  header.setUint8(37, 'a'.codeUnitAt(0));
  header.setUint8(38, 't'.codeUnitAt(0));
  header.setUint8(39, 'a'.codeUnitAt(0));
  header.setUint32(40, dataLength, Endian.little);

  return header.buffer.asUint8List();
}

/// Create complete WAV file buffer from PCM audio data
Uint8List createWavBuffer(Uint8List audioData, int sampleRate) {
  final header = createWavHeader(audioData.length, sampleRate);
  final wavBuffer = Uint8List(header.length + audioData.length);

  wavBuffer.setRange(0, header.length, header);
  wavBuffer.setRange(header.length, wavBuffer.length, audioData);

  return wavBuffer;
}

/// Validate audio data
bool validateAudioData(Uint8List audioData) {
  if (audioData.isEmpty) {
    return false;
  }

  // Check if length is reasonable (at least 0.1 seconds at 16kHz)
  const minBytes = 3200; // 0.1 seconds at 16kHz * 2 bytes per sample
  if (audioData.length < minBytes) {
    return false;
  }

  return true;
}
