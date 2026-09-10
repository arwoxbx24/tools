#!/usr/bin/env python3
"""
Build Intent Embeddings

Reads intents.yaml, embeds all examples via Jina AI API,
computes centroid (average) vectors per intent, and saves
to intents-embeddings.json.

Usage: python3 build-intent-embeddings.py

Requires: JINA_API_KEY in environment or secrets/global.env
Dependencies: httpx, pyyaml

Author: Claude Expert System
"""

import json
import os
import sys
from datetime import datetime
import math

_load = float(open('/proc/loadavg').read().split()[0])
if _load > 6.0:
    print(f"LOAD GUARD: load={_load} > 6.0 — skipping embedding build")
    exit(0)

try:
    import httpx
except ImportError:
    print("ERROR: httpx not installed. Run: pip3 install httpx", file=sys.stderr)
    sys.exit(1)

try:
    import yaml
except ImportError:
    print("ERROR: pyyaml not installed. Run: pip3 install pyyaml", file=sys.stderr)
    sys.exit(1)

# Configuration
INTENTS_FILE = "/root/workspaces/tools/acc1-scripts/config/intents.yaml"
OUTPUT_FILE = "/root/workspaces/tools/acc1-scripts/config/intents-embeddings.json"
SECRETS_FILE = "/root/workspaces/secrets/global.env"


def log(message):
    """Log to stderr"""
    print(f"[build-embeddings] {message}", file=sys.stderr)


def load_api_key():
    """Load JINA_API_KEY from environment or secrets file"""
    # Check environment first
    api_key = os.environ.get('JINA_API_KEY')
    if api_key:
        return api_key

    # Load from secrets file
    try:
        with open(SECRETS_FILE, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    if key.strip() == 'JINA_API_KEY':
                        return value.strip().strip('"').strip("'")
    except Exception as e:
        log(f"ERROR loading secrets: {e}")

    return None


def embed_texts(texts, api_key):
    """Embed multiple texts using Jina AI API"""
    log(f"Embedding {len(texts)} texts...")

    response = httpx.post(
        'https://api.jina.ai/v1/embeddings',
        headers={
            'Authorization': f'Bearer {api_key}',
            'Content-Type': 'application/json'
        },
        json={
            'input': texts,
            'model': 'jina-embeddings-v3',
            'task': 'text-matching'
        },
        timeout=30.0
    )

    response.raise_for_status()
    data = response.json()

    return [item['embedding'] for item in data['data']]


def normalize_vector(vec):
    """Normalize vector to unit length"""
    magnitude = math.sqrt(sum(x * x for x in vec))
    if magnitude == 0:
        return vec
    return [x / magnitude for x in vec]


def compute_centroid(embeddings):
    """Compute centroid (average) of multiple embeddings"""
    if not embeddings:
        return []

    dim = len(embeddings[0])
    centroid = [0.0] * dim

    for embedding in embeddings:
        for i in range(dim):
            centroid[i] += embedding[i]

    # Average
    for i in range(dim):
        centroid[i] /= len(embeddings)

    # Normalize to unit vector
    return normalize_vector(centroid)


def main():
    """Main entry point"""
    log("Starting intent embeddings builder")

    # Load API key
    api_key = load_api_key()
    if not api_key:
        log("ERROR: JINA_API_KEY not found in environment or secrets file")
        sys.exit(1)

    log("API key loaded")

    # Load intents.yaml
    try:
        with open(INTENTS_FILE, 'r') as f:
            config = yaml.safe_load(f)
    except Exception as e:
        log(f"ERROR loading {INTENTS_FILE}: {e}")
        sys.exit(1)

    intents = config.get('intents', {})
    log(f"Loaded {len(intents)} intent categories")

    # Build embeddings
    result = {
        'version': config.get('version', 1),
        'model': config.get('embedding_model', 'jina-embeddings-v3'),
        'dim': config.get('embedding_dim', 1024),
        'built_at': datetime.utcnow().isoformat() + 'Z',
        'intents': {}
    }

    total_examples = 0

    for intent_name, intent_data in intents.items():
        examples = intent_data.get('examples', [])
        if not examples:
            log(f"WARNING: Intent '{intent_name}' has no examples, skipping")
            continue

        log(f"Processing intent '{intent_name}' with {len(examples)} examples...")

        try:
            # Embed all examples
            embeddings = embed_texts(examples, api_key)

            # Compute centroid
            centroid = compute_centroid(embeddings)

            result['intents'][intent_name] = {
                'threshold': intent_data.get('threshold', 0.70),
                'description': intent_data.get('description', ''),
                'centroid': centroid,
                'examples_count': len(examples)
            }

            total_examples += len(examples)
            log(f"  ✓ Computed centroid from {len(examples)} examples")

        except Exception as e:
            log(f"ERROR processing intent '{intent_name}': {e}")
            continue

    # Save to JSON
    try:
        with open(OUTPUT_FILE, 'w') as f:
            json.dump(result, f, indent=2)
        log(f"Saved embeddings to {OUTPUT_FILE}")
    except Exception as e:
        log(f"ERROR saving output: {e}")
        sys.exit(1)

    # Print summary
    print("\n" + "="*60)
    print("Intent Embeddings Build Summary")
    print("="*60)
    print(f"Model:            {result['model']}")
    print(f"Dimensions:       {result['dim']}")
    print(f"Intents:          {len(result['intents'])}")
    print(f"Total examples:   {total_examples}")
    print(f"Output:           {OUTPUT_FILE}")
    print(f"Built at:         {result['built_at']}")
    print("="*60)

    # List intents
    print("\nIntent categories:")
    for intent_name, intent_info in result['intents'].items():
        print(f"  - {intent_name:20s} ({intent_info['examples_count']:2d} examples, threshold={intent_info['threshold']:.2f})")

    print("\n✓ Build complete")


if __name__ == '__main__':
    main()
