"""Entry point for Frame Karaoke application."""

import asyncio
import logging
import os
import sys
from dotenv import load_dotenv
import coloredlogs

from .karaoke_app import KaraokeApp


def setup_logging(log_level: str = "INFO"):
    """
    Configure logging.

    Args:
        log_level: Logging level (DEBUG, INFO, WARNING, ERROR)
    """
    # Configure colored logs
    coloredlogs.install(
        level=log_level,
        fmt='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        level_styles={
            'debug': {'color': 'cyan'},
            'info': {'color': 'green'},
            'warning': {'color': 'yellow'},
            'error': {'color': 'red', 'bold': True},
        }
    )

    # Set frame_sdk to WARNING to reduce noise
    logging.getLogger('frame_sdk').setLevel(logging.WARNING)


def load_config():
    """
    Load configuration from environment variables.

    Returns:
        Dictionary with configuration
    """
    # Load .env file
    load_dotenv()

    # Required configuration
    acrcloud_host = os.getenv('ACRCLOUD_HOST')
    acrcloud_access_key = os.getenv('ACRCLOUD_ACCESS_KEY')
    acrcloud_secret_key = os.getenv('ACRCLOUD_ACCESS_SECRET')

    if not all([acrcloud_host, acrcloud_access_key, acrcloud_secret_key]):
        print("Error: Missing required ACRCloud credentials in environment variables")
        print("Required variables:")
        print("  - ACRCLOUD_HOST")
        print("  - ACRCLOUD_ACCESS_KEY")
        print("  - ACRCLOUD_ACCESS_SECRET")
        print("\nCopy .env.example to .env and fill in your credentials")
        sys.exit(1)

    # Optional configuration
    frame_address = os.getenv('FRAME_ADDRESS', None)
    log_level = os.getenv('LOG_LEVEL', 'INFO')

    return {
        'acrcloud_host': acrcloud_host,
        'acrcloud_access_key': acrcloud_access_key,
        'acrcloud_secret_key': acrcloud_secret_key,
        'frame_address': frame_address if frame_address else None,
        'log_level': log_level,
    }


def print_banner():
    """Print application banner."""
    banner = """
    ╔═══════════════════════════════════════════════════════╗
    ║                                                       ║
    ║              ♪  FRAME KARAOKE  ♪                     ║
    ║                                                       ║
    ║      Real-time Karaoke for Brilliant Labs Frame      ║
    ║                                                       ║
    ╚═══════════════════════════════════════════════════════╝
    """
    print(banner)


async def main():
    """Main entry point."""
    # Print banner
    print_banner()

    # Load configuration
    config = load_config()

    # Setup logging
    setup_logging(config['log_level'])

    logger = logging.getLogger(__name__)
    logger.info("Starting Frame Karaoke application")

    # Log configuration (without secrets)
    logger.info(f"ACRCloud Host: {config['acrcloud_host']}")
    if config['frame_address']:
        logger.info(f"Frame Address: {config['frame_address']}")
    else:
        logger.info("Frame Address: Auto-detect (will connect to any Frame)")

    # Create and start app
    app = KaraokeApp(
        acrcloud_host=config['acrcloud_host'],
        acrcloud_access_key=config['acrcloud_access_key'],
        acrcloud_secret_key=config['acrcloud_secret_key'],
        frame_address=config['frame_address']
    )

    try:
        await app.start()
    except KeyboardInterrupt:
        logger.info("Received interrupt signal, shutting down...")
    except Exception as e:
        logger.error(f"Application error: {e}", exc_info=True)
        sys.exit(1)

    logger.info("Frame Karaoke stopped")


if __name__ == '__main__':
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nShutting down...")
        sys.exit(0)
