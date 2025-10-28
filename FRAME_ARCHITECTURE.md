# Frame Karaoke App - Python Architecture

## Overview

Port of the MentraOS karaoke app to Brilliant Labs Frame using Python SDK. This app runs as a **Python host application** on a computer that communicates with Frame glasses via Bluetooth.

## Key Architectural Differences from MentraOS Version

| Aspect | MentraOS (TypeScript) | Frame (Python) |
|--------|----------------------|----------------|
| **Runtime** | Bun/Node.js server | Python 3.7+ desktop app |
| **Communication** | WebSocket server | Direct Bluetooth via SDK |
| **Audio Streaming** | Continuous callback chunks | Polling with `record_audio()` |
| **Multi-user** | Multiple sessions via WebSocket | Single user per app instance |
| **Display** | Text-only, 5 lines, ~45 chars | 640x400 pixels, text rendering |
| **Language** | TypeScript | Python with async/await |

## Architecture Pattern

We maintain the **same manager pattern** from the TypeScript version, translating each component to Python:

```
KaraokeApp (main application)
├─ Frame SDK connection management
├─ Audio capture loop
└─ Coordinates all managers

Managers (same responsibilities as TypeScript version):
├─ RecognitionManager - Audio buffering & ACRCloud recognition
├─ LyricsManager - LRC fetching, parsing, chunking
├─ PositionTracker - Song position tracking with drift correction
├─ DisplayManager - Frame display formatting and updates
└─ HistoryManager - Song history tracking
```

## Core Classes

### 1. KaraokeApp (Main Application)

```python
class KaraokeApp:
    """Main application coordinating Frame and all managers."""

    def __init__(self, frame_address: Optional[str] = None):
        self.frame_address = frame_address
        self.frame: Optional[Frame] = None

        # Managers
        self.recognition_manager: RecognitionManager
        self.lyrics_manager: LyricsManager
        self.position_tracker: PositionTracker
        self.display_manager: DisplayManager
        self.history_manager: HistoryManager

        # State
        self.current_song: Optional[CurrentSong] = None
        self.app_state: AppState = AppState.LISTENING
        self.running: bool = False

    async def start(self):
        """Connect to Frame and start the karaoke loop."""
        async with Frame(self.frame_address) as frame:
            self.frame = frame
            await self._initialize_managers()
            await self._run_karaoke_loop()

    async def _run_karaoke_loop(self):
        """Main loop: capture audio, recognize, display."""
        while self.running:
            # 1. Capture audio chunk
            await self._capture_audio_chunk()

            # 2. Check if time for recognition
            if self.recognition_manager.should_recognize():
                await self._perform_recognition()

            # 3. Update display
            await self._update_display()

            # Small delay to prevent tight loop
            await asyncio.sleep(0.1)

    async def _capture_audio_chunk(self):
        """Capture audio from Frame microphone."""
        # Record short chunks (1-2 seconds) for continuous monitoring
        audio_data = await self.frame.microphone.record_audio(
            max_length_in_seconds=2
        )
        self.recognition_manager.add_audio_chunk(audio_data)

    async def _perform_recognition(self):
        """Run ACRCloud recognition on buffered audio."""
        result = await self.recognition_manager.recognize()
        if result:
            await self._handle_recognition_result(result)

    async def _update_display(self):
        """Update Frame display based on current state."""
        text = self.display_manager.get_display_text(
            self.app_state,
            self.current_song,
            self.position_tracker.get_current_position()
        )
        await self.frame.display.show_text(text, align=Alignment.TOP_LEFT)
```

### 2. RecognitionManager

