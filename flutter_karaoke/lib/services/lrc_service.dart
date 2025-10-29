import 'dart:convert';
import 'package:http/http.dart' as http;

/// LRC lyrics fetching service
class LRCService {
  final String lrclibBaseUrl = 'https://lrclib.net';

  /// Fetch LRC lyrics for a song
  Future<String?> fetchLRC(String title, String artist) async {
    try {
      // Build search URL
      final params = {
        'track_name': title,
        'artist_name': artist,
      };

      final uri = Uri.parse('$lrclibBaseUrl/api/search')
          .replace(queryParameters: params);

      // Search for song
      final response = await http.get(uri);

      if (response.statusCode != 200) {
        return null;
      }

      final results = json.decode(response.body) as List<dynamic>;

      if (results.isEmpty) {
        return null;
      }

      // Find best match
      final bestMatch = _findBestMatch(results, title, artist);

      if (bestMatch == null) {
        return null;
      }

      // Check if synced lyrics are in the result
      final syncedLyrics = bestMatch['syncedLyrics'] as String?;
      if (syncedLyrics != null && syncedLyrics.isNotEmpty) {
        return syncedLyrics;
      }

      // If not, try to fetch by ID
      final id = bestMatch['id'] as int?;
      if (id != null) {
        return await _fetchById(id);
      }

      return null;
    } catch (e) {
      print('Error fetching lyrics: $e');
      return null;
    }
  }

  /// Fetch lyrics by ID
  Future<String?> _fetchById(int id) async {
    try {
      final uri = Uri.parse('$lrclibBaseUrl/api/get/$id');
      final response = await http.get(uri);

      if (response.statusCode != 200) {
        return null;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      return data['syncedLyrics'] as String?;
    } catch (e) {
      print('Error fetching lyrics by ID: $e');
      return null;
    }
  }

  /// Find best matching result from search results
  Map<String, dynamic>? _findBestMatch(
    List<dynamic> results,
    String title,
    String artist,
  ) {
    final titleLower = title.toLowerCase();
    final artistLower = artist.toLowerCase();

    // Try to find exact match with synced lyrics
    for (final result in results) {
      final resultMap = result as Map<String, dynamic>;
      final trackName = (resultMap['trackName'] as String?)?.toLowerCase();
      final artistName = (resultMap['artistName'] as String?)?.toLowerCase();
      final hasSyncedLyrics = resultMap['syncedLyrics'] != null;

      if (hasSyncedLyrics &&
          trackName == titleLower &&
          artistName == artistLower) {
        return resultMap;
      }
    }

    // Try to find any result with synced lyrics
    for (final result in results) {
      final resultMap = result as Map<String, dynamic>;
      if (resultMap['syncedLyrics'] != null) {
        return resultMap;
      }
    }

    // Fall back to first result
    return results.isNotEmpty ? results[0] as Map<String, dynamic> : null;
  }
}
