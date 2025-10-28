"""Main karaoke application for Frame glasses."""

import asyncio
import logging
import os
from typing import Optional
from frame_sdk import Frame
from frame_sdk.display import Alignment

from .models import AppState, CurrentSong
from .services import ACRCloudService, LRCService
from .managers import (
    RecognitionManager,
    LyricsManager,
    PositionTracker,
    DisplayManager,
    HistoryManager,
)

logger = logging.getLogger(__name__)


class KaraokeApp:
    """
    Main karaoke application.

    Coordinates audio capture, song recognition, lyrics display,
    and all other karaoke functionality for Frame glasses.
    """

    def __init__(
        self,
        acrcloud_host: str,
        acrcloud_access_key: str,
        acrcloud_secret_key: str,
        frame_address: Optional[str] = None
    ):
        """
        Initialize karaoke app.

        Args:
            acrcloud_host: ACRCloud API host
            acrcloud_access_key: ACRCloud access key
            acrcloud_secret_key: ACRCloud secret key
            frame_address: Frame pairing code (None = connect to any Frame)
        """
        self.frame_address = frame_address
        self.frame: Optional[Frame] = None

        # Services
        self.acrcloud_service = ACRCloudService(
            acrcloud_host,
            acrcloud_access_key,
            acrcloud_secret_key
        )
        self.lrc_service = LRCService()

        # Managers
        self.recognition_manager = RecognitionManager(self.acrcloud_service)
        self.lyrics_manager = LyricsManager(self.lrc_service)
        self.position_tracker = PositionTracker()
        self.display_manager = DisplayManager()
        self.history_manager = HistoryManager()

        # State
        self.current_song: Optional[CurrentSong] = None
        self.app_state: AppState = AppState.LISTENING
        self.running: bool = False

    async def start(self):
        """Start the karaoke application."""
        logger.info("Starting Frame Karaoke...")

        try:
            async with Frame(self.frame_address) as frame:
                self.frame = frame
                self.running = True

                logger.info("Connected to Frame glasses")

                # Show welcome message
                await self._update_display()

                # Start recognition
                self.recognition_manager.start_listening()

                # Run main loops concurrently
                await asyncio.gather(
                    self._audio_capture_loop(),
                    self._recognition_loop(),
                    self._display_loop(),
                )

        except KeyboardInterrupt:
            logger.info("Received interrupt signal")
        except Exception as e:
            logger.error(f"Application error: {e}", exc_info=True)
        finally:
            await self.stop()

    async def stop(self):
        """Stop the karaoke application."""
        logger.info("Stopping Frame Karaoke...")
        self.running = False
        self.recognition_manager.stop_listening()

    async def _audio_capture_loop(self):
        """Continuously capture audio from Frame microphone."""
        logger.info("Starting audio capture loop")

        while self.running:
            try:
                # Record 2-second chunks for continuous monitoring
                audio_data = await self.frame.microphone.record_audio(
                    max_length_in_seconds=2
                )

                # Add to recognition buffer
                self.recognition_manager.add_audio_chunk(audio_data)

            except Exception as e:
                logger.error(f"Audio capture error: {e}")
                await asyncio.sleep(1)  # Prevent tight error loop

    async def _recognition_loop(self):
        """Periodically perform song recognition."""
        logger.info("Starting recognition loop")

        while self.running:
            try:
                # Check if it's time to recognize
                if self.recognition_manager.should_recognize():
                    await self._perform_recognition()

                await asyncio.sleep(1)  # Check every second

            except Exception as e:
                logger.error(f"Recognition loop error: {e}")
                await asyncio.sleep(5)

    async def _display_loop(self):
        """Periodically update Frame display."""
        logger.info("Starting display loop")

        while self.running:
            try:
                await self._update_display()
                await asyncio.sleep(0.5)  # Update every 500ms

            except Exception as e:
                logger.error(f"Display loop error: {e}")
                await asyncio.sleep(1)

    async def _perform_recognition(self):
        """Perform song recognition and handle result."""
        result = await self.recognition_manager.recognize()

        if not result or result.error:
            # No song detected or error
            if self.current_song:
                # Check if song has ended
                position = self.position_tracker.get_current_position()
                if position > self.current_song.duration + 5:
                    logger.info("Song appears to have ended")
                    await self._end_song()
            return

        # Got a recognition result
        await self._handle_recognition_result(result)

    async def _handle_recognition_result(self, result):
        """
        Handle song recognition result.

        Args:
            result: RecognitionResult from ACRCloud
        """
        # Check if this is a new song or continuation
        if self.current_song is None:
            # New song detected
            await self._start_new_song(result)

        else:
            # Check if same song or different song
            if (result.title == self.current_song.title and
                result.artist == self.current_song.artist):
                # Same song - update position
                await self._update_song_position(result)
            else:
                # Different song detected
                if result.confidence > 0.75:  # High confidence for song switch
                    await self._switch_song(result)

    async def _start_new_song(self, result):
        """
        Start tracking a new song.

        Args:
            result: RecognitionResult
        """
        logger.info(f"Starting new song: '{result.title}' by '{result.artist}'")

        # Create CurrentSong
        self.current_song = CurrentSong(
            title=result.title,
            artist=result.artist,
            album=result.album,
            duration=result.duration or 180.0,  # Default 3 minutes
            detected_at=asyncio.get_event_loop().time(),
            has_lyrics=False,
            confidence=result.confidence
        )

        # Start position tracking
        if result.offset_seconds is not None:
            self.position_tracker.start_song(
                asyncio.get_event_loop().time(),
                result.offset_seconds,
                getattr(result, 'api_latency', 0)
            )

        # Add to history
        self.history_manager.add_song(self.current_song)

        # Set state to processing while we fetch lyrics
        self.app_state = AppState.PROCESSING

        # Fetch lyrics
        lrc_data = await self.lyrics_manager.fetch_lyrics(self.current_song)

        if lrc_data:
            self.current_song.has_lyrics = True
            self.current_song.lrc_data = lrc_data
            self.app_state = AppState.SONG_DETECTED_WITH_LYRICS
            logger.info(f"Lyrics loaded: {len(lrc_data)} lines")
        else:
            self.app_state = AppState.SONG_DETECTED_NO_LYRICS
            logger.info("No lyrics available")

    async def _update_song_position(self, result):
        """
        Update position tracking for current song.

        Args:
            result: RecognitionResult
        """
        if result.offset_seconds is not None:
            self.position_tracker.recalibrate(
                result.offset_seconds,
                asyncio.get_event_loop().time(),
                result.confidence,
                getattr(result, 'api_latency', 0)
            )

    async def _switch_song(self, result):
        """
        Switch to a different song.

        Args:
            result: RecognitionResult for new song
        """
        logger.info(
            f"Switching song: '{self.current_song.title}' -> '{result.title}'"
        )
        await self._end_song()
        await self._start_new_song(result)

    async def _end_song(self):
        """End current song tracking."""
        if self.current_song:
            logger.info(f"Ending song: '{self.current_song.title}'")

        self.current_song = None
        self.app_state = AppState.LISTENING
        self.position_tracker.reset()

    async def _update_display(self):
        """Update Frame display with current state."""
        if not self.frame:
            return

        # Get current position
        position = self.position_tracker.get_current_position()

        # Get current and next lyrics chunks
        current_chunk = None
        next_chunk = None

        if self.current_song and self.current_song.has_lyrics:
            current_chunk = self.lyrics_manager.get_current_chunk(position)
            next_chunk = self.lyrics_manager.get_next_chunk(position)

        # Format display
        display_text = self.display_manager.format_display(
            self.app_state,
            self.current_song,
            current_chunk,
            next_chunk,
            position
        )

        # Send to Frame
        try:
            await self.frame.display.show_text(
                display_text,
                align=Alignment.TOP_LEFT
            )
        except Exception as e:
            logger.error(f"Display update error: {e}")
