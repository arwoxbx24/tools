#!/bin/bash
# PAUTINA Web Integrity System - Web Visualization Generator
# Generates HTML visualization with D3.js showing dependency graph
# CLAUDE.md as gold center node, green=valid, red=orphans/broken

# Note: set -e removed to avoid issues with empty arrays and arithmetic

# Configuration
[[ -z "$HOME" ]] && HOME="/root"
PROFILE_DIR="/root/workspaces/tools/acc1-scripts"
REFERENCE_DIR="${PROFILE_DIR}/reference"
OPERATIONS_DIR="${PROFILE_DIR}/operations"
OUTPUT_DIR="/root/claude-projects/.tmp"
OUTPUT_FILE="${OUTPUT_DIR}/pautina-web.html"

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

# Colors for output
GREEN='\033[0;32m'
GOLD='\033[0;33m'
NC='\033[0m'

echo -e "${GOLD}PAUTINA Web Visualization Generator${NC}"
echo "====================================="

# Extract INTEGRITY metadata from a file
extract_parent() {
    local file="$1"
    local content
    content=$(cat "$file" 2>/dev/null || echo "")

    local integrity_block
    integrity_block=$(echo "$content" | sed -n '/<!-- INTEGRITY/,/-->/p' 2>/dev/null)

    if [[ -z "$integrity_block" ]]; then
        echo ""
        return
    fi

    local parent
    parent=$(echo "$integrity_block" | grep -oP 'PARENT:\s*\K[^\s]+' 2>/dev/null | head -1)
    echo "$parent"
}

# Resolve parent to a node ID
resolve_parent_id() {
    local parent="$1"

    if [[ "$parent" == "CLAUDE.md" ]]; then
        echo "CLAUDE.md"
        return
    fi

    # Try reference/
    if [[ -f "${REFERENCE_DIR}/${parent}" ]]; then
        echo "reference/${parent}"
        return
    fi

    # Try operations/
    if [[ -f "${OPERATIONS_DIR}/${parent}" ]]; then
        echo "operations/${parent}"
        return
    fi

    echo ""
}

# Build nodes and links arrays
declare -a NODES
declare -a LINKS
declare -A NODE_STATUS  # valid, orphan, broken

# Add root node
NODES+=("{\"id\": \"CLAUDE.md\", \"label\": \"CLAUDE.md\", \"type\": \"root\"}")
NODE_STATUS["CLAUDE.md"]="root"

echo "Scanning files..."

# Scan reference directory
if [[ -d "$REFERENCE_DIR" ]]; then
    while IFS= read -r -d '' file; do
        filename=$(basename "$file")

        # Skip README, CHANGELOG
        if [[ "$filename" == "README.md" || "$filename" == "CHANGELOG.md" || "$filename" == "00-README.md" ]]; then
            continue
        fi

        node_id="reference/${filename}"
        parent=$(extract_parent "$file")

        if [[ -z "$parent" ]]; then
            # No INTEGRITY block - orphan
            NODES+=("{\"id\": \"${node_id}\", \"label\": \"${filename}\", \"type\": \"orphan\"}")
            NODE_STATUS["$node_id"]="orphan"
        else
            parent_id=$(resolve_parent_id "$parent")
            if [[ -z "$parent_id" ]]; then
                # Broken link
                NODES+=("{\"id\": \"${node_id}\", \"label\": \"${filename}\", \"type\": \"broken\"}")
                NODE_STATUS["$node_id"]="broken"
            else
                # Valid connection
                NODES+=("{\"id\": \"${node_id}\", \"label\": \"${filename}\", \"type\": \"valid\"}")
                NODE_STATUS["$node_id"]="valid"
                LINKS+=("{\"source\": \"${node_id}\", \"target\": \"${parent_id}\"}")
            fi
        fi
    done < <(find -L "$REFERENCE_DIR" -maxdepth 1 -name "*.md" -type f -print0 2>/dev/null)
fi

# Scan operations directory
if [[ -d "$OPERATIONS_DIR" ]]; then
    while IFS= read -r -d '' file; do
        filename=$(basename "$file")

        # Skip README, CHANGELOG
        if [[ "$filename" == "README.md" || "$filename" == "CHANGELOG.md" || "$filename" == "00-README.md" ]]; then
            continue
        fi

        node_id="operations/${filename}"
        parent=$(extract_parent "$file")

        if [[ -z "$parent" ]]; then
            # No INTEGRITY block - orphan
            NODES+=("{\"id\": \"${node_id}\", \"label\": \"${filename}\", \"type\": \"orphan\"}")
            NODE_STATUS["$node_id"]="orphan"
        else
            parent_id=$(resolve_parent_id "$parent")
            if [[ -z "$parent_id" ]]; then
                # Broken link
                NODES+=("{\"id\": \"${node_id}\", \"label\": \"${filename}\", \"type\": \"broken\"}")
                NODE_STATUS["$node_id"]="broken"
            else
                # Valid connection
                NODES+=("{\"id\": \"${node_id}\", \"label\": \"${filename}\", \"type\": \"valid\"}")
                NODE_STATUS["$node_id"]="valid"
                LINKS+=("{\"source\": \"${node_id}\", \"target\": \"${parent_id}\"}")
            fi
        fi
    done < <(find -L "$OPERATIONS_DIR" -maxdepth 1 -name "*.md" -type f -print0 2>/dev/null)
