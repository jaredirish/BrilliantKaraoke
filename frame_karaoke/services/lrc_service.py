"""LRC lyrics fetching service."""

import logging
from typing import Optional
from urllib.parse import urlencode
import aiohttp

logger = logging.getLogger(__name__)


class LRCService:
    """
    Service for fetching synchronized lyrics in LRC format.

    Currently supports LRCLib as the primary source.
    """

    def __init__(self):
        """Initialize LRC service with default sources."""
        self.lrclib_base_url = "https://lrclib.net"
        self.search_endpoint = "/api/search"
        self.get_endpoint = "/api/get"

    async def fetch_lrc(self, title: str, artist: str) -> Optional[str]:
        """
        Fetch LRC lyrics for a song.

        Args:
            title: Song title
            artist: Artist name

        Returns:
            LRC content as string, or None if not found
        """
        try:
            logger.info(f"Fetching lyrics for: '{title}' by '{artist}'")
            lrc_content = await self._fetch_from_lrclib(title, artist)

            if lrc_content:
                logger.info(f"Successfully fetched lyrics for '{title}'")
            else:
                logger.info(f"No synced lyrics found for '{title}'")

            return lrc_content

        except Exception as e:
            logger.error(f"Error fetching lyrics: {e}", exc_info=True)
            return None

    async def _fetch_from_lrclib(
        self,
        title: str,
        artist: str
    ) -> Optional[str]:
        """
        Fetch lyrics from LRCLib API.

        Args:
            title: Song title
            artist: Artist name

        Returns:
            LRC content or None
        """
        try:
            # Build search URL
            params = {
                'track_name': title,
                'artist_name': artist,
            }
            search_url = f"{self.lrclib_base_url}{self.search_endpoint}?{urlencode(params)}"

            async with aiohttp.ClientSession() as session:
                # Search for song
                async with session.get(search_url) as response:
                    if not response.ok:
                        logger.warning(f"LRCLib search failed: {response.status}")
                        return None

                    results = await response.json()

                # Check if we got results
                if not isinstance(results, list) or len(results) == 0:
                    logger.info("No results from LRCLib")
                    return None

                # Find best match
                best_match = self._find_best_match(results, title, artist)

                if not best_match:
                    logger.info("No suitable match found")
                    return None

                # Check if synced lyrics are in the result
                if best_match.get('syncedLyrics'):
                    return best_match['syncedLyrics']

                # If not, try to fetch by ID
                if best_match.get('id'):
                    return await self._fetch_by_id(session, best_match['id'])

                return None

        except aiohttp.ClientError as e:
            logger.error(f"Network error fetching from LRCLib: {e}")
            return None
        except Exception as e:
            logger.error(f"Unexpected error fetching from LRCLib: {e}", exc_info=True)
            return None

    async def _fetch_by_id(
        self,
        session: aiohttp.ClientSession,
        lyrics_id: int
    ) -> Optional[str]:
        """
        Fetch lyrics by ID.

        Args:
            session: Active aiohttp session
            lyrics_id: LRCLib lyrics ID

        Returns:
            LRC content or None
        """
        try:
            url = f"{self.lrclib_base_url}{self.get_endpoint}/{lyrics_id}"

            async with session.get(url) as response:
                if not response.ok:
                    return None

                data = await response.json()
                return data.get('syncedLyrics')

        except Exception as e:
            logger.error(f"Error fetching lyrics by ID {lyrics_id}: {e}")
            return None

    @staticmethod
    def _find_best_match(results: list, title: str, artist: str) -> Optional[dict]:
        """
        Find best matching result from search results.

        Priority:
        1. Exact match (title + artist) with synced lyrics
        2. First result with synced lyrics
        3. First result

        Args:
            results: List of search results
            title: Target song title
            artist: Target artist name

        Returns:
            Best matching result or None
        """
        title_lower = title.lower()
        artist_lower = artist.lower()

        # Try to find exact match with synced lyrics
        for result in results:
            if (result.get('syncedLyrics') and
                result.get('trackName', '').lower() == title_lower and
                result.get('artistName', '').lower() == artist_lower):
                return result

        # Try to find any result with synced lyrics
        for result in results:
            if result.get('syncedLyrics'):
                return result

        # Fall back to first result
        return results[0] if results else None
