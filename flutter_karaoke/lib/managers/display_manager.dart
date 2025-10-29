import '../models/app_models.dart';
import '../utils/lrc_parser.dart';

/// Display formatting manager for Frame glasses
class DisplayManager {
  DateTime _lastUpdateTime = DateTime.now();
  final Duration updateInterval;

  DisplayManager({this.updateInterval = const Duration(milliseconds: 500)});

  /// Format display text based on current state
  String formatDisplay({
    required AppState appState,
    CurrentSong? currentSong,
    LyricsChunk? currentChunk,
    LyricsChunk? nextChunk,
    double currentPosition = 0.0,
  }) {
    switch (appState) {
      case AppState.listening:
        return _formatListening();

      case AppState.processing:
        return _formatProcessing();

      case AppState.songDetectedNoLyrics:
        if (currentSong != null) {
          return _formatSongInfo(currentSong, currentPosition);
        }
        return _formatListening();

      case AppState.songDetectedWithLyrics:
        if (currentSong != null) {
          return _formatLyricsDisplay(
            currentSong,
            currentChunk,
            nextChunk,
            currentPosition,
          );
        }
        return _formatListening();
    }
  }

  /// Format listening state display
  String _formatListening() {
    return '♪ Listening...';
  }

  /// Format processing state display
  String _formatProcessing() {
    return 'Processing...\nFetching lyrics...';
  }

  /// Format song info without lyrics
  String _formatSongInfo(CurrentSong song, double position) {
    final lines = <String>[
      '♪ ${song.title}',
      '  ${song.artist}',
    ];

    if (song.album != null && song.album!.isNotEmpty) {
      lines.add('  ${song.album}');
    }

    lines.add(''); // Empty line for spacing

    // Add timestamp
    final timeStr = '  ${formatTimestamp(position)} / ${formatTimestamp(song.duration)}';
    lines.add(timeStr);

    return lines.join('\n');
  }

  /// Format lyrics display with current and next chunks
  String _formatLyricsDisplay(
    CurrentSong song,
    LyricsChunk? currentChunk,
    LyricsChunk? nextChunk,
    double position,
  ) {
    if (currentChunk == null) {
      // No current chunk, show song info
      return _formatSongInfo(song, position);
    }

    final lines = <String>[];

    // Show current lyrics lines
    lines.addAll(currentChunk.lines);

    // Add separator before preview
    if (nextChunk != null) {
      lines.add('-----');

      // Show preview of next chunk (first line only)
      if (nextChunk.lines.isNotEmpty) {
        var preview = nextChunk.lines[0];
        // Truncate if too long
        if (preview.length > 45) {
          preview = '${preview.substring(0, 42)}...';
        }
        lines.add(preview);
      }
    }

    // Add timestamp at bottom
    final timeStr = '${formatTimestamp(position)} / ${formatTimestamp(song.duration)}';
    lines.add(''); // Empty line for spacing
    lines.add(timeStr);

    return lines.join('\n');
  }

  /// Format display for instrumental breaks
  String formatInstrumental(CurrentSong song, double position) {
    return [
      '♪ ${song.title}',
      '  ${song.artist}',
      '',
      '  ♪ Instrumental ♪',
      '  ${formatTimestamp(position)} / ${formatTimestamp(song.duration)}',
    ].join('\n');
  }

  /// Format error message for display
  String formatError(String errorMessage) {
    return 'Error:\n$errorMessage';
  }

  /// Format welcome message
  String formatWelcome() {
    return '♪ Frame Karaoke\n\nPlay some music to\nget started!';
  }

  /// Check if enough time has passed for display update
  bool shouldUpdate() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastUpdateTime);

    if (elapsed >= updateInterval) {
      _lastUpdateTime = now;
      return true;
    }

    return false;
  }
}