fi

# Build JSON arrays
NODES_JSON=$(printf '%s\n' "${NODES[@]}" | paste -sd ',' -)
LINKS_JSON=$(printf '%s\n' "${LINKS[@]}" | paste -sd ',' -)

# Count statistics
VALID_COUNT=0
ORPHAN_COUNT=0
BROKEN_COUNT=0

for status in "${NODE_STATUS[@]}"; do
    case "$status" in
        valid) ((VALID_COUNT++)) ;;
        orphan) ((ORPHAN_COUNT++)) ;;
        broken) ((BROKEN_COUNT++)) ;;
    esac
done

echo "  Valid nodes: $VALID_COUNT"
echo "  Orphan nodes: $ORPHAN_COUNT"
echo "  Broken links: $BROKEN_COUNT"
echo ""

# Generate HTML
cat > "$OUTPUT_FILE" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PAUTINA Web Integrity Visualization</title>
    <script src="https://d3js.org/d3.v7.min.js"></script>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #1a1a2e;
            color: #eee;
            overflow: hidden;
        }
        #header {
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            padding: 15px 20px;
            background: rgba(26, 26, 46, 0.95);
            border-bottom: 1px solid #333;
            z-index: 100;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        h1 {
            color: #ffd700;
            font-size: 1.5em;
        }
        #stats {
            display: flex;
            gap: 20px;
        }
        .stat {
            padding: 5px 15px;
            border-radius: 5px;
            font-size: 0.9em;
        }
        .stat-valid { background: rgba(76, 175, 80, 0.3); color: #4CAF50; }
        .stat-orphan { background: rgba(244, 67, 54, 0.3); color: #F44336; }
        .stat-broken { background: rgba(255, 152, 0, 0.3); color: #FF9800; }
        #graph {
            width: 100vw;
            height: 100vh;
            padding-top: 60px;
        }
        .node {
            cursor: pointer;
        }
        .node-root {
            fill: #ffd700;
            stroke: #fff;
            stroke-width: 3px;
        }
        .node-valid {
            fill: #4CAF50;
            stroke: #2E7D32;
            stroke-width: 2px;
        }
        .node-orphan {
            fill: #F44336;
            stroke: #C62828;
            stroke-width: 2px;
        }
        .node-broken {
            fill: #FF9800;
            stroke: #EF6C00;
            stroke-width: 2px;
        }
        .link {
            stroke: #4CAF50;
            stroke-opacity: 0.6;
            stroke-width: 1.5px;
        }
        .link-broken {
            stroke: #F44336;
            stroke-dasharray: 5, 5;
        }
        .label {
            font-size: 10px;
            fill: #ddd;
            pointer-events: none;
            text-anchor: middle;
        }
        .label-root {
            font-size: 14px;
            font-weight: bold;
            fill: #ffd700;
        }
        #tooltip {
            position: absolute;
            background: rgba(0, 0, 0, 0.9);
            border: 1px solid #444;
            border-radius: 5px;
            padding: 10px;
            font-size: 12px;
            pointer-events: none;
            display: none;
            z-index: 200;
        }
        #legend {
            position: fixed;
            bottom: 20px;
            left: 20px;
            background: rgba(26, 26, 46, 0.95);
            border: 1px solid #333;
            border-radius: 5px;
            padding: 15px;
        }
        .legend-item {
            display: flex;
            align-items: center;
            margin: 5px 0;
        }
        .legend-circle {
            width: 12px;
            height: 12px;
            border-radius: 50%;
            margin-right: 10px;
        }
    </style>
