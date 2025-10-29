import 'dart:math';
import '../models/app_models.dart';

/// Song position tracking with drift correction
class PositionTracker {
  DateTime? _songStartTime;
  double _detectedOffset = 0.0;
  final List<RecognitionPoint> _recognitionHistory = [];
  double _estimatedDrift = 0.0;

  final double maxDriftSeconds;
  final int historySize;

  PositionTracker({
    this.maxDriftSeconds = 3.0,
    this.historySize = 5,
  });

  /// Initialize tracking for a new song
  void startSong(
    DateTime detectedAt,
    double songOffset,
    double apiLatency,
  ) {
    // Account for API latency (half before, half after)
    final apiLatencySeconds = apiLatency / 1000.0;
    _songStartTime = detectedAt.subtract(
      Duration(milliseconds: ((songOffset + apiLatencySeconds / 2) * 1000).round()),
    );
    _detectedOffset = songOffset;
    _estimatedDrift = 0.0;

    _recognitionHistory.clear();
    _recognitionHistory.add(RecognitionPoint(
      timestamp: detectedAt,
      detectedOffset: songOffset,
      confidence: 1.0,
      apiLatency: apiLatency,
      drift: 0.0,
    ));
  }

  /// Get current position in song
  double getCurrentPosition() {
    if (_songStartTime == null) {
      return 0.0;
    }

    final elapsed = DateTime.now().difference(_songStartTime!).inMilliseconds / 1000.0;
    final position = elapsed - _estimatedDrift;

    return max(0.0, position);
  }

  /// Validate if new detected position is consistent with current tracking
  bool validatePosition(
    double newOffset,
    DateTime detectionTime,
    double confidence,
    double apiLatency,
  ) {
    final currentPosition = getCurrentPosition();
    final drift = (currentPosition - newOffset).abs();

    return drift <= maxDriftSeconds;
  }

  /// Update position tracking with new recognition point
  void recalibrate(
    double newOffset,
    DateTime detectionTime,
    double confidence,
    double apiLatency,
  ) {
    if (_songStartTime == null) {
      startSong(detectionTime, newOffset, apiLatency);
      return;
    }

    // Add to history
    final apiLatencySeconds = apiLatency / 1000.0;
    final expected = detectionTime.difference(_songStartTime!).inMilliseconds / 1000.0;
    final actual = newOffset + (apiLatencySeconds / 2);
    final drift = expected - actual;

    _recognitionHistory.add(RecognitionPoint(
      timestamp: detectionTime,
      detectedOffset: newOffset,
      confidence: confidence,
      apiLatency: apiLatency,
      drift: drift,
    ));

    // Trim history
    if (_recognitionHistory.length > historySize) {
      _recognitionHistory.removeAt(0);
    }

    // Calculate weighted drift
    var totalWeight = 0.0;
    var weightedDriftSum = 0.0;

    for (var i = 0; i < _recognitionHistory.length; i++) {
      final point = _recognitionHistory[i];
      final expected = point.timestamp.difference(_songStartTime!).inMilliseconds / 1000.0;
      final actual = point.detectedOffset + (point.apiLatency / 2000.0);
      final drift = expected - actual;

      // Weight recent points more heavily
      final weight = point.confidence * (i + 1) / _recognitionHistory.length;
      weightedDriftSum += drift * weight;
      totalWeight += weight;
    }

    if (totalWeight > 0) {
      _estimatedDrift = weightedDriftSum / totalWeight;
    }

    // Check if we need full recalibration
    final currentPosition = getCurrentPosition();
    final currentDrift = (currentPosition - newOffset).abs();

    if (currentDrift > maxDriftSeconds) {
      // Full recalibration
      _songStartTime = detectionTime.subtract(
        Duration(milliseconds: ((newOffset + apiLatencySeconds / 2) * 1000).round()),
      );
      _estimatedDrift = 0.0;
    }
  }

  /// Calculate confidence in current position tracking
  double getConfidence() {
    if (_recognitionHistory.isEmpty) {
      return 0.0;
    }

    // Average confidence of recent points
    final recentPoints = _recognitionHistory.length <= 3
        ? _recognitionHistory
        : _recognitionHistory.sublist(_recognitionHistory.length - 3);

    final avgConfidence =
        recentPoints.fold<double>(0.0, (sum, p) => sum + p.confidence) / recentPoints.length;

    // Calculate drift variance
    final driftVariance = _calculateDriftVariance();

    // Penalize based on drift variance
    final driftPenalty = min(1.0, driftVariance / maxDriftSeconds);

    return avgConfidence * (1.0 - driftPenalty * 0.5);
  }

  /// Calculate standard deviation of drift values
  double _calculateDriftVariance() {
    if (_recognitionHistory.length < 2 || _songStartTime == null) {
      return 0.0;
    }

    // Calculate drift for each point
    final drifts = <double>[];
    for (final point in _recognitionHistory) {
      final expected = point.timestamp.difference(_songStartTime!).inMilliseconds / 1000.0;
      final actual = point.detectedOffset;
      final drift = expected - actual;
      drifts.add(drift);
    }

    // Calculate mean
    final avgDrift = drifts.fold<double>(0.0, (sum, d) => sum + d) / drifts.length;

    // Calculate variance
    final variance =
        drifts.fold<double>(0.0, (sum, d) => sum + pow(d - avgDrift, 2)) / drifts.length;

    // Return standard deviation
    return sqrt(variance);
  }

  /// Reset position tracking
  void reset() {
    _songStartTime = null;
    _detectedOffset = 0.0;
    _recognitionHistory.clear();
    _estimatedDrift = 0.0;
  }

  /// Check if position tracking is active
  bool get isActive => _songStartTime != null;
}
