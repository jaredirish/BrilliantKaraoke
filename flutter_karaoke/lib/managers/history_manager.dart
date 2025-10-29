import 'dart:convert';
import '../models/app_models.dart';

/// Song history tracking manager
class HistoryManager {
  final List<SongHistoryEntry> history = [];
  final int maxHistorySize;
  final Duration duplicateWindow;

  HistoryManager({
    this.maxHistorySize = 100,
    this.duplicateWindow = const Duration(seconds: 30),
  });

  /// Add song to history if not a duplicate
  void addSong(CurrentSong song) {
    if (isDuplicate(song)) {
      return;
    }

    final entry = SongHistoryEntry(
      title: song.title,
      artist: song.artist,
      album: song.album,
      identifiedAt: DateTime.now(),
      duration: song.duration,
      confidence: song.confidence,
    );

    // Add to front of list (most recent first)
    history.insert(0, entry);

    // Trim to max size
    if (history.length > maxHistorySize) {
      history.removeRange(maxHistorySize, history.length);
    }
  }

  /// Get recent songs from history
  List<SongHistoryEntry> getRecentSongs([int? limit]) {
    if (limit == null) {
      return List.from(history);
    }
    return history.take(limit).toList();
  }

  /// Check if song was recently added to history
  bool isDuplicate(CurrentSong song) {
    final now = DateTime.now();
    final recentCutoff = now.subtract(duplicateWindow);

    return history.any((entry) =>
        entry.title == song.title &&
        entry.artist == song.artist &&
        entry.identifiedAt.isAfter(recentCutoff));
  }

  /// Clear all history
  void clearHistory() {
    history.clear();
  }

  /// Export history as JSON string
  String exportHistory() {
    final historyMaps = history.map((entry) => entry.toJson()).toList();
    return json.encode(historyMaps);
  }

  /// Import history from JSON string
  bool importHistory(String jsonData) {
    try {
      final List<dynamic> imported = json.decode(jsonData);

      history.clear();
      for (final item in imported) {
        if (item is Map<String, dynamic>) {
          history.add(SongHistoryEntry.fromJson(item));
        }
      }

      // Trim to max size
      if (history.length > maxHistorySize) {
        history.removeRange(maxHistorySize, history.length);
      }

      return true;
    } catch (e) {
      print('Error importing history: $e');
      return false;
    }
  }

  /// Get current history size
  int get historySize => history.length;

  /// Find a specific song in history
  SongHistoryEntry? findSong(String title, String artist) {
    final titleLower = title.toLowerCase();
    final artistLower = artist.toLowerCase();

    for (final entry in history) {
      if (entry.title.toLowerCase() == titleLower &&
          entry.artist.toLowerCase() == artistLower) {
        return entry;
      }
    }

    return null;
  }

  /// Calculate statistics from history
  Map<String, dynamic> getStatistics() {
    if (history.isEmpty) {
      return {
        'totalSongs': 0,
        'uniqueSongs': 0,
        'avgConfidence': 0.0,
        'mostPlayedSong': null,
      };
    }

    // Count unique songs
    final songKeys = <String>{};
    final songCounts = <String, int>{};
    var totalConfidence = 0.0;

    for (final entry in history) {
      final key = '${entry.artist} - ${entry.title}';
      songKeys.add(key);
      songCounts[key] = (songCounts[key] ?? 0) + 1;
      totalConfidence += entry.confidence;
    }

    // Find most played song
    String? mostPlayedSong;
    var maxCount = 0;

    songCounts.forEach((song, count) {
      if (count > maxCount) {
        maxCount = count;
        mostPlayedSong = song;
      }
    });

    return {
      'totalSongs': history.length,
      'uniqueSongs': songKeys.length,
      'avgConfidence': totalConfidence / history.length,
      'mostPlayedSong':
          mostPlayedSong != null ? {'song': mostPlayedSong, 'count': maxCount} : null,
    };
  }
}
