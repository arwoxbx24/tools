#!/bin/bash
# Quick embedding test
# Usage: bash test-embedding.sh ["optional text to embed"]

TEXT="${1:-Hello world test embedding}"

echo "=== EMBEDDING TEST ==="
echo "Text: $TEXT"
echo ""

cd /root/workspaces/tools/acc1-scripts/mcp-servers/code-search

# Run Python test
python3 << PYEOF
import asyncio
from embeddings import EmbeddingCascade, get_rate_tracker
import os

async def test():
    config = {
        'voyage_api_key': os.environ.get('VOYAGE_API_KEY', 'dummy'),
        'jina_api_key': os.environ.get('JINA_API_KEY'),
        'openai_api_key': os.environ.get('OPENAI_API_KEY')
    }
    
    cascade = EmbeddingCascade(config)
    
    print("Calling embedding cascade...")
    try:
        result = await cascade.embed(["$TEXT"])
        print(f"✅ SUCCESS!")
        print(f"   Dimensions: {len(result[0])}")
        print(f"   First 5 values: {result[0][:5]}")
    except Exception as e:
        print(f"❌ FAILED: {e}")
    
    # Show rate limit status
    tracker = get_rate_tracker()
    status = tracker.get_status()
    if status.get('providers'):
        print(f"\n📊 Rate limits: {status['providers']}")

asyncio.run(test())
PYEOF

echo ""
echo "=== CHECK LOG ==="
tail -3 /root/workspaces/tools/acc1-scripts/logs/embeddings.log
