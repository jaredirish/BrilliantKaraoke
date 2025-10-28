"""Utility modules."""

from .audio_utils import (
    combine_audio_chunks,
    trim_audio_buffer,
    create_wav_header,
    create_wav_buffer,
    calculate_audio_duration,
    validate_audio_data,
)
from .lrc_parser import (
    parse_lrc,
    preprocess_lrc,
    analyze_lrc_patterns,
    format_timestamp,
)
from .text_chunker import (
    chunk_lyrics,
    get_current_chunk,
    get_next_chunk,
)

__all__ = [
    'combine_audio_chunks',
    'trim_audio_buffer',
    'create_wav_header',
    'create_wav_buffer',
    'calculate_audio_duration',
    'validate_audio_data',
    'parse_lrc',
    'preprocess_lrc',
    'analyze_lrc_patterns',
    'format_timestamp',
    'chunk_lyrics',
    'get_current_chunk',
    'get_next_chunk',
]
