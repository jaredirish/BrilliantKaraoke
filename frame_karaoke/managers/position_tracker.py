"""Song position tracking with drift correction."""

import time
import logging
import math
from typing import List, Optional

from ..models import RecognitionPoint

logger = logging.getLogger(__name__)


class PositionTracker:
    """
    Tracks song position with continuous drift correction.

    Maintains an accurate estimate of the current position in the song
    by tracking recognition points and calculating drift over time.
    """

    def __init__(self):
        """Initialize position tracker."""
        self.song_start_time: Optional[float] = None
        self.detected_offset: float = 0.0
        self.recognition_history: List[RecognitionPoint] = []
        self.estimated_drift: float = 0.0
        self.max_drift_seconds: float = 3.0
        self.history_size: int = 5

    def start_song(
        self,
        detected_at: float,
        song_offset: float,
        api_latency: float = 0.0
    ):
        """
        Initialize tracking for a new song.

        Args:
            detected_at: Timestamp when song was detected
            song_offset: Position in song when detected (seconds)
            api_latency: API call latency (milliseconds)
        """
        # Account for API latency (half before, half after)
        api_latency_seconds = api_latency / 1000.0
        self.song_start_time = detected_at - song_offset - (api_latency_seconds / 2)
        self.detected_offset = song_offset
        self.estimated_drift = 0.0

        self.recognition_history = [RecognitionPoint(
            timestamp=detected_at,
            detected_offset=song_offset,
            confidence=1.0,
            api_latency=api_latency,
            drift=0.0
        )]

        logger.info(
            f"Started tracking song at offset {song_offset:.1f}s "
            f"(API latency: {api_latency:.0f}ms)"
        )

    def get_current_position(self) -> float:
        """
        Get current position in song.

        Returns:
            Current position in seconds (0 if not tracking)
        """
        if self.song_start_time is None:
            return 0.0

        elapsed = time.time() - self.song_start_time
        position = elapsed - self.estimated_drift

        return max(0.0, position)

    def validate_position(
        self,
        new_offset: float,
        detection_time: float,
        confidence: float = 1.0,
        api_latency: float = 0.0
    ) -> bool:
        """
        Validate if new detected position is consistent with current tracking.

        Args:
            new_offset: Newly detected position in song
            detection_time: Timestamp of detection
            confidence: Recognition confidence (0-1)
            api_latency: API call latency (milliseconds)

        Returns:
            True if position is valid (drift within threshold)
        """
        current_position = self.get_current_position()
        drift = abs(current_position - new_offset)

        is_valid = drift <= self.max_drift_seconds

        if not is_valid:
            logger.warning(
                f"Position drift detected: {drift:.1f}s "
                f"(expected: {current_position:.1f}s, detected: {new_offset:.1f}s)"
            )

        return is_valid

    def recalibrate(
        self,
        new_offset: float,
        detection_time: float,
        confidence: float = 1.0,
        api_latency: float = 0.0
    ):
        """
        Update position tracking with new recognition point.

        Adjusts estimated drift or fully recalibrates if drift is too large.

        Args:
            new_offset: Newly detected position in song
            detection_time: Timestamp of detection
            confidence: Recognition confidence (0-1)
            api_latency: API call latency (milliseconds)
        """
        if self.song_start_time is None:
            self.start_song(detection_time, new_offset, api_latency)
            return

        # Add to history
        api_latency_seconds = api_latency / 1000.0
        expected_position = (detection_time - self.song_start_time)
        actual_position = new_offset + (api_latency_seconds / 2)
        drift = expected_position - actual_position

        self.recognition_history.append(RecognitionPoint(
            timestamp=detection_time,
            detected_offset=new_offset,
            confidence=confidence,
            api_latency=api_latency,
            drift=drift
        ))

        # Trim history
        if len(self.recognition_history) > self.history_size:
            self.recognition_history = self.recognition_history[-self.history_size:]

        # Calculate weighted drift
        weighted_drifts = []
        for i, point in enumerate(self.recognition_history):
            expected = (point.timestamp - self.song_start_time)
            actual = point.detected_offset + (point.api_latency / 2000.0)
            drift = expected - actual

            # Weight recent points more heavily
            weight = point.confidence * (i + 1) / len(self.recognition_history)
            weighted_drifts.append({'drift': drift, 'weight': weight})

        total_weight = sum(d['weight'] for d in weighted_drifts)
        if total_weight > 0:
            self.estimated_drift = sum(
                d['drift'] * d['weight'] for d in weighted_drifts
            ) / total_weight

        # Check if we need full recalibration
        current_position = self.get_current_position()
        current_drift = abs(current_position - new_offset)

        if current_drift > self.max_drift_seconds:
            logger.warning(
                f"Large drift detected ({current_drift:.1f}s), "
                "performing full recalibration"
            )
            # Full recalibration
            self.song_start_time = (
                detection_time - new_offset - (api_latency_seconds / 2)
            )
            self.estimated_drift = 0.0

        logger.debug(
            f"Position updated: {self.get_current_position():.1f}s "
            f"(drift: {self.estimated_drift:.2f}s)"
        )

    def get_confidence(self) -> float:
        """
        Calculate confidence in current position tracking.

        Factors in recognition confidence and drift variance.

        Returns:
            Confidence score (0-1)
        """
        if not self.recognition_history:
            return 0.0

        # Average confidence of recent points
        recent_points = self.recognition_history[-3:]
        avg_confidence = sum(p.confidence for p in recent_points) / len(recent_points)

        # Calculate drift variance
        drift_variance = self._calculate_drift_variance()

        # Penalize based on drift variance
        drift_penalty = min(1.0, drift_variance / self.max_drift_seconds)

        return avg_confidence * (1.0 - drift_penalty * 0.5)

    def _calculate_drift_variance(self) -> float:
        """
        Calculate standard deviation of drift values.

        Returns:
            Drift variance
        """
        if len(self.recognition_history) < 2:
            return 0.0

        if self.song_start_time is None:
            return 0.0

        # Calculate drift for each point
        drifts = []
        for point in self.recognition_history:
            expected = (point.timestamp - self.song_start_time)
            actual = point.detected_offset
            drift = expected - actual
            drifts.append(drift)

        # Calculate mean
        avg_drift = sum(drifts) / len(drifts)

        # Calculate variance
        variance = sum((d - avg_drift) ** 2 for d in drifts) / len(drifts)

        # Return standard deviation
        return math.sqrt(variance)

    def reset(self):
        """Reset position tracking."""
        self.song_start_time = None
        self.detected_offset = 0.0
        self.recognition_history = []
        self.estimated_drift = 0.0
        logger.debug("Position tracker reset")

    def is_active(self) -> bool:
        """
        Check if position tracking is active.

        Returns:
            True if currently tracking a song
        """
        return self.song_start_time is not None
