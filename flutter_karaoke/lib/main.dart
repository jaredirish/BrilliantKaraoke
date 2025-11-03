import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
// TODO: Re-enable Frame SDK once Gradle compatibility is resolved
// import 'package:frame_sdk/frame_sdk.dart';
// import 'package:frame_sdk/bluetooth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

import 'karaoke_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: '.env');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Frame Karaoke',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const KaraokeScreen(),
    );
  }
}

class KaraokeScreen extends StatefulWidget {
  const KaraokeScreen({super.key});

  @override
  State<KaraokeScreen> createState() => _KaraokeScreenState();
}

class _KaraokeScreenState extends State<KaraokeScreen> {
  // TODO: Re-enable Frame when SDK is fixed
  // final Frame _frame = Frame();
  KaraokeApp? _karaokeApp;

  bool _isConnected = false;
  bool _isRunning = false;
  String _statusMessage = 'Select audio source to begin';
  int? _batteryLevel;
  String _lyricsDisplay = '';

  // Audio source selection
  // Frame mode temporarily disabled
  AudioSource _selectedAudioSource = AudioSource.phone;

  @override
  void initState() {
    super.initState();
    _requestInitialPermissions();
  }

  @override
  void dispose() {
    _karaokeApp?.dispose();
    _karaokeApp?.stop();
    super.dispose();
  }

  Future<void> _requestInitialPermissions() async {
    // TODO: Re-enable when Frame SDK is fixed
    // try {
    //   // Request Bluetooth permissions
    //   await BrilliantBluetooth.requestPermission();
    // } catch (e) {
    //   print('Permission error: $e');
    // }
  }