```python
class RecognitionManager:
    """Manages audio buffering and ACRCloud recognition."""

    def __init__(self, acrcloud_service: ACRCloudService):
        self.acrcloud = acrcloud_service
        self.audio_buffer: List[bytes] = []
        self.last_recognition_time: float = 0
        self.recognition_interval: float = 12.0  # seconds
        self.max_buffer_duration: float = 8.0   # seconds
        self.sample_rate: int = 16000  # Default, will be updated

    def add_audio_chunk(self, audio_data: bytes):
        """Add audio chunk to rolling buffer."""
        self.audio_buffer.append(audio_data)
        self._trim_buffer()

    def should_recognize(self) -> bool:
        """Check if enough time has passed for next recognition."""
        elapsed = time.time() - self.last_recognition_time
        return elapsed >= self.recognition_interval

    async def recognize(self) -> Optional[RecognitionResult]:
        """Send buffered audio to ACRCloud for recognition."""
        if not self.audio_buffer:
            return None

        # Combine buffer chunks into single WAV
        audio_data = self._combine_audio_chunks()
        wav_data = self._create_wav(audio_data)

        # Send to ACRCloud
        result = await self.acrcloud.recognize(wav_data)
        self.last_recognition_time = time.time()

        return result

    def _trim_buffer(self):
        """Keep only last N seconds of audio."""
        # Calculate total duration and remove old chunks
        pass

    def _combine_audio_chunks(self) -> bytes:
        """Combine all buffer chunks."""
        return b''.join(self.audio_buffer)

    def _create_wav(self, pcm_data: bytes) -> bytes:
        """Create WAV file with proper headers."""
        # Similar to TypeScript version
        pass
```

### 3. LyricsManager

```python
class LyricsManager:
    """Fetches, parses, and chunks lyrics for display."""

    def __init__(self, lrc_service: LRCService):
        self.lrc_service = lrc_service
        self.lrc_cache: Dict[str, List[LRCLine]] = {}
        self.chunked_lyrics: List[LyricsChunk] = []

    async def fetch_lyrics(self, song: CurrentSong) -> Optional[List[LRCLine]]:
        """Fetch and parse LRC lyrics."""
        cache_key = f"{song.artist}-{song.title}"

        if cache_key in self.lrc_cache:
            return self.lrc_cache[cache_key]

        lrc_content = await self.lrc_service.fetch_lrc(
            song.title, song.artist
        )

        if lrc_content:
            lrc_lines = self._parse_lrc(lrc_content)
            lrc_lines = self._preprocess_lrc(lrc_lines)
            self.lrc_cache[cache_key] = lrc_lines
            self.chunked_lyrics = self._chunk_lyrics(lrc_lines)
            return lrc_lines

        return None

    def get_current_chunk(self, position: float) -> Optional[LyricsChunk]:
        """Get lyrics chunk for current song position."""
        for chunk in self.chunked_lyrics:
            if chunk.start_time <= position < chunk.end_time:
                return chunk
        return None

    def get_next_chunk(self, position: float) -> Optional[LyricsChunk]:
        """Get next chunk for preview."""
        for chunk in self.chunked_lyrics:
            if chunk.start_time > position:
                return chunk
        return None

    def _parse_lrc(self, content: str) -> List[LRCLine]:
        """Parse LRC format: [MM:SS.MS]Text"""
        # Same logic as TypeScript version
        pass

    def _preprocess_lrc(self, lines: List[LRCLine]) -> List[LRCLine]:
        """Merge short lines, split long lines."""
        # Same preprocessing logic
        pass

    def _chunk_lyrics(self, lines: List[LRCLine]) -> List[LyricsChunk]:
        """Create display-friendly chunks."""
        # Max words per line, max chars per line logic
        pass
```

### 4. PositionTracker

```python
class PositionTracker:
    """Tracks song position with drift correction."""

    def __init__(self):
        self.song_start_time: Optional[float] = None
        self.detected_offset: float = 0
        self.estimated_drift: float = 0
        self.recognition_history: List[RecognitionPoint] = []

    def start_song(self, detected_offset: float, detection_time: float):
        """Initialize tracking for new song."""
        self.song_start_time = detection_time
        self.detected_offset = detected_offset
        self.estimated_drift = 0
        self.recognition_history = []

    def get_current_position(self) -> float:
        """Calculate current position in song."""
        if not self.song_start_time:
            return 0.0

        elapsed = time.time() - self.song_start_time
        position = elapsed + self.detected_offset - self.estimated_drift
        return max(0.0, position)

    def update_position(self, detected_offset: float, detection_time: float):
        """Update position based on new recognition."""
        expected_position = self.get_current_position()
        drift = detected_offset - expected_position

        # Record recognition point
        self.recognition_history.append(RecognitionPoint(
            timestamp=detection_time,
            detected_offset=detected_offset,
            drift=drift
        ))

        # Recalibrate if drift is significant
        if abs(drift) > 3.0:
            self._recalibrate(detected_offset, detection_time)
        else:
            # Update estimated drift with exponential moving average
            self.estimated_drift = self._calculate_drift()

    def _recalibrate(self, detected_offset: float, detection_time: float):
        """Force recalibration on large drift."""
        self.song_start_time = detection_time
        self.detected_offset = detected_offset
        self.estimated_drift = 0

    def _calculate_drift(self) -> float:
        """Calculate weighted average drift from history."""
        # Weight recent recognitions more heavily
        pass
```

