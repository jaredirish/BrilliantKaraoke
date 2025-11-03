import 'dart:async';
import 'dart:typed_data';
import 'package:frame_sdk/frame_sdk.dart';
import 'package:frame_sdk/display.dart';
import 'package:record/record.dart';

import 'models/app_models.dart';
import 'services/acrcloud_service.dart';
import 'services/lrc_service.dart';
import 'managers/recognition_manager.dart';
import 'managers/lyrics_manager.dart';
import 'managers/position_tracker.dart';
import 'managers/display_manager.dart';
import 'managers/history_manager.dart';

/// Audio source for the app
enum AudioSource {
  frame,      // Frame glasses microphone
  phone,      // Phone's built-in microphone
}

/// Main karaoke application for Frame glasses
class KaraokeApp {
  final Frame? frame;  // Optional now for test mode
  final String acrcloudHost;
  final String acrcloudAccessKey;
  final String acrcloudSecretKey;
  final AudioSource audioSource;

  // Phone microphone recorder (for test mode)
  final AudioRecorder _audioRecorder = AudioRecorder();

  // Services
  late final ACRCloudService _acrcloudService;
  late final LRCService _lrcService;

  // Managers
  late final RecognitionManager _recognitionManager;
  late final LyricsManager _lyricsManager;
  late final PositionTracker _positionTracker;
  late final DisplayManager _displayManager;
  late final HistoryManager _historyManager;

  // State
  CurrentSong? currentSong;
  AppState appState = AppState.listening;
  bool _isRunning = false;

  // Timers
  Timer? _recognitionTimer;
  Timer? _displayTimer;
  Timer? _phoneAudioTimer;

  // Display callback for showing lyrics in app UI
  Function(String)? onDisplayUpdate;

  KaraokeApp({
    this.frame,
    required this.acrcloudHost,
    required this.acrcloudAccessKey,
    required this.acrcloudSecretKey,
    this.audioSource = AudioSource.frame,
    this.onDisplayUpdate,
  }) {
    _initializeServices();
  }

  void _initializeServices() {
    // Initialize services
    _acrcloudService = ACRCloudService(
      host: acrcloudHost,
      accessKey: acrcloudAccessKey,
      secretKey: acrcloudSecretKey,
    );
    _lrcService = LRCService();

    // Initialize managers
    _recognitionManager = RecognitionManager(
      acrcloudService: _acrcloudService,
    );
    _lyricsManager = LyricsManager(_lrcService);
    _positionTracker = PositionTracker();
    _displayManager = DisplayManager();
    _historyManager = HistoryManager();
  }

