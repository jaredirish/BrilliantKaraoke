"""Audio recognition and buffering manager."""

import time
import logging
from typing import List, Optional, Callable

from ..models import RecognitionResult
from ..services import ACRCloudService
from ..utils import (
    combine_audio_chunks,
    trim_audio_buffer,
    create_wav_buffer,
    calculate_audio_duration,
    validate_audio_data,
)

logger = logging.getLogger(__name__)


class RecognitionManager:
    """
    Manages audio buffering and song recognition.

    Maintains a rolling audio buffer and performs periodic recognition
    using ACRCloud service.
    """

    def __init__(
        self,
        acrcloud_service: ACRCloudService,
        sample_rate: int = 16000
    ):
        """
        Initialize recognition manager.

        Args:
            acrcloud_service: ACRCloud service instance
            sample_rate: Audio sample rate in Hz (default: 16000)
        """
        self.acrcloud = acrcloud_service
        self.sample_rate = sample_rate

        # Audio buffer
        self.audio_buffer: List[bytes] = []
        self.is_recording: bool = False

        # Timing
        self.last_recognition_time: float = 0.0
        self.recognition_interval: float = 12.0  # seconds between recognitions

        # Configuration
        self.max_buffer_duration: float = 8.0  # seconds
        self.min_audio_duration: float = 3.0  # minimum audio for first recognition

    def start_listening(self):
        """Start audio recording and recognition."""
        self.is_recording = True
        self.audio_buffer = []
        self.last_recognition_time = 0.0
        logger.info("Started listening for audio")

    def stop_listening(self):
        """Stop audio recording."""
        self.is_recording = False
        logger.info("Stopped listening")

    def add_audio_chunk(self, audio_data: bytes):
        """
        Add audio chunk to buffer.

        Args:
            audio_data: Raw audio data (PCM 16-bit)
        """
        if not self.is_recording:
            return

        self.audio_buffer.append(audio_data)

        # Combine and trim buffer to max duration
        combined = combine_audio_chunks(self.audio_buffer)
        trimmed = trim_audio_buffer(
            combined,
            self.max_buffer_duration,
            self.sample_rate
        )
        self.audio_buffer = [trimmed]

    def should_recognize(self) -> bool:
        """
        Check if it's time to perform recognition.

        Returns:
            True if recognition should be performed
        """
        now = time.time()

        # First recognition - wait for enough audio
        if self.last_recognition_time == 0:
            if not self.audio_buffer:
                return False

            combined = combine_audio_chunks(self.audio_buffer)
            duration = calculate_audio_duration(len(combined), self.sample_rate)
            return duration >= self.min_audio_duration

        # Subsequent recognitions - check interval
        elapsed = now - self.last_recognition_time
        return elapsed >= self.recognition_interval

    async def recognize(self) -> Optional[RecognitionResult]:
        """
        Perform song recognition on buffered audio.

        Returns:
            Recognition result or None if recognition fails
        """
        if not self.audio_buffer:
            logger.warning("No audio in buffer for recognition")
            return None

        start_time = time.time()

        # Combine audio chunks
        audio_data = combine_audio_chunks(self.audio_buffer)

        # Validate audio
        if not validate_audio_data(audio_data):
            logger.warning("Invalid audio data, skipping recognition")
            return None

        # Create WAV buffer
        wav_buffer = create_wav_buffer(audio_data, self.sample_rate)

        duration = calculate_audio_duration(len(audio_data), self.sample_rate)

        logger.info(
            f"Sending audio to ACRCloud: {len(audio_data)} bytes, "
            f"{duration:.1f}s duration"
        )

        try:
            # Send to ACRCloud
            result = await self.acrcloud.recognize(wav_buffer)
            api_latency = (time.time() - start_time) * 1000  # milliseconds

            # Update last recognition time
            self.last_recognition_time = time.time()

            if result.error:
                logger.info(f"Recognition failed: {result.error}")
                return None

            if not result.title or not result.artist:
                logger.info("No song detected")
                return None

            # Add API latency to result
            result.api_latency = api_latency

            logger.info(
                f"Recognized: '{result.title}' by '{result.artist}' "
                f"(confidence: {result.confidence:.2f}, latency: {api_latency:.0f}ms)"
            )

            return result

        except Exception as e:
            logger.error(f"Recognition error: {e}", exc_info=True)
            self.last_recognition_time = time.time()
            return None

    def reset(self):
        """Reset recognition state."""
        self.audio_buffer = []
        self.last_recognition_time = 0.0
        logger.debug("Recognition manager reset")

    def set_sample_rate(self, rate: int):
        """
        Update sample rate.

        Args:
            rate: New sample rate in Hz
        """
        self.sample_rate = rate
        logger.info(f"Sample rate set to {rate} Hz")

    def get_buffer_duration(self) -> float:
        """
        Get current buffer duration in seconds.

        Returns:
            Buffer duration
        """
        if not self.audio_buffer:
            return 0.0

        combined = combine_audio_chunks(self.audio_buffer)
        return calculate_audio_duration(len(combined), self.sample_rate)

    def set_recognition_interval(self, interval: float):
        """
        Set recognition interval.

        Args:
            interval: Interval in seconds
        """
        self.recognition_interval = interval
        logger.info(f"Recognition interval set to {interval}s")
