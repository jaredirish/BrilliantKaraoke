"""Audio processing utilities."""

import struct
import logging
from typing import List

logger = logging.getLogger(__name__)


def combine_audio_chunks(chunks: List[bytes]) -> bytes:
    """
    Combine multiple audio chunks into a single buffer.

    Args:
        chunks: List of audio data chunks

    Returns:
        Combined audio data
    """
    return b''.join(chunks)


def trim_audio_buffer(
    audio_data: bytes,
    max_duration_seconds: float,
    sample_rate: int = 16000
) -> bytes:
    """
    Trim audio buffer to a maximum duration.

    Keeps the most recent audio (end of buffer).

    Args:
        audio_data: Audio data to trim
        max_duration_seconds: Maximum duration in seconds
        sample_rate: Audio sample rate (default: 16000 Hz)

    Returns:
        Trimmed audio data
    """
    bytes_per_second = sample_rate * 2  # 16-bit mono = 2 bytes per sample
    max_bytes = int(max_duration_seconds * bytes_per_second)

    if len(audio_data) <= max_bytes:
        return audio_data

    # Keep only the last max_bytes
    return audio_data[-max_bytes:]


def calculate_audio_duration(
    audio_length: int,
    sample_rate: int = 16000
) -> float:
    """
    Calculate audio duration from buffer length.

    Args:
        audio_length: Length of audio data in bytes
        sample_rate: Audio sample rate (default: 16000 Hz)

    Returns:
        Duration in seconds
    """
    bytes_per_second = sample_rate * 2  # 16-bit mono
    return audio_length / bytes_per_second


def create_wav_header(data_length: int, sample_rate: int = 16000) -> bytes:
    """
    Create WAV file header for PCM audio.

    Format: 16-bit PCM, mono channel

    Args:
        data_length: Length of audio data in bytes
        sample_rate: Audio sample rate (default: 16000 Hz)

    Returns:
        44-byte WAV header
    """
    # Constants for 16-bit mono PCM
    num_channels = 1
    bits_per_sample = 16
    byte_rate = sample_rate * num_channels * (bits_per_sample // 8)
    block_align = num_channels * (bits_per_sample // 8)

    # Build header (44 bytes total)
    header = bytearray()

    # RIFF chunk descriptor (12 bytes)
    header += b'RIFF'                                    # ChunkID
    header += struct.pack('<I', data_length + 36)       # ChunkSize (file size - 8)
    header += b'WAVE'                                    # Format

    # fmt sub-chunk (24 bytes)
    header += b'fmt '                                    # Subchunk1ID
    header += struct.pack('<I', 16)                     # Subchunk1Size (16 for PCM)
    header += struct.pack('<H', 1)                      # AudioFormat (1 = PCM)
    header += struct.pack('<H', num_channels)           # NumChannels
    header += struct.pack('<I', sample_rate)            # SampleRate
    header += struct.pack('<I', byte_rate)              # ByteRate
    header += struct.pack('<H', block_align)            # BlockAlign
    header += struct.pack('<H', bits_per_sample)        # BitsPerSample

    # data sub-chunk (8 bytes)
    header += b'data'                                    # Subchunk2ID
    header += struct.pack('<I', data_length)            # Subchunk2Size

    return bytes(header)


def create_wav_buffer(audio_data: bytes, sample_rate: int = 16000) -> bytes:
    """
    Create complete WAV file buffer from PCM audio data.

    Args:
        audio_data: Raw PCM audio data
        sample_rate: Audio sample rate (default: 16000 Hz)

    Returns:
        Complete WAV file as bytes (header + data)
    """
    header = create_wav_header(len(audio_data), sample_rate)
    return header + audio_data


def validate_audio_data(audio_data: bytes) -> bool:
    """
    Validate audio data.

    Args:
        audio_data: Audio data to validate

    Returns:
        True if valid, False otherwise
    """
    if not audio_data or len(audio_data) == 0:
        logger.warning("Audio data is empty")
        return False

    # Check if length is reasonable (at least 0.1 seconds at 16kHz)
    min_bytes = int(0.1 * 16000 * 2)  # 0.1 seconds
    if len(audio_data) < min_bytes:
        logger.warning(f"Audio data too short: {len(audio_data)} bytes")
        return False

    return True
