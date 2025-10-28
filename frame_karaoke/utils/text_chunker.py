"""Text chunking utilities for display formatting."""

import logging
from typing import List

from ..models import LRCLine, LyricsChunk

logger = logging.getLogger(__name__)


def chunk_lyrics(
    lrc_data: List[LRCLine],
    max_words_per_line: int = 8,
    max_chars_per_line: int = 60,
    lines_per_chunk: int = 2
) -> List[LyricsChunk]:
    """
    Chunk lyrics for display on smart glasses.

    Splits long lyrics lines into multiple display-friendly chunks,
    respecting word boundaries and display constraints.

    Args:
        lrc_data: Parsed LRC lines
        max_words_per_line: Maximum words per display line (default: 8)
        max_chars_per_line: Maximum characters per line (default: 60)
        lines_per_chunk: Lines per display chunk (default: 2)

    Returns:
        List of lyrics chunks ready for display
    """
    chunks: List[LyricsChunk] = []

    for lrc_line in lrc_data:
        # Split the line into display-friendly chunks
        lines = _split_line_into_chunks(
            lrc_line.text,
            max_words_per_line,
            max_chars_per_line
        )

        # Group lines into chunks (e.g., 2 lines per chunk)
        for j in range(0, len(lines), lines_per_chunk):
            chunk_lines = lines[j:j + lines_per_chunk]
            words_per_line = [
                len(line.split()) for line in chunk_lines
            ]

            start_time = lrc_line.timestamp
            end_time = lrc_line.end_time or lrc_line.timestamp + 3.0

            # If we split a line into multiple chunks, adjust timing
            if len(lines) > lines_per_chunk:
                progress = (j + len(chunk_lines)) / len(lines)
                end_time = start_time + (end_time - start_time) * progress

            chunks.append(LyricsChunk(
                lines=chunk_lines,
                start_time=start_time,
                end_time=end_time,
                words_per_line=words_per_line
            ))

    logger.info(f"Created {len(chunks)} lyrics chunks from {len(lrc_data)} LRC lines")
    return chunks


def _split_line_into_chunks(
    text: str,
    max_words: int,
    max_chars: int
) -> List[str]:
    """
    Split a text line into multiple chunks respecting word boundaries.

    Args:
        text: Text to split
        max_words: Maximum words per chunk
        max_chars: Maximum characters per chunk

    Returns:
        List of text chunks
    """
    words = [w for w in text.split() if w]  # Filter empty strings
    chunks: List[str] = []
    current_chunk: List[str] = []
    current_length = 0

    for word in words:
        # If single word exceeds max, add it on its own line
        if len(word) > max_chars:
            if current_chunk:
                chunks.append(' '.join(current_chunk))
                current_chunk = []
                current_length = 0
            chunks.append(word)
            continue

        # Calculate length if we add this word
        word_length = len(word) + (1 if current_chunk else 0)  # +1 for space

        # Check if adding this word would exceed limits
        if (len(current_chunk) >= max_words or
            current_length + word_length > max_chars):
            # Finish current chunk
            if current_chunk:
                chunks.append(' '.join(current_chunk))
                current_chunk = []
                current_length = 0

        # Add word to current chunk
        current_chunk.append(word)
        current_length += word_length

    # Add remaining chunk
    if current_chunk:
        chunks.append(' '.join(current_chunk))

    return chunks if chunks else ['']


def get_current_chunk(
    chunks: List[LyricsChunk],
    position: float
) -> LyricsChunk | None:
    """
    Get the lyrics chunk for the current position.

    Args:
        chunks: List of lyrics chunks
        position: Current position in seconds

    Returns:
        Current chunk or None
    """
    for chunk in chunks:
        if chunk.start_time <= position < chunk.end_time:
            return chunk
    return None


def get_next_chunk(
    chunks: List[LyricsChunk],
    position: float
) -> LyricsChunk | None:
    """
    Get the next lyrics chunk after current position.

    Useful for showing preview of upcoming lyrics.

    Args:
        chunks: List of lyrics chunks
        position: Current position in seconds

    Returns:
        Next chunk or None
    """
    for chunk in chunks:
        if chunk.start_time > position:
            return chunk
    return None
