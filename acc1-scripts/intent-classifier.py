#!/usr/bin/env python3
"""
Intent Classifier HTTP Service

Classifies Russian user messages into intent categories using
semantic similarity with pre-computed embeddings.

Port: 20512
Endpoints:
  GET /classify?text=<url-encoded-text>
  GET /health

Author: Claude Expert System
"""

import json
import hashlib
import subprocess
import sys
import os
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs, urlparse, unquote_plus
import math
import time

# Configuration
PORT = 20512
EMBEDDINGS_FILE = "/root/workspaces/tools/acc1-scripts/config/intents-embeddings.json"
SECRETS_FILE = "/root/workspaces/secrets/global.env"
MAX_TEXT_LENGTH = 500
CACHE_TTL = 3600

# Global state
intents_data = None
api_keys = {}


def log(message):
    """Log to stderr"""
    print(f"[intent-classifier] {message}", file=sys.stderr)


def load_env():
    """Load API keys from secrets file"""
    global api_keys
    try:
        with open(SECRETS_FILE, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    key = key.strip()
                    value = value.strip().strip('"').strip("'")
                    if key in ['JINA_API_KEY', 'VOYAGE_API_KEY', 'OPENAI_API_KEY']:
                        api_keys[key] = value
        log(f"Loaded API keys: {', '.join(api_keys.keys())}")
    except Exception as e:
        log(f"ERROR loading secrets: {e}")


def load_intents():
    """Load pre-computed intent embeddings"""
    global intents_data
    try:
        with open(EMBEDDINGS_FILE, 'r') as f:
            intents_data = json.load(f)
        log(f"Loaded {len(intents_data.get('intents', {}))} intents from {EMBEDDINGS_FILE}")
        return True
    except Exception as e:
        log(f"CRITICAL: Failed to load intents: {e}")
        return False


def redis_get(key):
    """Get value from Redis"""
    try:
        result = subprocess.run(['redis-cli', 'GET', key],
                              capture_output=True, text=True, timeout=2)
        val = result.stdout.strip()
        return None if val == '(nil)' else val
    except:
        return None


def redis_set(key, value, ex=3600):
    """Set value in Redis with expiration"""
    try:
        subprocess.run(['redis-cli', 'SET', key, value, 'EX', str(ex)],
                      capture_output=True, timeout=2)
    except:
        pass


def cosine_similarity(vec1, vec2):
    """Compute cosine similarity between two vectors"""
    if len(vec1) != len(vec2):
        # Handle dimension mismatch - truncate to shorter
        min_len = min(len(vec1), len(vec2))
        vec1 = vec1[:min_len]
        vec2 = vec2[:min_len]

    dot_product = sum(a * b for a, b in zip(vec1, vec2))
    magnitude1 = math.sqrt(sum(a * a for a in vec1))
    magnitude2 = math.sqrt(sum(b * b for b in vec2))

    if magnitude1 == 0 or magnitude2 == 0:
        return 0.0

    return dot_product / (magnitude1 * magnitude2)


def normalize_vector(vec):
    """Normalize vector to unit length"""
    magnitude = math.sqrt(sum(x * x for x in vec))
    if magnitude == 0:
        return vec
    return [x / magnitude for x in vec]


def embed_text_jina(text):
    """Embed text using Jina AI API"""
    import httpx

    api_key = api_keys.get('JINA_API_KEY')
    if not api_key:
        raise Exception("JINA_API_KEY not found")

    response = httpx.post(
        'https://api.jina.ai/v1/embeddings',
        headers={
            'Authorization': f'Bearer {api_key}',
            'Content-Type': 'application/json'
        },
        json={
            'input': [text],
            'model': 'jina-embeddings-v3',
            'task': 'text-matching'
        },
        timeout=10.0
    )
    response.raise_for_status()
    data = response.json()
    return data['data'][0]['embedding']


def embed_text_voyage(text):
    """Embed text using Voyage AI API via Cloudflare proxy"""
    import httpx

    api_key = api_keys.get('VOYAGE_API_KEY')
    if not api_key:
        raise Exception("VOYAGE_API_KEY not found")

    response = httpx.post(
        'https://cf-voyage-embeddings.b244.workers.dev',
        headers={
            'Authorization': f'Bearer {api_key}',
            'Content-Type': 'application/json'
        },
        json={
            'input': [text],
            'model': 'voyage-code-3'
        },
        timeout=10.0
    )
    response.raise_for_status()
    data = response.json()
    return data['data'][0]['embedding']


def embed_text_openai(text):
    """Embed text using OpenAI API (fallback)"""
    import httpx

    api_key = api_keys.get('OPENAI_API_KEY')
    if not api_key:
        raise Exception("OPENAI_API_KEY not found")

    response = httpx.post(
        'https://api.openai.com/v1/embeddings',
        headers={
            'Authorization': f'Bearer {api_key}',
            'Content-Type': 'application/json'
        },
        json={
            'input': text,
            'model': 'text-embedding-3-small'
        },
        timeout=10.0
    )
    response.raise_for_status()
    data = response.json()
    embedding = data['data'][0]['embedding']

    # OpenAI returns 1536-dim, truncate to 1024 for consistency
    return embedding[:1024]


def embed_text(text):
    """Embed text with fallback cascade: Jina → Voyage → OpenAI"""
    errors = []

    # Try Jina first
    try:
        return embed_text_jina(text), 'jina'
    except Exception as e:
        errors.append(f"Jina: {str(e)}")

    # Try Voyage
    try:
        return embed_text_voyage(text), 'voyage'
    except Exception as e:
        errors.append(f"Voyage: {str(e)}")

    # Try OpenAI
    try:
        return embed_text_openai(text), 'openai'
    except Exception as e:
        errors.append(f"OpenAI: {str(e)}")

    raise Exception(f"All embedding providers failed: {'; '.join(errors)}")


def classify_text(text):
    """Classify text into intent categories"""
    if not intents_data:
        return {"error": "Intents not loaded"}

    # Truncate text
    text = text[:MAX_TEXT_LENGTH]

    # Check cache
    cache_key = f"intent:cache:{hashlib.md5(text.encode()).hexdigest()}"
    cached = redis_get(cache_key)
    if cached:
        try:
            result = json.loads(cached)
            result['cached'] = True
            return result
        except:
            pass

    # Embed query text
    try:
        query_embedding, provider = embed_text(text)
        log(f"Embedded text using {provider} ({len(query_embedding)} dims)")
    except Exception as e:
        log(f"ERROR embedding text: {e}")
        return {
            "intents": [],
            "top": None,
            "cached": False,
            "error": str(e)
        }

    # Compute similarities
    results = []
    for intent_name, intent_info in intents_data.get('intents', {}).items():
        centroid = intent_info['centroid']
        threshold = intent_info['threshold']

        similarity = cosine_similarity(query_embedding, centroid)

        if similarity >= threshold:
            results.append({
                "name": intent_name,
                "score": round(similarity, 3)
            })

    # Sort by score descending
    results.sort(key=lambda x: x['score'], reverse=True)

    response = {
        "intents": results,
        "top": results[0]['name'] if results else None,
        "cached": False
    }

    # Cache result
    try:
        redis_set(cache_key, json.dumps(response), CACHE_TTL)
    except:
        pass

    return response


class IntentHandler(BaseHTTPRequestHandler):
    """HTTP request handler"""

    def log_message(self, format, *args):
        """Suppress default logging"""
        pass

    def do_GET(self):
        """Handle GET requests"""
        parsed = urlparse(self.path)

        if parsed.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            response = {
                "status": "ok",
                "intents_loaded": len(intents_data.get('intents', {})) if intents_data else 0
            }
            self.wfile.write(json.dumps(response).encode())
            return

        if parsed.path == '/classify':
            params = parse_qs(parsed.query)
            text = params.get('text', [''])[0]

            if not text:
                self.send_response(400)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({"error": "Missing text parameter"}).encode())
                return

            # Decode URL encoding
            text = unquote_plus(text)

            start_time = time.time()
            result = classify_text(text)
            elapsed = round((time.time() - start_time) * 1000, 1)

            log(f"Classified '{text[:50]}...' in {elapsed}ms: {result.get('top', 'none')}")

            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(result).encode())
            return

        # 404 for unknown paths
        self.send_response(404)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({"error": "Not found"}).encode())


def main():
    """Main entry point"""
    log("Starting Intent Classifier HTTP service")

    # Load environment
    load_env()

    if not api_keys:
        log("ERROR: No API keys found in secrets file")
        sys.exit(1)

    # Load intents
    if not load_intents():
        log("ERROR: Cannot start without intents data")
        sys.exit(1)

    # Start HTTP server
    server = HTTPServer(('0.0.0.0', PORT), IntentHandler)
    log(f"Listening on 0.0.0.0:{PORT}")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log("Shutting down")
        server.shutdown()


if __name__ == '__main__':
    main()
