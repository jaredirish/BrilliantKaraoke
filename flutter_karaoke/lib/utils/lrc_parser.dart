import 'dart:math';
import '../models/app_models.dart';

const maxCharsPerLine = 45;
const idealCharsPerLine = 35;

/// Parse LRC format lyrics
List<LRCLine> parseLRC(String lrcContent) {
  final lines = lrcContent.split('\n');
  final lrcLines = <LRCLine>[];

  // Regex to match timestamps: [MM:SS.MS]
  final timeRegex = RegExp(r'^\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)$');

  for (final line in lines) {
    final match = timeRegex.firstMatch(line);
    if (match != null) {
      final minutes = int.parse(match.group(1)!);
      final seconds = int.parse(match.group(2)!);
      // Pad milliseconds to 3 digits if needed
      final millisecondsStr = match.group(3)!.padRight(3, '0');
      final milliseconds = int.parse(millisecondsStr);

      // Calculate timestamp in seconds
      final timestamp = minutes * 60 + seconds + milliseconds / 1000.0;
      final text = match.group(4)!.trim();

      if (text.isNotEmpty) {
        lrcLines.add(LRCLine(
          timestamp: timestamp,
          text: text,
        ));
      }
    }
  }

  // Sort by timestamp
  lrcLines.sort((a, b) => a.timestamp.compareTo(b.timestamp));

  // Calculate end times
  for (var i = 0; i < lrcLines.length - 1; i++) {
    lrcLines[i].endTime = lrcLines[i + 1].timestamp;
  }

  // Last line gets default 5-second duration
  if (lrcLines.isNotEmpty) {
    final lastLine = lrcLines.last;
    lastLine.endTime = lastLine.timestamp + 5.0;
  }

  return lrcLines;
}

/// Preprocess LRC lines by merging short lines and splitting long lines
class PreprocessedLRC {
  final List<LRCLine> lines;
  final Map<String, dynamic> metadata;

  PreprocessedLRC(this.lines, this.metadata);
}

PreprocessedLRC preprocessLRC(List<LRCLine> lrcLines) {
  if (lrcLines.isEmpty) {
    return PreprocessedLRC([], {});
  }

  // Calculate initial statistics
  final totalChars = lrcLines.fold<int>(0, (sum, line) => sum + line.text.length);
  final avgLength = totalChars / lrcLines.length;
  final shortLines = lrcLines.where((line) => line.text.length < 15).length;
  final longLines = lrcLines.where((line) => line.text.length > maxCharsPerLine).length;

  final metadata = {
    'averageLineLength': avgLength,
    'shortLinesCount': shortLines,
    'longLinesCount': longLines,
    'totalLines': lrcLines.length,
  };

  final processedLines = <LRCLine>[];
  var i = 0;

  while (i < lrcLines.length) {
    final currentLine = lrcLines[i];
    final nextLine = i + 1 < lrcLines.length ? lrcLines[i + 1] : null;
    final prevLine = i > 0 ? lrcLines[i - 1] : null;

    // Handle very long lines by splitting
    if (currentLine.text.length > maxCharsPerLine) {
      processedLines.addAll(_splitLongLine(currentLine));
      i++;
      continue;
    }

    // Check if we should merge with next line
    if (nextLine != null && _shouldMergeLines(currentLine, nextLine, prevLine)) {
      final mergedLine = _mergeTwoLines(currentLine, nextLine);

      // If merged line is still reasonable, use it
      if (mergedLine.text.length <= maxCharsPerLine) {
        processedLines.add(mergedLine);
        i += 2;
        continue;
      }
    }

    // Keep line as is
    processedLines.add(currentLine);
    i++;
  }

  return PreprocessedLRC(processedLines, metadata);
}

