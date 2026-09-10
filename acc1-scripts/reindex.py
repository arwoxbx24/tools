#!/usr/bin/env python3
"""
Full reindex script for claude-projects
"""

import sys
import os
import asyncio
import logging

# Setup path
sys.path.insert(0, '/root/workspaces/tools/acc1-scripts/mcp-servers/code-search')

from database import VectorDatabase
from indexer import CodeIndexer
from embeddings import EmbeddingCascade

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

COMMON_EXCLUDE = [
    '__pycache__', 'venv', '.venv', 'node_modules', '.git',
    'dist', 'build', '.cache', '.tmp', '.claude',
    'logs', 'data', 'vendor', 'backup', '.bak', 'coverage'
]

async def main():
    logger.info("=== FULL REINDEX START ===")

    db = VectorDatabase('/root/workspaces/tools/acc1-scripts/data/vectors.db')

    config = {
        'voyage_api_key': os.environ.get('VOYAGE_API_KEY'),
        'jina_api_key': os.environ.get('JINA_API_KEY'),
        'openai_api_key': os.environ.get('OPENAI_API_KEY')
    }

    cascade = EmbeddingCascade(config)
    indexer = CodeIndexer(cascade, db)

    stats_before = db.get_stats()
    logger.info(f"Before: {stats_before['total_chunks']} chunks, {stats_before['total_files']} files")

    # Index claude-projects
    logger.info("Indexing /root/claude-projects...")
    result = await indexer.index_directory(
        '/root/claude-projects',
        ['*.py', '*.php', '*.js', '*.ts', '*.sh', '*.md', '*.json'],
        COMMON_EXCLUDE
    )
    logger.info(f"Result: {result['files_indexed']} files, {result['embeddings_created']} embeddings")

    if result['errors']:
        logger.warning(f"Errors: {len(result['errors'])}")
        for err in result['errors'][:5]:
            logger.warning(f"  - {err}")

    stats_after = db.get_stats()
    logger.info(f"After: {stats_after['total_chunks']} chunks, {stats_after['total_files']} files")
    logger.info(f"Added: {stats_after['total_chunks'] - stats_before['total_chunks']} chunks")
    logger.info("=== COMPLETE ===")

if __name__ == '__main__':
    asyncio.run(main())