### 5. DisplayManager

```python
class DisplayManager:
    """Formats and manages Frame display content."""

    def __init__(self):
        self.last_display_update: float = 0
        self.update_interval: float = 0.5  # Update every 500ms

    def get_display_text(
        self,
        app_state: AppState,
        current_song: Optional[CurrentSong],
        position: float
    ) -> str:
        """Generate display text based on current state."""

        if app_state == AppState.LISTENING:
            return self._format_listening()

        elif app_state == AppState.PROCESSING:
            return self._format_processing()

        elif app_state == AppState.SONG_DETECTED_NO_LYRICS:
            return self._format_song_info(current_song, position)

        elif app_state == AppState.SONG_DETECTED_WITH_LYRICS:
            return self._format_lyrics(current_song, position)

        return "♪ Karaoke"

    def _format_listening(self) -> str:
        """Format listening state."""
        return "♪ Listening..."

    def _format_processing(self) -> str:
        """Format processing state."""
        return "♪ Processing...\nFetching lyrics..."

    def _format_song_info(self, song: CurrentSong, position: float) -> str:
        """Format song info without lyrics."""
        time_str = self._format_time(position, song.duration)
        lines = [
            f"♪ {song.title}",
            f"  {song.artist}",
        ]
        if song.album:
            lines.append(f"  {song.album}")
        lines.append("")
        lines.append(time_str)
        return "\n".join(lines)

    def _format_lyrics(self, song: CurrentSong, position: float) -> str:
        """Format lyrics with time."""
        # Get current and next chunks from LyricsManager
        # Format as:
        # Current line 1
        # Current line 2
        # -----
        # Next line preview
        # 2:34 / 5:55
        pass

    def _format_time(self, current: float, total: float) -> str:
        """Format time as MM:SS / MM:SS"""
        def fmt(seconds: float) -> str:
            mins = int(seconds // 60)
            secs = int(seconds % 60)
            return f"{mins}:{secs:02d}"

        return f"{fmt(current)} / {fmt(total)}"
```

### 6. HistoryManager

```python
class HistoryManager:
    """Tracks song history."""

    def __init__(self):
        self.history: List[SongHistoryEntry] = []
        self.max_history_size: int = 100

    def add_song(self, song: CurrentSong):
        """Add song to history if not duplicate."""
        if self._is_duplicate(song):
            return

        entry = SongHistoryEntry(
            title=song.title,
            artist=song.artist,
            album=song.album,
            identified_at=time.time(),
            duration=song.duration,
            confidence=song.confidence
        )

        self.history.append(entry)

        # Trim to max size
        if len(self.history) > self.max_history_size:
            self.history = self.history[-self.max_history_size:]

    def _is_duplicate(self, song: CurrentSong) -> bool:
        """Check if song was added recently (within 30 seconds)."""
        if not self.history:
            return False

        last_entry = self.history[-1]
        if (last_entry.title == song.title and
            last_entry.artist == song.artist and
            time.time() - last_entry.identified_at < 30):
            return True

        return False

    def get_recent_songs(self, limit: int = 10) -> List[SongHistoryEntry]:
        """Get recent songs."""
        return self.history[-limit:]
```

## Data Models

```python
from dataclasses import dataclass
from enum import Enum
from typing import Optional, List

class AppState(Enum):
    LISTENING = "listening"
    PROCESSING = "processing"
    SONG_DETECTED_NO_LYRICS = "song_no_lyrics"
    SONG_DETECTED_WITH_LYRICS = "song_with_lyrics"

@dataclass
class CurrentSong:
    title: str
    artist: str
    album: Optional[str]
    duration: float
    detected_at: float
    has_lyrics: bool
    confidence: float
    lrc_data: Optional[List['LRCLine']] = None

@dataclass
class LRCLine:
    timestamp: float
    text: str
    end_time: Optional[float] = None

@dataclass
class LyricsChunk:
    lines: List[str]
    start_time: float
    end_time: float
    words_per_line: List[int]

@dataclass
class RecognitionResult:
    title: str
    artist: str
    album: Optional[str]
    duration: Optional[float]
    offset_seconds: Optional[float]
    confidence: float

@dataclass
class RecognitionPoint:
    timestamp: float
    detected_offset: float
    drift: float

@dataclass
class SongHistoryEntry:
    title: str
    artist: str
    album: Optional[str]
    identified_at: float
    duration: Optional[float]
    confidence: float
```

