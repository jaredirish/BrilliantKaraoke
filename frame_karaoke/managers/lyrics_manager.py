"""Lyrics fetching and management."""

import logging
from typing import Dict, List, Optional

from ..models import CurrentSong, LRCLine, LyricsChunk
from ..services import LRCService
from ..utils import (
    parse_lrc,
    preprocess_lrc,
    analyze_lrc_patterns,
    chunk_lyrics,
)

logger = logging.getLogger(__name__)


class LyricsManager:
    """
    Manages lyrics fetching, parsing, and chunking.

    Handles LRC file fetching, preprocessing, chunking for display,
    and position-based chunk retrieval.
    """

    def __init__(self, lrc_service: LRCService):
        """
        Initialize lyrics manager.

        Args:
            lrc_service: LRC service for fetching lyrics
        """
        self.lrc_service = lrc_service
        self.cached_lrc: Dict[str, List[LRCLine]] = {}
        self.current_chunks: List[LyricsChunk] = []

    async def fetch_lyrics(self, song: CurrentSong) -> Optional[List[LRCLine]]:
        """
        Fetch and parse lyrics for a song.

        Args:
            song: Song to fetch lyrics for

        Returns:
            List of LRC lines or None if not found
        """
        cache_key = f"{song.artist}-{song.title}"

        # Check cache first
        if cache_key in self.cached_lrc:
            logger.info(f"Using cached lyrics for '{song.title}'")
            return self.cached_lrc[cache_key]

        try:
            # Fetch LRC content
            lrc_content = await self.lrc_service.fetch_lrc(song.title, song.artist)

            if not lrc_content:
                logger.info(f"No lyrics found for '{song.title}'")
                return None

            # Parse LRC
            raw_lrc_data = parse_lrc(lrc_content)

            if not raw_lrc_data:
                logger.warning("Failed to parse LRC data")
                return None

            # Analyze if preprocessing would help
            analysis = analyze_lrc_patterns(raw_lrc_data)

            lrc_data = raw_lrc_data
            if analysis['recommend_preprocessing']:
                logger.info("Preprocessing LRC data")
                preprocessed = preprocess_lrc(raw_lrc_data)
                lrc_data = preprocessed.lines

                logger.info(
                    f"LRC preprocessed: {len(raw_lrc_data)} -> {len(lrc_data)} lines"
                )

            # Cache the processed lyrics
            self.cached_lrc[cache_key] = lrc_data

            # Create chunks for display
            self.current_chunks = self.chunk_lyrics(lrc_data)

            logger.info(
                f"Fetched lyrics for '{song.title}': "
                f"{len(lrc_data)} lines, {len(self.current_chunks)} chunks"
            )

            return lrc_data

        except Exception as e:
            logger.error(f"Error fetching lyrics: {e}", exc_info=True)
            return None

    def chunk_lyrics(
        self,
        lrc_data: List[LRCLine],
        max_words_per_line: int = 8,
        max_chars_per_line: int = 60,
        lines_per_chunk: int = 2
    ) -> List[LyricsChunk]:
        """
        Chunk lyrics for display.

        Args:
            lrc_data: Parsed LRC lines
            max_words_per_line: Maximum words per line
            max_chars_per_line: Maximum characters per line
            lines_per_chunk: Lines per chunk

        Returns:
            List of lyrics chunks
        """
        return chunk_lyrics(
            lrc_data,
            max_words_per_line,
            max_chars_per_line,
            lines_per_chunk
        )

    def get_current_chunk(self, position: float) -> Optional[LyricsChunk]:
        """
        Get lyrics chunk for current position.

        Args:
            position: Current position in song (seconds)

        Returns:
            Current chunk or None
        """
        if not self.current_chunks:
            return None

        # Find chunk that contains this position
        for chunk in self.current_chunks:
            if chunk.start_time <= position < chunk.end_time:
                return chunk

        # If no exact match, check if we're close to the next chunk (within 1 second)
        for chunk in self.current_chunks:
            if chunk.start_time > position and chunk.start_time - position < 1.0:
                return chunk

        return None

    def get_next_chunk(self, position: float) -> Optional[LyricsChunk]:
        """
        Get next lyrics chunk after current position.

        Args:
            position: Current position in song (seconds)

        Returns:
            Next chunk or None
        """
        if not self.current_chunks:
            return None

        # Get current chunk
        current_chunk = self.get_current_chunk(position)

        if current_chunk is None:
            # No current chunk, find first chunk after position
            for chunk in self.current_chunks:
                if chunk.start_time > position:
                    return chunk
            return None

        # Find next chunk after current
        try:
            current_index = self.current_chunks.index(current_chunk)
            if current_index < len(self.current_chunks) - 1:
                return self.current_chunks[current_index + 1]
        except ValueError:
            pass

        return None

    def clear_cache(self):
        """Clear lyrics cache."""
        self.cached_lrc.clear()
        self.current_chunks = []
        logger.info("Lyrics cache cleared")

    def get_cache_size(self) -> int:
        """Get number of cached lyrics."""
        return len(self.cached_lrc)
