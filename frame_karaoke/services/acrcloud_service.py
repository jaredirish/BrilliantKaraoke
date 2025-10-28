"""ACRCloud song recognition service."""

import hashlib
import hmac
import base64
import time
import logging
from typing import Optional
import aiohttp

from ..models import RecognitionResult

logger = logging.getLogger(__name__)


class ACRCloudService:
    """
    Service for song recognition using ACRCloud API.

    Sends audio data to ACRCloud and parses the recognition results.
    """

    def __init__(self, host: str, access_key: str, secret_key: str):
        """
        Initialize ACRCloud service.

        Args:
            host: ACRCloud API host (e.g., identify-us-west-2.acrcloud.com)
            access_key: ACRCloud access key
            secret_key: ACRCloud secret key
        """
        self.host = host
        self.access_key = access_key
        self.secret_key = secret_key
        self.api_url = f"https://{host}/v1/identify"

    async def recognize(self, audio_data: bytes) -> RecognitionResult:
        """
        Recognize song from audio data.

        Args:
            audio_data: Audio data in WAV format

        Returns:
            RecognitionResult with song information or error
        """
        timestamp = int(time.time())
        signature = self._build_signature(timestamp)

        try:
            form_data = self._create_form_data(audio_data, signature, timestamp)

            async with aiohttp.ClientSession() as session:
                async with session.post(self.api_url, data=form_data) as response:
                    if not response.ok:
                        error_msg = f"ACRCloud API error: {response.status}"
                        logger.error(error_msg)
                        return RecognitionResult(
                            title='',
                            artist='',
                            confidence=0.0,
                            error=error_msg
                        )

                    data = await response.json()

            # Check status code
            if data.get('status', {}).get('code') != 0:
                error_msg = data.get('status', {}).get('msg', 'Recognition failed')
                logger.warning(f"ACRCloud recognition failed: {error_msg}")
                return RecognitionResult(
                    title='',
                    artist='',
                    confidence=0.0,
                    error=error_msg
                )

            # Extract music metadata
            music = data.get('metadata', {}).get('music', [])
            if not music or len(music) == 0:
                logger.info("No music detected in audio")
                return RecognitionResult(
                    title='',
                    artist='',
                    confidence=0.0,
                    error='No music detected'
                )

            # Parse first match
            music_info = music[0]
            result = RecognitionResult(
                title=music_info.get('title', ''),
                artist=self._extract_artist(music_info),
                album=music_info.get('album', {}).get('name'),
                duration=self._ms_to_seconds(music_info.get('duration_ms')),
                offset_seconds=self._ms_to_seconds(music_info.get('play_offset_ms')),
                confidence=self._normalize_confidence(music_info.get('score'))
            )

            logger.info(
                f"Recognized: '{result.title}' by '{result.artist}' "
                f"(confidence: {result.confidence:.2f})"
            )
            return result

        except aiohttp.ClientError as e:
            error_msg = f"Network error: {str(e)}"
            logger.error(error_msg)
            return RecognitionResult(
                title='',
                artist='',
                confidence=0.0,
                error=error_msg
            )
        except Exception as e:
            error_msg = f"Unexpected error: {str(e)}"
            logger.error(error_msg, exc_info=True)
            return RecognitionResult(
                title='',
                artist='',
                confidence=0.0,
                error=error_msg
            )

    def _build_signature(self, timestamp: int) -> str:
        """
        Build HMAC-SHA1 signature for ACRCloud API.

        Args:
            timestamp: Unix timestamp

        Returns:
            Base64-encoded signature
        """
        string_to_sign = (
            f"POST\n/v1/identify\n{self.access_key}\n"
            f"audio\n1\n{timestamp}"
        )

        signature = hmac.new(
            self.secret_key.encode('utf-8'),
            string_to_sign.encode('utf-8'),
            hashlib.sha1
        ).digest()

        return base64.b64encode(signature).decode('utf-8')

    def _create_form_data(
        self,
        audio_data: bytes,
        signature: str,
        timestamp: int
    ) -> aiohttp.FormData:
        """
        Create form data for ACRCloud API request.

        Args:
            audio_data: Audio data bytes
            signature: HMAC signature
            timestamp: Unix timestamp

        Returns:
            FormData object ready for POST request
        """
        form = aiohttp.FormData()
        form.add_field('access_key', self.access_key)
        form.add_field('sample_bytes', str(len(audio_data)))
        form.add_field('timestamp', str(timestamp))
        form.add_field('signature', signature)
        form.add_field('data_type', 'audio')
        form.add_field('signature_version', '1')
        form.add_field(
            'sample',
            audio_data,
            filename='audio.wav',
            content_type='audio/wav'
        )

        return form

    @staticmethod
    def _extract_artist(music_info: dict) -> str:
        """Extract artist name from music metadata."""
        artists = music_info.get('artists', [])
        if artists and len(artists) > 0:
            return artists[0].get('name', '')
        return ''

    @staticmethod
    def _ms_to_seconds(milliseconds: Optional[int]) -> Optional[float]:
        """Convert milliseconds to seconds."""
        if milliseconds is None:
            return None
        return milliseconds / 1000.0

    @staticmethod
    def _normalize_confidence(score: Optional[int]) -> float:
        """
        Normalize ACRCloud confidence score from 0-100 to 0-1.

        Args:
            score: Score from 0-100, or None

        Returns:
            Normalized confidence from 0.0 to 1.0
        """
        if score is None:
            return 0.5  # Default confidence
        return max(0.0, min(1.0, score / 100.0))