</head>
<body>
    <div id="header">
        <h1>PAUTINA Web Integrity</h1>
        <div id="stats">
            <span class="stat stat-valid">Valid: <span id="count-valid">0</span></span>
            <span class="stat stat-orphan">Orphans: <span id="count-orphan">0</span></span>
            <span class="stat stat-broken">Broken: <span id="count-broken">0</span></span>
        </div>
    </div>

    <div id="graph"></div>

    <div id="tooltip"></div>

    <div id="legend">
        <div class="legend-item">
            <div class="legend-circle" style="background: #ffd700;"></div>
            <span>CLAUDE.md (Root)</span>
        </div>
        <div class="legend-item">
            <div class="legend-circle" style="background: #4CAF50;"></div>
            <span>Valid Connection</span>
        </div>
        <div class="legend-item">
            <div class="legend-circle" style="background: #F44336;"></div>
            <span>Orphan (No INTEGRITY)</span>
        </div>
        <div class="legend-item">
            <div class="legend-circle" style="background: #FF9800;"></div>
            <span>Broken Link</span>
        </div>
    </div>

    <script>
        // Data will be injected here
        const graphData = {
            nodes: [__NODES__],
            links: [__LINKS__]
        };

        // Update stats
        const counts = { valid: 0, orphan: 0, broken: 0 };
        graphData.nodes.forEach(n => {
            if (n.type === 'valid') counts.valid++;
            else if (n.type === 'orphan') counts.orphan++;
            else if (n.type === 'broken') counts.broken++;
        });
        document.getElementById('count-valid').textContent = counts.valid;
        document.getElementById('count-orphan').textContent = counts.orphan;
        document.getElementById('count-broken').textContent = counts.broken;

        // SVG setup
        const width = window.innerWidth;
        const height = window.innerHeight;

        const svg = d3.select('#graph')
            .append('svg')
            .attr('width', width)
            .attr('height', height);

        // Zoom behavior
        const g = svg.append('g');
        svg.call(d3.zoom()
            .scaleExtent([0.1, 4])
            .on('zoom', (event) => g.attr('transform', event.transform)));

        // Force simulation
        const simulation = d3.forceSimulation(graphData.nodes)
            .force('link', d3.forceLink(graphData.links).id(d => d.id).distance(100))
            .force('charge', d3.forceManyBody().strength(-300))
            .force('center', d3.forceCenter(width / 2, height / 2))
            .force('collision', d3.forceCollide().radius(40));

        // Links
        const link = g.append('g')
            .selectAll('line')
            .data(graphData.links)
            .join('line')
            .attr('class', 'link');

        // Nodes
        const node = g.append('g')
            .selectAll('circle')
            .data(graphData.nodes)
            .join('circle')
            .attr('class', d => `node node-${d.type}`)
            .attr('r', d => d.type === 'root' ? 25 : 12)
            .call(d3.drag()
                .on('start', dragstarted)
                .on('drag', dragged)
                .on('end', dragended));

        // Labels
        const label = g.append('g')
            .selectAll('text')
            .data(graphData.nodes)
            .join('text')
            .attr('class', d => d.type === 'root' ? 'label label-root' : 'label')
            .attr('dy', d => d.type === 'root' ? 40 : 25)
            .text(d => d.label);

        // Tooltip
        const tooltip = d3.select('#tooltip');

        node.on('mouseover', (event, d) => {
            tooltip
                .style('display', 'block')
                .style('left', (event.pageX + 10) + 'px')
                .style('top', (event.pageY + 10) + 'px')
                .html(`<strong>${d.label}</strong><br>Type: ${d.type}<br>ID: ${d.id}`);
        })
        .on('mouseout', () => tooltip.style('display', 'none'));

        // Simulation tick
        simulation.on('tick', () => {
            link
                .attr('x1', d => d.source.x)
                .attr('y1', d => d.source.y)
                .attr('x2', d => d.target.x)
                .attr('y2', d => d.target.y);

            node
                .attr('cx', d => d.x)
                .attr('cy', d => d.y);

            label
                .attr('x', d => d.x)
                .attr('y', d => d.y);
        });

        // Drag functions
        function dragstarted(event) {
            if (!event.active) simulation.alphaTarget(0.3).restart();
            event.subject.fx = event.subject.x;
            event.subject.fy = event.subject.y;
        }

        function dragged(event) {
            event.subject.fx = event.x;
            event.subject.fy = event.y;
        }

        function dragended(event) {
            if (!event.active) simulation.alphaTarget(0);
            event.subject.fx = null;
            event.subject.fy = null;
        }
    </script>
</body>
</html>
HTMLEOF

# Inject data into HTML using awk (handles special chars better than sed)
# Write JSON data to temp files
NODES_TMP=$(mktemp)
LINKS_TMP=$(mktemp)
echo "$NODES_JSON" > "$NODES_TMP"
echo "$LINKS_JSON" > "$LINKS_TMP"

# Use awk to replace placeholders
awk -v nodes_file="$NODES_TMP" -v links_file="$LINKS_TMP" '
{
    if (/__NODES__/) {
        getline nodes < nodes_file
        gsub(/__NODES__/, nodes)
    }
    if (/__LINKS__/) {
        getline links < links_file
        gsub(/__LINKS__/, links)
    }
    print
}' "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"

# Cleanup temp files
rm -f "$NODES_TMP" "$LINKS_TMP"

echo -e "${GREEN}Visualization generated: ${OUTPUT_FILE}${NC}"
echo ""
echo "Open in browser to view the dependency graph."
