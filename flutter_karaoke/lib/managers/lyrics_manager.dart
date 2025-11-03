import '../models/app_models.dart';
import '../services/lrc_service.dart';
import '../utils/lrc_parser.dart';
import '../utils/text_chunker.dart' as text_chunker;

/// Lyrics fetching and management
class LyricsManager {
  final LRCService lrcService;
  final Map<String, List<LRCLine>> _cachedLRC = {};
  List<LyricsChunk> currentChunks = [];

  LyricsManager(this.lrcService);

  /// Fetch and parse lyrics for a song
  Future<List<LRCLine>?> fetchLyrics(CurrentSong song) async {
    final cacheKey = '${song.artist}-${song.title}';

    // Check cache first
    if (_cachedLRC.containsKey(cacheKey)) {
      return _cachedLRC[cacheKey];
    }

    try {
      // Fetch LRC content
      final lrcContent = await lrcService.fetchLRC(song.title, song.artist);

      if (lrcContent == null) {
        return null;
      }

      // Parse LRC
      final rawLrcData = parseLRC(lrcContent);

      if (rawLrcData.isEmpty) {
        return null;
      }

      // Analyze if preprocessing would help
      final analysis = analyzeLRCPatterns(rawLrcData);

      var lrcData = rawLrcData;
      if (analysis['recommendPreprocessing'] == true) {
        final preprocessed = preprocessLRC(rawLrcData);
        lrcData = preprocessed.lines;
      }

      // Cache the processed lyrics
      _cachedLRC[cacheKey] = lrcData;

      // Create chunks for display
      currentChunks = text_chunker.chunkLyrics(lrcData);

      return lrcData;
    } catch (e) {
      print('Error fetching lyrics: $e');
      return null;
    }
  }

  /// Get lyrics chunk for current position
  LyricsChunk? getCurrentChunk(double position) {
    return text_chunker.getCurrentChunk(currentChunks, position);
  }

  /// Get next lyrics chunk after current position
  LyricsChunk? getNextChunk(double position) {
    return text_chunker.getNextChunk(currentChunks, position);
  }

  /// Clear lyrics cache
  void clearCache() {
    _cachedLRC.clear();
    currentChunks = [];
  }

  /// Get number of cached lyrics
  int get cacheSize => _cachedLRC.length;
}
