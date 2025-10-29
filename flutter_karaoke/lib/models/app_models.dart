/// Data models for Flutter Karaoke application

/// Application state
enum AppState {
  listening,
  processing,
  songDetectedNoLyrics,
  songDetectedWithLyrics,
}

/// Currently playing song information
class CurrentSong {
  final String title;
  final String artist;
  final String? album;
  final double duration; // seconds
  final DateTime detectedAt;
  final bool hasLyrics;
  final double confidence; // 0.0 to 1.0
  List<LRCLine>? lrcData;

  CurrentSong({
    required this.title,
    required this.artist,
    this.album,
    required this.duration,
    required this.detectedAt,
    required this.hasLyrics,
    required this.confidence,
    this.lrcData,
  });
}

/// A single line from an LRC file
class LRCLine {
  final double timestamp; // seconds
  final String text;
  double? endTime; // seconds

  LRCLine({
    required this.timestamp,
    required this.text,
    this.endTime,
  });
}

/// A chunk of lyrics formatted for display
class LyricsChunk {
  final List<String> lines; // Max 2 lines
  final double startTime; // seconds
  final double endTime; // seconds
  final List<int> wordsPerLine;

  LyricsChunk({
    required this.lines,
    required this.startTime,
    required this.endTime,
    required this.wordsPerLine,
  });
}

/// Result from song recognition service
class RecognitionResult {
  final String title;
  final String artist;
  final String? album;
  final double? duration; // seconds
  final double? offsetSeconds; // Position in song when detected
  final double confidence; // 0.0 to 1.0
  final String? error;
  double? apiLatency; // milliseconds

  RecognitionResult({
    required this.title,
    required this.artist,
    this.album,
    this.duration,
    this.offsetSeconds,
    required this.confidence,
    this.error,
    this.apiLatency,
  });

  bool get hasError => error != null;
  bool get isValid => title.isNotEmpty && artist.isNotEmpty && !hasError;
}

/// A point in time when a song was recognized
class RecognitionPoint {
  final DateTime timestamp; // When recognition occurred
  final double detectedOffset; // Position in song that was detected
  final double confidence;
  final double apiLatency; // milliseconds
  final double drift;

  RecognitionPoint({
    required this.timestamp,
    required this.detectedOffset,
    required this.confidence,
    required this.apiLatency,
    required this.drift,
  });
}

/// Entry in song history
class SongHistoryEntry {
  final String title;
  final String artist;
  final String? album;
  final DateTime identifiedAt;
  final double? duration; // seconds
  final double confidence;

  SongHistoryEntry({
    required this.title,
    required this.artist,
    this.album,
    required this.identifiedAt,
    this.duration,
    required this.confidence,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'artist': artist,
        'album': album,
        'identifiedAt': identifiedAt.millisecondsSinceEpoch,
        'duration': duration,
        'confidence': confidence,
      };

  factory SongHistoryEntry.fromJson(Map<String, dynamic> json) {
    return SongHistoryEntry(
      title: json['title'] as String,
      artist: json['artist'] as String,
      album: json['album'] as String?,
      identifiedAt:
          DateTime.fromMillisecondsSinceEpoch(json['identifiedAt'] as int),
      duration: json['duration'] as double?,
      confidence: json['confidence'] as double,
    );
  }
}