## External Services

### ACRCloudService

```python
class ACRCloudService:
    """ACRCloud API wrapper."""

    def __init__(self, host: str, access_key: str, secret_key: str):
        self.host = host
        self.access_key = access_key
        self.secret_key = secret_key

    async def recognize(self, audio_data: bytes) -> Optional[RecognitionResult]:
        """Send audio to ACRCloud for recognition."""
        # Build signature
        # Create form data
        # POST to API
        # Parse response
        pass
```

### LRCService

```python
class LRCService:
    """LRC lyrics fetching service."""

    def __init__(self):
        self.lrclib_url = "https://lrclib.net"

    async def fetch_lrc(self, title: str, artist: str) -> Optional[str]:
        """Fetch LRC content from LRCLib."""
        # Search for song
        # Download synced lyrics
        # Return LRC content
        pass
```

## Project Structure

```
BrilliantKaraoke/
├── frame_karaoke/          # New Python package
│   ├── __init__.py
│   ├── main.py            # Entry point
│   ├── karaoke_app.py     # KaraokeApp class
│   ├── models.py          # Data models
│   ├── managers/
│   │   ├── __init__.py
│   │   ├── recognition_manager.py
│   │   ├── lyrics_manager.py
│   │   ├── position_tracker.py
│   │   ├── display_manager.py
│   │   └── history_manager.py
│   ├── services/
│   │   ├── __init__.py
│   │   ├── acrcloud_service.py
│   │   └── lrc_service.py
│   └── utils/
│       ├── __init__.py
│       ├── audio_utils.py
│       ├── lrc_parser.py
│       └── text_chunker.py
├── requirements.txt       # Python dependencies
├── .env                   # Environment variables
├── README_FRAME.md        # Frame-specific documentation
└── [existing TypeScript files remain]
```

## Key Implementation Considerations

### 1. Audio Capture Loop

Frame SDK's `record_audio()` blocks until silence or max duration. For continuous monitoring:

```python
async def _audio_capture_loop(self):
    """Continuous audio capture in background."""
    while self.running:
        # Record 2-second chunks
        audio_chunk = await self.frame.microphone.record_audio(
            max_length_in_seconds=2
        )

        # Add to buffer for recognition
        self.recognition_manager.add_audio_chunk(audio_chunk)

        # No sleep needed - record_audio blocks naturally
```

### 2. Concurrent Tasks

Use asyncio.gather() for concurrent operations:

```python
async def _run_karaoke_loop(self):
    """Run multiple tasks concurrently."""
    await asyncio.gather(
        self._audio_capture_task(),
        self._recognition_task(),
        self._display_update_task(),
    )
```

### 3. Display Updates

Frame display can show text, but we should optimize for its higher resolution:

- Text size and positioning can be customized
- Multiple lines of text with good formatting
- Consider using pixel coordinates for precise layout
- Still keep simple text-based approach initially

### 4. Error Handling

Add comprehensive error handling for:
- Bluetooth disconnections
- Audio capture failures
- API timeouts (ACRCloud, LRCLib)
- Invalid audio data

```python
try:
    audio_chunk = await self.frame.microphone.record_audio(2)
except Exception as e:
    logger.error(f"Audio capture failed: {e}")
    await asyncio.sleep(1)  # Prevent tight error loop
```

## Dependencies

```
frame-sdk>=1.0.0
aiohttp>=3.8.0          # Async HTTP client
python-dotenv>=0.20.0   # Environment variables
acrcloud>=1.0.0         # ACRCloud SDK (if available)
```

## Configuration

Environment variables (`.env`):
```
ACRCLOUD_HOST=identify-us-west-2.acrcloud.com
ACRCLOUD_ACCESS_KEY=your_key_here
ACRCLOUD_ACCESS_SECRET=your_secret_here
FRAME_ADDRESS=               # Optional: specific Frame pairing code
```

## Next Steps

1. ✅ Architecture designed
2. Create project structure
3. Implement data models
4. Implement services (ACRCloud, LRC)
5. Implement managers
6. Implement main app
7. Test and refine
8. Document usage