  /// Start the karaoke app
  Future<void> start() async {
    _isRunning = true;

    // Show welcome message
    await _updateDisplay();

    // Start recognition
    _recognitionManager.startListening();

    // Start audio capture based on source
    if (audioSource == AudioSource.phone) {
      await _startPhoneAudioCapture();
    }
    // For Frame, audio will be added via addAudioChunk() calls

    // Start periodic recognition checks (every 1 second)
    _recognitionTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_recognitionManager.shouldRecognize()) {
        await _performRecognition();
      }
    });

    // Start display updates (every 500ms)
    _displayTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (_displayManager.shouldUpdate()) {
        await _updateDisplay();
      }
    });
  }

  /// Start phone microphone audio capture
  Future<void> _startPhoneAudioCapture() async {
    try {
      // Check and request permission
      if (!await _audioRecorder.hasPermission()) {
        print('Microphone permission denied');
        return;
      }

      // Start recording in chunks
      _phoneAudioTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
        try {
          // Start recording to stream
          final stream = await _audioRecorder.startStream(
            const RecordConfig(
              encoder: AudioEncoder.pcm16bits,
              sampleRate: 16000,
              numChannels: 1,
            ),
          );

          // Collect 2 seconds of audio
          final chunks = <Uint8List>[];
          final subscription = stream.listen((data) {
            chunks.add(Uint8List.fromList(data));
          });

          // Wait 2 seconds
          await Future.delayed(const Duration(seconds: 2));

          // Stop recording
          await subscription.cancel();
          await _audioRecorder.stop();

          // Combine chunks and add to recognition buffer
          if (chunks.isNotEmpty) {
            final combined = Uint8List.fromList(
              chunks.expand((chunk) => chunk).toList(),
            );
            addAudioChunk(combined);
          }
        } catch (e) {
          print('Phone audio capture error: $e');
        }
      });
    } catch (e) {
      print('Failed to start phone audio: $e');
    }
  }

  /// Stop the karaoke app
  Future<void> stop() async {
    _isRunning = false;
    _recognitionManager.stopListening();
    _recognitionTimer?.cancel();
    _displayTimer?.cancel();
    _phoneAudioTimer?.cancel();

    // Stop phone audio recording
    if (audioSource == AudioSource.phone) {
      try {
        await _audioRecorder.stop();
      } catch (e) {
        print('Error stopping audio recorder: $e');
      }
    }
  }

  /// Add audio chunk from Frame microphone
  void addAudioChunk(Uint8List audioData) {
    _recognitionManager.addAudioChunk(audioData);
  }

  /// Perform song recognition
  Future<void> _performRecognition() async {
    final result = await _recognitionManager.recognize();

    if (result == null || !result.isValid) {
      // No song detected or error
      if (currentSong != null) {
        // Check if song has ended
        final position = _positionTracker.getCurrentPosition();
        if (position > currentSong!.duration + 5) {
          await _endSong();
        }
      }
      return;
    }

    // Got a recognition result
    await _handleRecognitionResult(result);
  }

  /// Handle song recognition result
  Future<void> _handleRecognitionResult(RecognitionResult result) async {
    // Check if this is a new song or continuation
    if (currentSong == null) {
      // New song detected
      await _startNewSong(result);
    } else {
      // Check if same song or different song
      if (result.title == currentSong!.title &&
          result.artist == currentSong!.artist) {
        // Same song - update position
        _updateSongPosition(result);
      } else {
        // Different song detected
        if (result.confidence > 0.75) {
          // High confidence for song switch
          await _switchSong(result);
        }
      }
    }
  }

  /// Start tracking a new song
  Future<void> _startNewSong(RecognitionResult result) async {
    currentSong = CurrentSong(
      title: result.title,
      artist: result.artist,
      album: result.album,
      duration: result.duration ?? 180.0, // Default 3 minutes
      detectedAt: DateTime.now(),
      hasLyrics: false,
      confidence: result.confidence,
    );

    // Start position tracking
    if (result.offsetSeconds != null) {
      _positionTracker.startSong(
        DateTime.now(),
        result.offsetSeconds!,
        result.apiLatency ?? 0,
      );
    }

    // Add to history
    _historyManager.addSong(currentSong!);

    // Set state to processing while we fetch lyrics
    appState = AppState.processing;

    // Fetch lyrics
    final lrcData = await _lyricsManager.fetchLyrics(currentSong!);

    if (lrcData != null && lrcData.isNotEmpty) {
      currentSong!.hasLyrics = true;
      currentSong!.lrcData = lrcData;
      appState = AppState.songDetectedWithLyrics;
    } else {
      appState = AppState.songDetectedNoLyrics;
    }
  }

  /// Update position tracking for current song
  void _updateSongPosition(RecognitionResult result) {
    if (result.offsetSeconds != null) {
      _positionTracker.recalibrate(
        result.offsetSeconds!,
        DateTime.now(),
        result.confidence,
        result.apiLatency ?? 0,
      );
    }
  }

  /// Switch to a different song
  Future<void> _switchSong(RecognitionResult result) async {
    await _endSong();
    await _startNewSong(result);
  }

  /// End current song tracking
  Future<void> _endSong() async {
    currentSong = null;
    appState = AppState.listening;
    _positionTracker.reset();
  }

  /// Update Frame display
  Future<void> _updateDisplay() async {
    // Get current position
    final position = _positionTracker.getCurrentPosition();

    // Get current and next lyrics chunks
    LyricsChunk? currentChunk;
    LyricsChunk? nextChunk;

    if (currentSong != null && currentSong!.hasLyrics) {
      currentChunk = _lyricsManager.getCurrentChunk(position);
      nextChunk = _lyricsManager.getNextChunk(position);
    }

    // Format display
    final displayText = _displayManager.formatDisplay(
      appState: appState,
      currentSong: currentSong,
      currentChunk: currentChunk,
      nextChunk: nextChunk,
      currentPosition: position,
    );

    // Send to Frame (if connected)
    if (frame != null && audioSource == AudioSource.frame) {
      try {
        await frame!.display.showText(displayText);
      } catch (e) {
        print('Display update error: $e');
      }
    }

    // Also send to app UI callback
    if (onDisplayUpdate != null) {
      onDisplayUpdate!(displayText);
    }
  }

  /// Get current app state (for UI)
  String get currentStateString {
    switch (appState) {
      case AppState.listening:
        return 'Listening for music...';
      case AppState.processing:
        return 'Processing song...';
      case AppState.songDetectedNoLyrics:
        return 'Playing: ${currentSong?.title ?? "Unknown"}';
      case AppState.songDetectedWithLyrics:
        return 'Playing with lyrics: ${currentSong?.title ?? "Unknown"}';
    }
  }

  /// Check if currently running
  bool get isRunning => _isRunning;

  /// Dispose resources
  void dispose() {
    _audioRecorder.dispose();
  }
}
