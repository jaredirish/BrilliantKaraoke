"""Display formatting manager for Frame glasses."""

import logging
from typing import Optional, List

from ..models import CurrentSong, LyricsChunk, AppState
from ..utils.lrc_parser import format_timestamp

logger = logging.getLogger(__name__)


class DisplayManager:
    """
    Manages display formatting for Frame glasses.

    Formats lyrics, song info, and status messages for display
    on Frame's 640x400 pixel display.
    """

    def __init__(self):
        """Initialize display manager."""
        self.last_update_time: float = 0
        self.update_interval: float = 0.5  # Update every 500ms

    def format_display(
        self,
        app_state: AppState,
        current_song: Optional[CurrentSong] = None,
        current_chunk: Optional[LyricsChunk] = None,
        next_chunk: Optional[LyricsChunk] = None,
        current_position: float = 0.0
    ) -> str:
        """
        Format display text based on current state.

        Args:
            app_state: Current application state
            current_song: Currently playing song
            current_chunk: Current lyrics chunk
            next_chunk: Next lyrics chunk (for preview)
            current_position: Current position in song (seconds)

        Returns:
            Formatted text string for display
        """
        if app_state == AppState.LISTENING:
            return self._format_listening()

        elif app_state == AppState.PROCESSING:
            return self._format_processing()

        elif app_state == AppState.SONG_DETECTED_NO_LYRICS:
            if current_song:
                return self._format_song_info(current_song, current_position)
            return self._format_listening()

        elif app_state == AppState.SONG_DETECTED_WITH_LYRICS:
            if current_song:
                return self._format_lyrics_display(
                    current_song,
                    current_chunk,
                    next_chunk,
                    current_position
                )
            return self._format_listening()

        return self._format_listening()

    def _format_listening(self) -> str:
        """Format listening state display."""
        return "♪ Listening..."

    def _format_processing(self) -> str:
        """Format processing state display."""
        return "Processing...\nFetching lyrics..."

    def _format_song_info(self, song: CurrentSong, position: float) -> str:
        """
        Format song info without lyrics.

        Args:
            song: Current song
            position: Current position in song

        Returns:
            Formatted song info
        """
        lines = [
            f"♪ {song.title}",
            f"  {song.artist}"
        ]

        if song.album:
            lines.append(f"  {song.album}")

        lines.append("")  # Empty line for spacing

        # Add timestamp
        time_str = f"  {format_timestamp(position)} / {format_timestamp(song.duration)}"
        lines.append(time_str)

        return "\n".join(lines)

    def _format_lyrics_display(
        self,
        song: CurrentSong,
        current_chunk: Optional[LyricsChunk],
        next_chunk: Optional[LyricsChunk],
        position: float
    ) -> str:
        """
        Format lyrics display with current and next chunks.

        Args:
            song: Current song
            current_chunk: Current lyrics chunk
            next_chunk: Next lyrics chunk
            position: Current position in song

        Returns:
            Formatted lyrics display
        """
        if not current_chunk:
            # No current chunk, show song info
            return self._format_song_info(song, position)

        lines = []

        # Show current lyrics lines
        for line in current_chunk.lines:
            lines.append(line)

        # Add separator before preview
        if next_chunk:
            lines.append("-----")

            # Show preview of next chunk (first line only)
            if next_chunk.lines:
                preview = next_chunk.lines[0]
                # Truncate if too long
                if len(preview) > 45:
                    preview = preview[:42] + "..."
                lines.append(preview)

        # Add timestamp at bottom
        time_str = f"{format_timestamp(position)} / {format_timestamp(song.duration)}"
        lines.append("")  # Empty line for spacing
        lines.append(time_str)

        return "\n".join(lines)

    def _format_instrumental(self, song: CurrentSong, position: float) -> str:
        """
        Format display for instrumental breaks.

        Args:
            song: Current song
            position: Current position in song

        Returns:
            Formatted instrumental display
        """
        lines = [
            f"♪ {song.title}",
            f"  {song.artist}",
            "",
            "  ♪ Instrumental ♪",
            f"  {format_timestamp(position)} / {format_timestamp(song.duration)}"
        ]
        return "\n".join(lines)

    def format_error(self, error_message: str) -> str:
        """
        Format error message for display.

        Args:
            error_message: Error message to display

        Returns:
            Formatted error display
        """
        return f"Error:\n{error_message}"

    def format_welcome(self) -> str:
        """Format welcome message."""
        return "♪ Frame Karaoke\n\nPlay some music to\nget started!"

    def should_update(self, current_time: float) -> bool:
        """
        Check if enough time has passed for display update.

        Args:
            current_time: Current timestamp

        Returns:
            True if display should be updated
        """
        elapsed = current_time - self.last_update_time
        if elapsed >= self.update_interval:
            self.last_update_time = current_time
            return True
        return False
