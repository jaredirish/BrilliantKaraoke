"""LRC file parsing and preprocessing utilities."""

import re
import logging
from typing import List, Optional, Dict
from dataclasses import dataclass

from ..models import LRCLine

logger = logging.getLogger(__name__)

# Display constraints
MAX_CHARS_PER_LINE = 45
IDEAL_CHARS_PER_LINE = 35


@dataclass
class PreprocessedLRC:
    """Result of LRC preprocessing."""
    lines: List[LRCLine]
    metadata: Dict[str, any]


def parse_lrc(lrc_content: str) -> List[LRCLine]:
    """
    Parse LRC format lyrics.

    Format: [MM:SS.MS]Lyric text

    Args:
        lrc_content: LRC file content

    Returns:
        List of parsed LRC lines with timestamps
    """
    lines = lrc_content.split('\n')
    lrc_lines: List[LRCLine] = []

    # Regex to match timestamps: [MM:SS.MS]
    time_regex = re.compile(r'^\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)$')

    for line in lines:
        match = time_regex.match(line)
        if match:
            minutes = int(match.group(1))
            seconds = int(match.group(2))
            # Pad milliseconds to 3 digits if needed
            milliseconds_str = match.group(3).ljust(3, '0')
            milliseconds = int(milliseconds_str)

            # Calculate timestamp in seconds
            timestamp = minutes * 60 + seconds + milliseconds / 1000.0
            text = match.group(4).strip()

            if text:  # Only add non-empty lines
                lrc_lines.append(LRCLine(
                    timestamp=timestamp,
                    text=text,
                    end_time=None
                ))

    # Sort by timestamp
    lrc_lines.sort(key=lambda x: x.timestamp)

    # Calculate end times
    for i in range(len(lrc_lines) - 1):
        lrc_lines[i].end_time = lrc_lines[i + 1].timestamp

    # Last line gets default 5-second duration
    if lrc_lines:
        last_line = lrc_lines[-1]
        last_line.end_time = last_line.timestamp + 5.0

    logger.info(f"Parsed {len(lrc_lines)} lyric lines")
    return lrc_lines


def preprocess_lrc(lrc_lines: List[LRCLine]) -> PreprocessedLRC:
    """
    Preprocess LRC lines by merging short lines and splitting long lines.

    Args:
        lrc_lines: Original LRC lines

    Returns:
        Preprocessed LRC with metadata
    """
    if not lrc_lines:
        return PreprocessedLRC(lines=[], metadata={})

    # Calculate initial statistics
    total_chars = sum(len(line.text) for line in lrc_lines)
    avg_length = total_chars / len(lrc_lines) if lrc_lines else 0
    short_lines = sum(1 for line in lrc_lines if len(line.text) < 15)
    long_lines = sum(1 for line in lrc_lines if len(line.text) > MAX_CHARS_PER_LINE)

    metadata = {
        'average_line_length': avg_length,
        'short_lines_count': short_lines,
        'long_lines_count': long_lines,
        'total_lines': len(lrc_lines)
    }

    processed_lines: List[LRCLine] = []
    i = 0

    while i < len(lrc_lines):
        current_line = lrc_lines[i]
        next_line = lrc_lines[i + 1] if i + 1 < len(lrc_lines) else None
        prev_line = lrc_lines[i - 1] if i > 0 else None

        # Handle very long lines by splitting
        if len(current_line.text) > MAX_CHARS_PER_LINE:
            split_lines = _split_long_line(current_line)
            processed_lines.extend(split_lines)
            i += 1
            continue

        # Check if we should merge with next line
        if next_line and _should_merge_lines(current_line, next_line, prev_line):
            merged_line = _merge_two_lines(current_line, next_line)

            # If merged line is still reasonable, use it
            if len(merged_line.text) <= MAX_CHARS_PER_LINE:
                processed_lines.append(merged_line)
                i += 2
                continue

        # Keep line as is
        processed_lines.append(current_line)
        i += 1

    logger.info(
        f"Preprocessed {len(lrc_lines)} lines -> {len(processed_lines)} lines "
        f"(avg: {avg_length:.1f} chars)"
    )

    return PreprocessedLRC(lines=processed_lines, metadata=metadata)


