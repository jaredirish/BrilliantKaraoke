import 'dart:typed_data';
import '../models/app_models.dart';
import '../services/acrcloud_service.dart';
import '../utils/audio_utils.dart';

/// Audio recognition and buffering manager
class RecognitionManager {
  final ACRCloudService acrcloudService;
  final int sampleRate;

  final List<Uint8List> _audioBuffer = [];
  bool _isRecording = false;
  DateTime _lastRecognitionTime = DateTime.now();

  final Duration recognitionInterval;
  final Duration maxBufferDuration;
  final Duration minAudioDuration;

  RecognitionManager({
    required this.acrcloudService,
    this.sampleRate = 16000,
    this.recognitionInterval = const Duration(seconds: 12),
    this.maxBufferDuration = const Duration(seconds: 8),
    this.minAudioDuration = const Duration(seconds: 3),
  });

  /// Start audio recording and recognition
  void startListening() {
    _isRecording = true;
    _audioBuffer.clear();
    _lastRecognitionTime = DateTime.now();
  }

  /// Stop audio recording
  void stopListening() {
    _isRecording = false;
  }

  /// Add audio chunk to buffer
  void addAudioChunk(Uint8List audioData) {
    if (!_isRecording) return;

    _audioBuffer.add(audioData);

    // Combine and trim buffer to max duration
    final combined = combineAudioChunks(_audioBuffer);
    final trimmed = trimAudioBuffer(
      combined,
      maxBufferDuration.inMilliseconds / 1000.0,
      sampleRate,
    );

    _audioBuffer.clear();
    _audioBuffer.add(trimmed);
  }

  /// Check if it's time to perform recognition
  bool shouldRecognize() {
    final now = DateTime.now();

    // First recognition - wait for enough audio
    if (_lastRecognitionTime == DateTime.now()) {
      if (_audioBuffer.isEmpty) return false;

      final combined = combineAudioChunks(_audioBuffer);
      final duration = calculateAudioDuration(combined.length, sampleRate);
      return duration >= minAudioDuration.inMilliseconds / 1000.0;
    }

    // Subsequent recognitions - check interval
    final elapsed = now.difference(_lastRecognitionTime);
    return elapsed >= recognitionInterval;
  }

  /// Perform song recognition on buffered audio
  Future<RecognitionResult?> recognize() async {
    if (_audioBuffer.isEmpty) {
      return null;
    }

    final startTime = DateTime.now();

    // Combine audio chunks
    final audioData = combineAudioChunks(_audioBuffer);

    // Validate audio
    if (!validateAudioData(audioData)) {
      return null;
    }

    // Create WAV buffer
    final wavBuffer = createWavBuffer(audioData, sampleRate);

    try {
      // Send to ACRCloud
      final result = await acrcloudService.recognize(wavBuffer);
      final apiLatency = DateTime.now().difference(startTime).inMilliseconds.toDouble();

      // Update last recognition time
      _lastRecognitionTime = DateTime.now();

      if (result.hasError || !result.isValid) {
        return null;
      }

      // Add API latency to result
      result.apiLatency = apiLatency;

      return result;
    } catch (e) {
      print('Recognition error: $e');
      _lastRecognitionTime = DateTime.now();
      return null;
    }
  }

  /// Reset recognition state
  void reset() {
    _audioBuffer.clear();
    _lastRecognitionTime = DateTime.now();
  }

  /// Get current buffer duration in seconds
  double get bufferDuration {
    if (_audioBuffer.isEmpty) return 0.0;

    final combined = combineAudioChunks(_audioBuffer);
    return calculateAudioDuration(combined.length, sampleRate);
  }

  /// Check if currently recording
  bool get isRecording => _isRecording;
}
