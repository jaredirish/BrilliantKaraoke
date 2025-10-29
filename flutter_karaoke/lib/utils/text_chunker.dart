import '../models/app_models.dart';

/// Chunk lyrics for display on smart glasses
List<LyricsChunk> chunkLyrics(
  List<LRCLine> lrcData, {
  int maxWordsPerLine = 8,
  int maxCharsPerLine = 60,
  int linesPerChunk = 2,
}) {
  final chunks = <LyricsChunk>[];

  for (final lrcLine in lrcData) {
    // Split the line into display-friendly chunks
    final lines = _splitLineIntoChunks(
      lrcLine.text,
      maxWordsPerLine,
      maxCharsPerLine,
    );

    // Group lines into chunks (e.g., 2 lines per chunk)
    for (var j = 0; j < lines.length; j += linesPerChunk) {
      final chunkLines = lines.sublist(
        j,
        (j + linesPerChunk).clamp(0, lines.length),
      );

      final wordsPerLine = chunkLines
          .map((line) => line.split(' ').where((w) => w.isNotEmpty).length)
          .toList();

      final startTime = lrcLine.timestamp;
      var endTime = lrcLine.endTime ?? lrcLine.timestamp + 3.0;

      // If we split a line into multiple chunks, adjust timing
      if (lines.length > linesPerChunk) {
        final progress = (j + chunkLines.length) / lines.length;
        endTime = startTime + (endTime - startTime) * progress;
      }

      chunks.add(LyricsChunk(
        lines: chunkLines,
        startTime: startTime,
        endTime: endTime,
        wordsPerLine: wordsPerLine,
      ));
    }
  }

  return chunks;
}

/// Split a text line into multiple chunks respecting word boundaries
List<String> _splitLineIntoChunks(
  String text,
  int maxWords,
  int maxChars,
) {
  final words = text.split(' ').where((w) => w.isNotEmpty).toList();
  final chunks = <String>[];
  final currentChunk = <String>[];
  var currentLength = 0;

  for (final word in words) {
    // If single word exceeds max, add it on its own line
    if (word.length > maxChars) {
      if (currentChunk.isNotEmpty) {
        chunks.add(currentChunk.join(' '));
        currentChunk.clear();
        currentLength = 0;
      }
      chunks.add(word);
      continue;
    }

    // Calculate length if we add this word
    final wordLength = word.length + (currentChunk.isNotEmpty ? 1 : 0); // +1 for space

    // Check if adding this word would exceed limits
    if (currentChunk.length >= maxWords ||
        currentLength + wordLength > maxChars) {
      // Finish current chunk
      if (currentChunk.isNotEmpty) {
        chunks.add(currentChunk.join(' '));
        currentChunk.clear();
        currentLength = 0;
      }
    }

    // Add word to current chunk
    currentChunk.add(word);
    currentLength += wordLength;
  }

  // Add remaining chunk
  if (currentChunk.isNotEmpty) {
    chunks.add(currentChunk.join(' '));
  }

  return chunks.isNotEmpty ? chunks : [''];
}

/// Get the lyrics chunk for the current position
LyricsChunk? getCurrentChunk(
  List<LyricsChunk> chunks,
  double position,
) {
  for (final chunk in chunks) {
    if (chunk.startTime <= position && position < chunk.endTime) {
      return chunk;
    }
  }

  // Check if we're close to the next chunk (within 1 second)
  for (final chunk in chunks) {
    if (chunk.startTime > position && chunk.startTime - position < 1.0) {
      return chunk;
    }
  }

  return null;
}

/// Get the next lyrics chunk after current position
LyricsChunk? getNextChunk(
  List<LyricsChunk> chunks,
  double position,
) {
  // Get current chunk first
  final currentChunk = getCurrentChunk(chunks, position);

  if (currentChunk == null) {
    // No current chunk, find first chunk after position
    for (final chunk in chunks) {
      if (chunk.startTime > position) {
        return chunk;
      }
    }
    return null;
  }

  // Find next chunk after current
  final currentIndex = chunks.indexOf(currentChunk);
  if (currentIndex >= 0 && currentIndex < chunks.length - 1) {
    return chunks[currentIndex + 1];
  }

  return null;
}
