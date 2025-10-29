import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:frame_sdk/frame_sdk.dart';
import 'package:frame_sdk/bluetooth.dart';
import 'dart:typed_data';
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
  final Frame _frame = Frame();
  KaraokeApp? _karaokeApp;

  bool _isConnected = false;
  bool _isRunning = false;
  String _statusMessage = 'Not connected to Frame';
  int? _batteryLevel;

  StreamSubscription? _audioSubscription;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  @override
  void dispose() {
    _audioSubscription?.cancel();
    _karaokeApp?.stop();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    try {
      await BrilliantBluetooth.requestPermission();
    } catch (e) {
      _showError('Permission error: $e');
    }
  }

  Future<void> _connectToFrame() async {
    setState(() {
      _statusMessage = 'Connecting to Frame...';
    });

    try {
      final connected = await _frame.connect();

      if (!connected) {
        _showError('Failed to connect to Frame');
        return;
      }

      setState(() {
        _isConnected = true;
        _statusMessage = 'Connected to Frame';
      });

      // Get battery level
      _batteryLevel = await _frame.getBatteryLevel();

      // Initialize karaoke app
      _initializeKaraokeApp();
    } catch (e) {
      _showError('Connection error: $e');
    }
  }

  void _initializeKaraokeApp() {
    final acrcloudHost = dotenv.env['ACRCLOUD_HOST'] ?? '';
    final acrcloudAccessKey = dotenv.env['ACRCLOUD_ACCESS_KEY'] ?? '';
    final acrcloudSecret = dotenv.env['ACRCLOUD_ACCESS_SECRET'] ?? '';

    if (acrcloudHost.isEmpty ||
        acrcloudAccessKey.isEmpty ||
        acrcloudSecret.isEmpty) {
      _showError('ACRCloud credentials not configured in .env file');
      return;
    }

    _karaokeApp = KaraokeApp(
      frame: _frame,
      acrcloudHost: acrcloudHost,
      acrcloudAccessKey: acrcloudAccessKey,
      acrcloudSecretKey: acrcloudSecret,
    );

    setState(() {
      _statusMessage = 'Ready to start karaoke';
    });
  }

  Future<void> _startKaraoke() async {
    if (_karaokeApp == null) {
      _showError('Karaoke app not initialized');
      return;
    }

    try {
      // Start karaoke app
      await _karaokeApp!.start();

      // Start audio capture from Frame
      _startAudioCapture();

      setState(() {
        _isRunning = true;
        _statusMessage = 'Karaoke running - listening for music';
      });
    } catch (e) {
      _showError('Start error: $e');
    }
  }

  void _startAudioCapture() {
    // Record audio in 2-second chunks continuously
    Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!_isRunning || _karaokeApp == null) {
        timer.cancel();
        return;
      }

      try {
        final audioData = await _frame.microphone.recordAudio(
          maxLengthInSeconds: 2,
        );

        if (audioData != null) {
          _karaokeApp!.addAudioChunk(audioData);
        }
      } catch (e) {
        print('Audio capture error: $e');
      }
    });
  }

  Future<void> _stopKaraoke() async {
    if (_karaokeApp != null) {
      await _karaokeApp!.stop();
    }

    setState(() {
      _isRunning = false;
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
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                      Text('Battery: $_batteryLevel%'),
                    ],
                    if (_isRunning && _karaokeApp != null) ...[
                      const SizedBox(height: 8),
                      Text(_karaokeApp!.currentStateString),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Controls
            if (!_isConnected)
              ElevatedButton.icon(
                onPressed: _connectToFrame,
                icon: const Icon(Icons.bluetooth),
                label: const Text('Connect to Frame'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),

            if (_isConnected && !_isRunning)
              ElevatedButton.icon(
                onPressed: _startKaraoke,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start Karaoke'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),

            if (_isRunning)
              ElevatedButton.icon(
                onPressed: _stopKaraoke,
                icon: const Icon(Icons.stop),
                label: const Text('Stop Karaoke'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
              ),

            const Spacer(),

            // Info
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How it works:',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text('1. Connect your Frame glasses'),
                    const Text('2. Start karaoke mode'),
                    const Text('3. Play any music around you'),
                    const Text('4. Watch lyrics appear on Frame!'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