  Future<void> _requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      _showError('Microphone permission denied');
    }
  }

  Future<void> _connectToFrame() async {
    // TODO: Re-enable when Frame SDK is fixed
    _showError('Frame mode temporarily disabled');
    return;

    // setState(() {
    //   _statusMessage = 'Connecting to Frame...';
    // });
    // try {
    //   final connected = await _frame.connect();
    //   if (!connected) {
    //     _showError('Failed to connect to Frame');
    //     return;
    //   }
    //   setState(() {
    //     _isConnected = true;
    //     _statusMessage = 'Connected to Frame';
    //   });
    //   _batteryLevel = await _frame.getBatteryLevel();
    //   setState(() {
    //     _statusMessage = 'Frame connected - ready to start';
    //   });
    // } catch (e) {
    //   _showError('Connection error: $e');
    // }
  }

  Future<void> _startKaraoke() async {
    // Initialize karaoke app based on selected audio source
    final acrcloudHost = dotenv.env['ACRCLOUD_HOST'] ?? '';
    final acrcloudAccessKey = dotenv.env['ACRCLOUD_ACCESS_KEY'] ?? '';
    final acrcloudSecret = dotenv.env['ACRCLOUD_ACCESS_SECRET'] ?? '';

    if (acrcloudHost.isEmpty ||
        acrcloudAccessKey.isEmpty ||
        acrcloudSecret.isEmpty) {
      _showError('ACRCloud credentials not configured in .env file');
      return;
    }

    // Request microphone permission if using phone
    if (_selectedAudioSource == AudioSource.phone) {
      await _requestMicrophonePermission();
    }

    try {
      _karaokeApp = KaraokeApp(
        // frame: _isConnected ? _frame : null, // TODO: Re-enable
        acrcloudHost: acrcloudHost,
        acrcloudAccessKey: acrcloudAccessKey,
        acrcloudSecretKey: acrcloudSecret,
        audioSource: _selectedAudioSource,
        onDisplayUpdate: (text) {
          setState(() {
            _lyricsDisplay = text;
          });
        },
      );

      // Start karaoke app
      await _karaokeApp!.start();

      // If using Frame, start audio capture
      if (_selectedAudioSource == AudioSource.frame && _isConnected) {
        _startFrameAudioCapture();
      }

      setState(() {
        _isRunning = true;
        _statusMessage = _selectedAudioSource == AudioSource.frame
            ? 'Karaoke running - using Frame microphone'
            : 'Karaoke running - using phone microphone';
      });
    } catch (e) {
      _showError('Start error: $e');
    }
  }

  void _startFrameAudioCapture() {
    // TODO: Re-enable when Frame SDK is fixed
    print('Frame audio capture disabled');
    // Timer.periodic(const Duration(seconds: 2), (timer) async {
    //   if (!_isRunning || _karaokeApp == null) {
    //     timer.cancel();
    //     return;
    //   }
    //   try {
    //     final audioData = await _frame.microphone.recordAudio();
    //     _karaokeApp!.addAudioChunk(audioData);
    //   } catch (e) {
    //     print('Frame audio capture error: $e');
    //   }
    // });
  }

  Future<void> _stopKaraoke() async {
    if (_karaokeApp != null) {
      await _karaokeApp!.stop();
      _karaokeApp!.dispose();
      _karaokeApp = null;
    }

    setState(() {
      _isRunning = false;
      _lyricsDisplay = '';
      _statusMessage = 'Karaoke stopped';
    });
  }

  void _showError(String message) {
    setState(() {
      _statusMessage = 'Error: $message';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('♪ Frame Karaoke'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Audio Source Selection
              if (!_isRunning) ...[
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Audio Source',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        RadioListTile<AudioSource>(
                          title: const Text('📱 Phone Microphone (Test Mode)'),
                          subtitle: const Text(
                              'Use phone\'s built-in mic - no Frame needed'),
                          value: AudioSource.phone,
                          groupValue: _selectedAudioSource,
                          onChanged: (value) {
                            setState(() {
                              _selectedAudioSource = value!;
                            });
                          },
                        ),
                        RadioListTile<AudioSource>(
                          title: const Text('🥽 Frame Glasses Microphone'),
                          subtitle: const Text('Use Frame glasses mic (connect first)'),
                          value: AudioSource.frame,
                          groupValue: _selectedAudioSource,
                          onChanged: (value) {
                            setState(() {
                              _selectedAudioSource = value!;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Status card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Status',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(_statusMessage),
                      if (_isConnected && _batteryLevel != null) ...[
                        const SizedBox(height: 8),
                        Text('Frame Battery: $_batteryLevel%'),
                      ],
                      if (_isRunning && _karaokeApp != null) ...[
                        const SizedBox(height: 8),
                        Text(_karaokeApp!.currentStateString),
                        const SizedBox(height: 8),
                        Text(
                          'Audio: ${_selectedAudioSource == AudioSource.frame ? "Frame Mic" : "Phone Mic"}',
                          style: TextStyle(
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Lyrics Preview
              if (_isRunning)
                Card(
                  color: Colors.black87,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 200),
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lyrics Preview',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: Colors.white,
                              ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _lyricsDisplay.isEmpty ? '♪ Listening...' : _lyricsDisplay,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 24),

              // Controls
              if (!_isConnected &&
                  _selectedAudioSource == AudioSource.frame &&
                  !_isRunning)
                ElevatedButton.icon(
                  onPressed: _connectToFrame,
                  icon: const Icon(Icons.bluetooth),
                  label: const Text('Connect to Frame'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                ),

              if (!_isRunning &&
                  (_selectedAudioSource == AudioSource.phone || _isConnected))
                ElevatedButton.icon(
                  onPressed: _startKaraoke,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(_selectedAudioSource == AudioSource.phone
                      ? 'Start Test Mode'
                      : 'Start Karaoke'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),

              if (_isRunning)
                ElevatedButton.icon(
                  onPressed: _stopKaraoke,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),

              const SizedBox(height: 24),

              // Info
              Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '💡 How to use:',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      if (_selectedAudioSource == AudioSource.phone) ...[
                        const Text('📱 Test Mode (Phone Microphone):'),
                        const SizedBox(height: 4),
                        const Text('1. Tap "Start Test Mode"'),
                        const Text('2. Play music near your phone'),
                        const Text('3. Watch lyrics appear in the app!'),
                        const Text('4. No Frame glasses needed for testing'),
                      ] else ...[
                        const Text('🥽 Frame Mode:'),
                        const SizedBox(height: 4),
                        const Text('1. Connect your Frame glasses'),
                        const Text('2. Tap "Start Karaoke"'),
                        const Text('3. Play music around you'),
                        const Text('4. Lyrics appear on Frame & in app!'),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