def _should_merge_lines(
    current: LRCLine,
    next_line: LRCLine,
    prev_line: Optional[LRCLine]
) -> bool:
    """Determine if two lines should be merged."""
    # Don't merge if combined would be too long
    combined_length = len(current.text) + len(next_line.text) + 1  # +1 for space
    if combined_length > MAX_CHARS_PER_LINE:
        return False

    # Both lines are very short (likely fragments)
    if len(current.text) < 15 and len(next_line.text) < 15:
        return True

    # Lines are close in time (likely same phrase)
    time_diff = next_line.timestamp - (current.end_time or current.timestamp)
    if time_diff < 1.0:  # Less than 1 second gap
        return True

    # Check for incomplete sentences
    current_ending = current.text.strip()[-1] if current.text.strip() else ''
    next_words = next_line.text.strip().split()
    next_starts_lower = (
        next_words[0][0].islower() if next_words else False
    )

    # Current line doesn't end with sentence terminator
    if current_ending not in ['.', '!', '?']:
        # Next line starts with lowercase (continuation)
        first_word = next_words[0].lower() if next_words else ''
        if next_starts_lower and first_word not in ['i', 'a']:
            return True

        # Current line ends with comma or letter
        if current_ending == ',' or current_ending.isalpha():
            return True

    # Question/answer pattern
    if current_ending == '?' and len(next_line.text) < 20:
        return True

    # Common continuations
    continuation_words = ['but', 'and', 'or', 'so', 'because', 'when', 'while', 'if']
    if next_words and next_words[0].lower() in continuation_words:
        return True

    return False


def _merge_two_lines(line1: LRCLine, line2: LRCLine) -> LRCLine:
    """Merge two LRC lines into one."""
    # Determine appropriate separator
    line1_ending = line1.text.strip()[-1] if line1.text.strip() else ''
    separator = ' '

    # Add comma before conjunctions if no punctuation
    if line1_ending.isalpha():
        line2_words = line2.text.strip().split()
        first_word = line2_words[0].lower() if line2_words else ''
        if first_word in ['but', 'and', 'or', 'so']:
            separator = ', '

    return LRCLine(
        timestamp=line1.timestamp,
        text=line1.text.strip() + separator + line2.text.strip(),
        end_time=line2.end_time or line2.timestamp + 2.0
    )


def _split_long_line(line: LRCLine) -> List[LRCLine]:
    """Split a long line into multiple shorter lines."""
    words = line.text.strip().split()
    chunks: List[str] = []
    current_chunk = ''

    for word in words:
        test_chunk = (current_chunk + ' ' + word) if current_chunk else word

        if len(test_chunk) <= IDEAL_CHARS_PER_LINE:
            current_chunk = test_chunk
        else:
            # Try to find a good break point
            if current_chunk:
                chunks.append(current_chunk)
                current_chunk = word
            else:
                # Single word is too long, add it anyway
                chunks.append(word)

    if current_chunk:
        chunks.append(current_chunk)

    # Create LRCLine objects for each chunk
    duration = (line.end_time or line.timestamp + 2.0) - line.timestamp
    chunk_duration = duration / len(chunks) if chunks else duration

    return [
        LRCLine(
            timestamp=line.timestamp + (chunk_duration * i),
            text=chunk,
            end_time=line.timestamp + (chunk_duration * (i + 1))
        )
        for i, chunk in enumerate(chunks)
    ]


def analyze_lrc_patterns(lines: List[LRCLine]) -> Dict[str, any]:
    """
    Analyze LRC patterns to determine if preprocessing is recommended.

    Args:
        lines: LRC lines to analyze

    Returns:
        Dictionary with analysis results
    """
    if not lines:
        return {
            'has_short_lines': False,
            'has_long_lines': False,
            'average_gap': 0,
            'recommend_preprocessing': False
        }

    total_gap = 0.0
    gap_count = 0
    short_lines = 0
    long_lines = 0

    for i in range(len(lines) - 1):
        gap = lines[i + 1].timestamp - (lines[i].end_time or lines[i].timestamp)
        total_gap += gap
        gap_count += 1

        if len(lines[i].text) < 15:
            short_lines += 1
        if len(lines[i].text) > MAX_CHARS_PER_LINE:
            long_lines += 1

    average_gap = total_gap / gap_count if gap_count > 0 else 0
    short_line_ratio = short_lines / len(lines) if lines else 0
    has_short_lines = short_line_ratio > 0.3  # More than 30% short
    has_long_lines = long_lines > 0

    return {
        'has_short_lines': has_short_lines,
        'has_long_lines': has_long_lines,
        'average_gap': average_gap,
        'recommend_preprocessing': has_short_lines or has_long_lines or average_gap < 1.5
    }


def format_timestamp(seconds: float) -> str:
    """
    Format seconds as MM:SS.

    Args:
        seconds: Time in seconds

    Returns:
        Formatted time string
    """
    mins = int(seconds // 60)
    secs = int(seconds % 60)
    return f"{mins}:{secs:02d}"
