import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../models/app_models.dart';

/// ACRCloud song recognition service
class ACRCloudService {
  final String host;
  final String accessKey;
  final String secretKey;

  ACRCloudService({
    required this.host,
    required this.accessKey,
    required this.secretKey,
  });

  /// Recognize song from audio data
  Future<RecognitionResult> recognize(Uint8List audioData) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final signature = _buildSignature(timestamp);

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('https://$host/v1/identify'),
      );

      // Add form fields
      request.fields['access_key'] = accessKey;
      request.fields['sample_bytes'] = audioData.length.toString();
      request.fields['timestamp'] = timestamp.toString();
      request.fields['signature'] = signature;
      request.fields['data_type'] = 'audio';
      request.fields['signature_version'] = '1';

      // Add audio file
      request.files.add(http.MultipartFile.fromBytes(
        'sample',
        audioData,
        filename: 'audio.wav',
      ));

      // Send request
      final response = await request.send();
      final responseData = await response.stream.bytesToString();

      if (response.statusCode != 200) {
        return RecognitionResult(
          title: '',
          artist: '',
          confidence: 0.0,
          error: 'ACRCloud API error: ${response.statusCode}',
        );
      }

      // Parse JSON response
      final data = json.decode(responseData) as Map<String, dynamic>;

      // Check status code
      final status = data['status'] as Map<String, dynamic>?;
      if (status?['code'] != 0) {
        return RecognitionResult(
          title: '',
          artist: '',
          confidence: 0.0,
          error: status?['msg'] ?? 'Recognition failed',
        );
      }

      // Extract music metadata
      final metadata = data['metadata'] as Map<String, dynamic>?;
      final music = metadata?['music'] as List<dynamic>?;

      if (music == null || music.isEmpty) {
        return RecognitionResult(
          title: '',
          artist: '',
          confidence: 0.0,
          error: 'No music detected',
        );
      }

      // Parse first match
      final musicInfo = music[0] as Map<String, dynamic>;

      return RecognitionResult(
        title: musicInfo['title'] as String? ?? '',
        artist: _extractArtist(musicInfo),
        album: (musicInfo['album'] as Map<String, dynamic>?)?['name'] as String?,
        duration: _msToSeconds(musicInfo['duration_ms'] as int?),
        offsetSeconds: _msToSeconds(musicInfo['play_offset_ms'] as int?),
        confidence: _normalizeConfidence(musicInfo['score'] as int?),
      );
    } catch (e) {
      return RecognitionResult(
        title: '',
        artist: '',
        confidence: 0.0,
        error: 'Error: $e',
      );
    }
  }

  /// Build HMAC-SHA1 signature for ACRCloud API
  String _buildSignature(int timestamp) {
    final stringToSign =
        'POST\n/v1/identify\n$accessKey\naudio\n1\n$timestamp';

    final key = utf8.encode(secretKey);
    final bytes = utf8.encode(stringToSign);

    final hmac = Hmac(sha1, key);
    final digest = hmac.convert(bytes);

    return base64.encode(digest.bytes);
  }

  /// Extract artist name from music metadata
  String _extractArtist(Map<String, dynamic> musicInfo) {
    final artists = musicInfo['artists'] as List<dynamic>?;
    if (artists != null && artists.isNotEmpty) {
      final artist = artists[0] as Map<String, dynamic>?;
      return artist?['name'] as String? ?? '';
    }
    return '';
  }

  /// Convert milliseconds to seconds
  double? _msToSeconds(int? milliseconds) {
    if (milliseconds == null) return null;
    return milliseconds / 1000.0;
  }

  /// Normalize ACRCloud confidence score from 0-100 to 0-1
  double _normalizeConfidence(int? score) {
    if (score == null) return 0.5;
    return (score / 100.0).clamp(0.0, 1.0);
  }
}
