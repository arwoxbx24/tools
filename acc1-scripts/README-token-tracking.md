# Token Usage Tracking Scripts

Scripts for parsing and analyzing agent token usage from JSONL files.

## Scripts

### parse-agent-tokens.sh

Parses agent JSONL files to extract token usage statistics and stores them in Redis DB 5.

**Usage:**
```bash
parse-agent-tokens.sh <path-to-agent-jsonl>
```

**Example:**
```bash
parse-agent-tokens.sh /tmp/claude-0/agent-a87a701.jsonl
parse-agent-tokens.sh agent-abc123.jsonl
```

**Features:**
- Extracts token counts (input, output, cache read/write)
- Detects model type (opus/sonnet/haiku)
- Calculates cost estimates based on model pricing
- Stores data in Redis with 30-day retention
- Updates daily totals (per-agent, per-model, global)

**Output:**
```
📊 Agent Token Stats: a87a701
─────────────────────────────────
Model:        sonnet
Input:        12,500 tokens
Output:       3,400 tokens
Cache Read:   25,000 tokens
Cache Write:  9,200 tokens
Messages:     15
Est. Cost:    $0.0234
─────────────────────────────────
✓ Saved to Redis DB 5
```

**Redis Keys Created:**
- `tokens:agent:{AGENT_ID}:{DATE}` - Per-agent daily stats
- `tokens:model:{MODEL}:{DATE}` - Per-model daily totals
- `tokens:global:{DATE}` - Global daily totals

**Model Pricing:**
- Opus: $15/M input, $75/M output
- Sonnet: $3/M input, $15/M output
- Haiku: $0.25/M input, $1.25/M output

### view-token-stats.sh

View token usage statistics stored in Redis DB 5.

**Usage:**
```bash
view-token-stats.sh [OPTIONS]
```

**Options:**
- `-d, --date DATE` - Show stats for specific date (YYYY-MM-DD, default: today)
- `-a, --agent AGENT_ID` - Show stats for specific agent
- `-m, --model MODEL` - Show stats for model (opus/sonnet/haiku)
- `-g, --global` - Show global daily stats (default)
- `-l, --list` - List all available keys
- `-h, --help` - Show help message

**Examples:**
```bash
# Today's global stats
view-token-stats.sh --global

# Specific model stats
view-token-stats.sh --model sonnet

# Specific agent stats
view-token-stats.sh --agent a87a701

# Specific date
view-token-stats.sh --date 2026-02-01 --global

# List all stored stats
view-token-stats.sh --list
```

## JSONL File Format

The scripts expect JSONL files with the following structure:

```json
{
  "agentId": "abc123",
  "message": {
    "id": "msg_01",
    "type": "message",
    "role": "assistant",
    "model": "claude-sonnet-4-5-20250929",
    "usage": {
      "input_tokens": 1500,
      "output_tokens": 850,
      "cache_creation_input_tokens": 2000,
      "cache_read_input_tokens": 5000
    }
  }
}
```

**Key fields:**
- `message.usage` or `usage` - Token usage data
- `message.model` or `model` - Model identifier
- `agentId` - Agent identifier (optional, can be extracted from filename)

**Filename format:**
- `agent-{AGENT_ID}.jsonl` - Recommended format for automatic agent ID extraction
- Any `.jsonl` file will work, but agent ID must be in filename

## Redis Data Structure

### Agent Stats
```
tokens:agent:{AGENT_ID}:{DATE}
  input_tokens: integer
  output_tokens: integer
  cache_read: integer
  cache_write: integer
  model: string
  cost_usd: float
  message_count: integer
  timestamp: unix_timestamp
```

### Model Stats
```
tokens:model:{MODEL}:{DATE}
  total_input: integer (accumulative)
  total_output: integer (accumulative)
  total_cache_read: integer (accumulative)
  total_cache_write: integer (accumulative)
  total_cost: float (accumulative)
```

### Global Stats
```
tokens:global:{DATE}
  total_input: integer (accumulative)
  total_output: integer (accumulative)
  total_cache_read: integer (accumulative)
  total_cache_write: integer (accumulative)
  total_cost: float (accumulative)
```

## Integration Examples

### Parse all agent files in directory
```bash
for file in /tmp/claude-*/agent-*.jsonl; do
  [ -f "$file" ] && parse-agent-tokens.sh "$file"
done
```

### Weekly cost report
```bash
#!/bin/bash
echo "Weekly Token Usage Report"
echo "========================="
for i in {0..6}; do
  date=$(date -d "$i days ago" +%Y-%m-%d)
  echo ""
  echo "Date: $date"
  view-token-stats.sh --date "$date" --global | grep "Total Cost"
done
```

### Monitor daily spend
```bash
#!/bin/bash
# Add to crontab: 0 23 * * * /path/to/monitor-daily-spend.sh
date=$(date +%Y-%m-%d)
cost=$(redis-cli -n 5 HGET "tokens:global:$date" total_cost)

if (( $(echo "$cost > 10" | bc -l) )); then
  echo "WARNING: Daily token cost exceeds $10: \$$cost" | mail -s "Token Usage Alert" admin@example.com
fi
```

## Troubleshooting

### No usage data found
- Check JSONL file format
- Ensure each line is valid JSON
- Verify `message.usage` or `usage` field exists
- Check for empty lines

### Agent ID not detected
- Ensure filename follows pattern: `agent-{ID}.jsonl`
- Script will generate temporary ID if pattern not matched
- Manually specify agent ID in filename

### Model not detected
- Script defaults to 'sonnet' if model not found
- Check for `model` field in message or metadata
- Valid model identifiers: claude-opus, claude-sonnet, claude-haiku

### Redis connection failed
- Ensure Redis is running: `redis-cli -n 5 PING`
- Check Redis configuration
- Verify DB 5 is available

## Dependencies

- `jq` - JSON processor
- `redis-cli` - Redis command-line client
- `bc` - Basic calculator for cost calculations

Install missing dependencies:
```bash
apt-get install jq redis-tools bc
```
