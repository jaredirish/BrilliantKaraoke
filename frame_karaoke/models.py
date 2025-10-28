"""Data models for Frame Karaoke application."""

from dataclasses import dataclass, field
from enum import Enum
from typing import Optional, List


class AppState(Enum):
    """Application state."""
    LISTENING = "listening"
    PROCESSING = "processing"
    SONG_DETECTED_NO_LYRICS = "song_no_lyrics"
    SONG_DETECTED_WITH_LYRICS = "song_with_lyrics"


class RecognitionState(Enum):
    """Recognition state machine states."""
    LISTENING = "listening"
    SONG_DETECTED_PENDING = "song_detected_pending"
    SONG_DETECTED_CONFIRMED = "song_detected_confirmed"
    SONG_PLAYING = "song_playing"
    SONG_SWITCH_PENDING = "song_switch_pending"
    SONG_ENDING = "song_ending"


@dataclass
class CurrentSong:
    """Currently playing song information."""
    title: str
    artist: str
    album: Optional[str]
    duration: float  # seconds
    detected_at: float  # timestamp
    has_lyrics: bool
    confidence: float  # 0.0 to 1.0
    lrc_data: Optional[List['LRCLine']] = None


@dataclass
class LRCLine:
    """A single line from an LRC file."""
    timestamp: float  # seconds
    text: str
    end_time: Optional[float] = None  # seconds


@dataclass
class LyricsChunk:
    """A chunk of lyrics formatted for display."""
    lines: List[str]  # Max 2 lines
    start_time: float  # seconds
    end_time: float  # seconds
    words_per_line: List[int] = field(default_factory=list)


@dataclass
class RecognitionResult:
    """Result from song recognition service."""
    title: str
    artist: str
    album: Optional[str] = None
    duration: Optional[float] = None  # seconds
    offset_seconds: Optional[float] = None  # Position in song when detected
    confidence: float = 0.0  # 0.0 to 1.0
    error: Optional[str] = None


@dataclass
class RecognitionPoint:
    """A point in time when a song was recognized."""
    timestamp: float  # When recognition occurred
    detected_offset: float  # Position in song that was detected
    confidence: float
    api_latency: float = 0.0  # How long the API call took
    drift: float = 0.0  # Difference from expected position


@dataclass
class SongHistoryEntry:
    """Entry in song history."""
    title: str
    artist: str
    album: Optional[str]
    identified_at: float  # timestamp
    duration: Optional[float] = None  # seconds
    confidence: float = 0.0
