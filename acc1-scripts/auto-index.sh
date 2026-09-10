#!/bin/bash
# Auto-index script for vector database
# Runs periodically to index new/modified files

LOG_FILE="/root/workspaces/tools/acc1-scripts/logs/auto-index.log"
LOCK_FILE="/tmp/auto-index.lock"
CODE_SEARCH_DIR="/root/workspaces/tools/acc1-scripts/mcp-servers/code-search"

# Prevent concurrent runs
if [ -f "$LOCK_FILE" ]; then
    exit 0
fi
trap "rm -f $LOCK_FILE" EXIT
touch "$LOCK_FILE"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Load guard: skip if system is under heavy load
LOAD_NOW=$(awk '{print $1}' /proc/loadavg 2>/dev/null)
LOAD_INT=$(echo "$LOAD_NOW" | awk '{printf "%d", $1 * 10}')
if [ "${LOAD_INT:-0}" -gt 60 ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] LOAD GUARD: load=${LOAD_NOW} > 6.0 — skipping auto-index"
    exit 0
fi

log "=== AUTO-INDEX START ==="

# Activate venv and load env
source "$CODE_SEARCH_DIR/venv/bin/activate"
source ~/.bashrc

# Run indexing
cd "$CODE_SEARCH_DIR"
timeout 120 nice -n 19 ionice -c 3 python3 << 'PYEOF' 2>&1 | tee -a "$LOG_FILE"
import sys, os, asyncio
sys.path.insert(0, '.')
from database import VectorDatabase
from indexer import CodeIndexer
from embeddings import EmbeddingCascade

async def main():
    db = VectorDatabase('/root/workspaces/tools/acc1-scripts/data/vectors.db')
    config = {
        'voyage_api_key': os.environ.get('VOYAGE_API_KEY'),
        'jina_api_key': os.environ.get('JINA_API_KEY'),
        'openai_api_key': os.environ.get('OPENAI_API_KEY')
    }
    cascade = EmbeddingCascade(config)
    indexer = CodeIndexer(cascade, db)  # embedder first, db second

    # Exclude patterns: cache, system files, databases, logs, secrets
    COMMON_EXCLUDE = [
        '__pycache__', 'venv', '.venv', 'node_modules', '.git',
        'dist', 'build', '.cache', '.tmp', '.claude',
        'logs', 'data', '*.db', '*.log', '.env*',
        'statsig', 'plans', 'todos', 'backup*', '*.bak',
        'coverage', '.nyc_output', '.pytest_cache'
    ]

    dirs = [
        ('/root/workspaces/tools/acc1-scripts', ['*.py', '*.sh', '*.md'], COMMON_EXCLUDE),
        ('/root/claude-projects', ['*.py', '*.js', '*.ts', '*.sh'], COMMON_EXCLUDE)
    ]

    for path, patterns, exclude in dirs:
        try:
            result = await indexer.index_directory(path, patterns, exclude)
            print(f"Indexed {path}: {result.get('files_indexed', 0)} files, {result.get('embeddings_created', 0)} chunks")
        except Exception as e:
            print(f"Error {path}: {e}")

    stats = db.get_stats()
    print(f"Total DB: {stats['total_chunks']} chunks, {stats['total_files']} files")

asyncio.run(main())
PYEOF

log "=== AUTO-INDEX COMPLETE ==="