/// Determine if two lines should be merged
bool _shouldMergeLines(
  LRCLine current,
  LRCLine nextLine,
  LRCLine? prevLine,
) {
  // Don't merge if combined would be too long
  final combinedLength = current.text.length + nextLine.text.length + 1; // +1 for space
  if (combinedLength > maxCharsPerLine) {
    return false;
  }

  // Both lines are very short (likely fragments)
  if (current.text.length < 15 && nextLine.text.length < 15) {
    return true;
  }

  // Lines are close in time (likely same phrase)
  final timeDiff = nextLine.timestamp - (current.endTime ?? current.timestamp);
  if (timeDiff < 1.0) {
    // Less than 1 second gap
    return true;
  }

  // Check for incomplete sentences
  final currentEnding = current.text.isNotEmpty ? current.text[current.text.length - 1] : '';
  final nextWords = nextLine.text.trim().split(' ');
  final nextStartsLower = nextWords.isNotEmpty && nextWords[0][0] == nextWords[0][0].toLowerCase();

  // Current line doesn't end with sentence terminator
  if (!'.!?'.contains(currentEnding)) {
    // Next line starts with lowercase (continuation)
    final firstWord = nextWords.isNotEmpty ? nextWords[0].toLowerCase() : '';
    if (nextStartsLower && firstWord != 'i' && firstWord != 'a') {
      return true;
    }

    // Current line ends with comma or letter
    if (currentEnding == ',' || RegExp(r'[a-zA-Z]').hasMatch(currentEnding)) {
      return true;
    }
  }

  // Question/answer pattern
  if (currentEnding == '?' && nextLine.text.length < 20) {
    return true;
  }

  // Common continuations
  const continuationWords = ['but', 'and', 'or', 'so', 'because', 'when', 'while', 'if'];
  final firstWordNext = nextWords.isNotEmpty ? nextWords[0].toLowerCase() : '';
  if (continuationWords.contains(firstWordNext)) {
    return true;
  }

  return false;
}

/// Merge two LRC lines into one
LRCLine _mergeTwoLines(LRCLine line1, LRCLine line2) {
  // Determine appropriate separator
  final line1Ending = line1.text.isNotEmpty ? line1.text[line1.text.length - 1] : '';
  var separator = ' ';

  // Add comma before conjunctions if no punctuation
  if (RegExp(r'[a-zA-Z]').hasMatch(line1Ending)) {
    final line2Words = line2.text.trim().split(' ');
    final firstWord = line2Words.isNotEmpty ? line2Words[0].toLowerCase() : '';
    if (['but', 'and', 'or', 'so'].contains(firstWord)) {
      separator = ', ';
    }
  }

  return LRCLine(
    timestamp: line1.timestamp,
    text: line1.text.trim() + separator + line2.text.trim(),
    endTime: line2.endTime ?? line2.timestamp + 2.0,
  );
}

/// Split a long line into multiple shorter lines
List<LRCLine> _splitLongLine(LRCLine line) {
  final words = line.text.trim().split(' ');
  final chunks = <String>[];
  var currentChunk = '';

  for (final word in words) {
    final testChunk = currentChunk.isEmpty ? word : '$currentChunk $word';

    if (testChunk.length <= idealCharsPerLine) {
      currentChunk = testChunk;
    } else {
      // Try to find a good break point
      if (currentChunk.isNotEmpty) {
        chunks.add(currentChunk);
        currentChunk = word;
      } else {
        // Single word is too long, add it anyway
        chunks.add(word);
      }
    }
  }

  if (currentChunk.isNotEmpty) {
    chunks.add(currentChunk);
  }

  // Create LRCLine objects for each chunk
  final duration = (line.endTime ?? line.timestamp + 2.0) - line.timestamp;
  final chunkDuration = chunks.isNotEmpty ? duration / chunks.length : duration;

  return List.generate(chunks.length, (i) {
    return LRCLine(
      timestamp: line.timestamp + (chunkDuration * i),
      text: chunks[i],
      endTime: line.timestamp + (chunkDuration * (i + 1)),
    );
  });
}

/// Analyze LRC patterns to determine if preprocessing is recommended
Map<String, dynamic> analyzeLRCPatterns(List<LRCLine> lines) {
  if (lines.isEmpty) {
    return {
      'hasShortLines': false,
      'hasLongLines': false,
      'averageGap': 0.0,
      'recommendPreprocessing': false,
    };
  }

  var totalGap = 0.0;
  var gapCount = 0;
  var shortLines = 0;
  var longLines = 0;

  for (var i = 0; i < lines.length - 1; i++) {
    final gap = lines[i + 1].timestamp - (lines[i].endTime ?? lines[i].timestamp);
    totalGap += gap;
    gapCount++;

    if (lines[i].text.length < 15) shortLines++;
    if (lines[i].text.length > maxCharsPerLine) longLines++;
  }

  final averageGap = gapCount > 0 ? totalGap / gapCount : 0.0;
  final shortLineRatio = lines.isNotEmpty ? shortLines / lines.length : 0.0;
  final hasShortLines = shortLineRatio > 0.3; // More than 30% short
  final hasLongLines = longLines > 0;

  return {
    'hasShortLines': hasShortLines,
    'hasLongLines': hasLongLines,
    'averageGap': averageGap,
    'recommendPreprocessing': hasShortLines || hasLongLines || averageGap < 1.5,
  };
}

/// Format seconds as MM:SS
String formatTimestamp(double seconds) {
  final mins = seconds ~/ 60;
  final secs = (seconds % 60).floor();
  return '$mins:${secs.toString().padLeft(2, '0')}';
}
