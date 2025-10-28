"""Song history tracking manager."""

import json
import time
import logging
from typing import List, Optional, Dict
from collections import Counter

from ..models import CurrentSong, SongHistoryEntry

logger = logging.getLogger(__name__)


class HistoryManager:
    """
    Manages song history and statistics.

    Tracks all identified songs and provides duplicate detection,
    statistics, and import/export functionality.
    """

    def __init__(self, max_history_size: int = 100):
        """
        Initialize history manager.

        Args:
            max_history_size: Maximum number of songs to keep in history
        """
        self.history: List[SongHistoryEntry] = []
        self.max_history_size = max_history_size
        self.duplicate_window_seconds = 30.0  # 30 seconds

    def add_song(self, song: CurrentSong):
        """
        Add song to history if not a duplicate.

        Args:
            song: Song to add to history
        """
        if self.is_duplicate(song):
            logger.debug(f"Skipping duplicate song: '{song.title}' by '{song.artist}'")
            return

        entry = SongHistoryEntry(
            title=song.title,
            artist=song.artist,
            album=song.album,
            identified_at=time.time(),
            duration=song.duration,
            confidence=song.confidence
        )

        # Add to front of list (most recent first)
        self.history.insert(0, entry)

        # Trim to max size
        if len(self.history) > self.max_history_size:
            self.history = self.history[:self.max_history_size]

        logger.info(f"Added to history: '{entry.title}' by '{entry.artist}'")

    def get_recent_songs(self, limit: Optional[int] = None) -> List[SongHistoryEntry]:
        """
        Get recent songs from history.

        Args:
            limit: Maximum number of songs to return (None = all)

        Returns:
            List of recent song entries
        """
        if limit is None:
            return self.history.copy()
        return self.history[:limit]

    def is_duplicate(self, song: CurrentSong) -> bool:
        """
        Check if song was recently added to history.

        Args:
            song: Song to check

        Returns:
            True if duplicate within time window, False otherwise
        """
        now = time.time()
        recent_cutoff = now - self.duplicate_window_seconds

        return any(
            entry.title == song.title and
            entry.artist == song.artist and
            entry.identified_at > recent_cutoff
            for entry in self.history
        )

    def clear_history(self):
        """Clear all history."""
        self.history = []
        logger.info("History cleared")

    def export_history(self) -> str:
        """
        Export history as JSON string.

        Returns:
            JSON representation of history
        """
        # Convert dataclasses to dicts for JSON serialization
        history_dicts = [
            {
                'title': entry.title,
                'artist': entry.artist,
                'album': entry.album,
                'identified_at': entry.identified_at,
                'duration': entry.duration,
                'confidence': entry.confidence
            }
            for entry in self.history
        ]
        return json.dumps(history_dicts, indent=2)

    def import_history(self, json_data: str) -> bool:
        """
        Import history from JSON string.

        Args:
            json_data: JSON string to import

        Returns:
            True if successful, False otherwise
        """
        try:
            imported = json.loads(json_data)

            if not isinstance(imported, list):
                logger.error("Invalid history format: not a list")
                return False

            # Validate and convert to SongHistoryEntry objects
            validated_entries = []
            for entry_dict in imported:
                if (isinstance(entry_dict, dict) and
                    'title' in entry_dict and
                    'artist' in entry_dict and
                    'identified_at' in entry_dict and
                    isinstance(entry_dict['identified_at'], (int, float))):

                    validated_entries.append(SongHistoryEntry(
                        title=entry_dict['title'],
                        artist=entry_dict['artist'],
                        album=entry_dict.get('album'),
                        identified_at=entry_dict['identified_at'],
                        duration=entry_dict.get('duration'),
                        confidence=entry_dict.get('confidence', 0.0)
                    ))

            # Trim to max size
            self.history = validated_entries[:self.max_history_size]
            logger.info(f"Imported {len(self.history)} songs")
            return True

        except json.JSONDecodeError as e:
            logger.error(f"Error importing history: {e}")
            return False
        except Exception as e:
            logger.error(f"Unexpected error importing history: {e}")
            return False

    def get_history_size(self) -> int:
        """Get current history size."""
        return len(self.history)

    def find_song(self, title: str, artist: str) -> Optional[SongHistoryEntry]:
        """
        Find a specific song in history.

        Args:
            title: Song title (case-insensitive)
            artist: Artist name (case-insensitive)

        Returns:
            Song entry if found, None otherwise
        """
        title_lower = title.lower()
        artist_lower = artist.lower()

        for entry in self.history:
            if (entry.title.lower() == title_lower and
                entry.artist.lower() == artist_lower):
                return entry

        return None

    def get_statistics(self) -> Dict[str, any]:
        """
        Calculate statistics from history.

        Returns:
            Dictionary with statistics:
            - total_songs: Total number of entries
            - unique_songs: Number of unique song/artist combinations
            - avg_confidence: Average confidence score
            - most_played_song: Most frequently played song
        """
        total_songs = len(self.history)

        if total_songs == 0:
            return {
                'total_songs': 0,
                'unique_songs': 0,
                'avg_confidence': 0.0,
                'most_played_song': None
            }

        # Count unique songs
        song_keys = [f"{entry.artist} - {entry.title}" for entry in self.history]
        unique_songs = len(set(song_keys))

        # Calculate average confidence
        total_confidence = sum(entry.confidence for entry in self.history)
        avg_confidence = total_confidence / total_songs

        # Find most played song
        counter = Counter(song_keys)
        most_common = counter.most_common(1)
        most_played_song = {
            'song': most_common[0][0],
            'count': most_common[0][1]
        } if most_common else None

        return {
            'total_songs': total_songs,
            'unique_songs': unique_songs,
            'avg_confidence': avg_confidence,
            'most_played_song': most_played_song
        }
