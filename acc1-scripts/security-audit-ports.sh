#!/bin/bash
# Security Audit: Exposed Services Checker
# Scans listening ports and checks for unauthenticated access

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
DOMAIN=""
OUTPUT_JSON=0
VERBOSE=0
TIMEOUT=3

# Known admin panel paths to check
ADMIN_PATHS=(
    "/control/"
    "/admin/"
    "/api/"
    "/dashboard/"
    "/panel/"
    "/manage/"
    "/console/"
    "/phpmyadmin/"
    "/adminer/"
    "/wp-admin/"
    "/.env"
    "/config/"
    "/server-status"
)

# Usage information
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Options:
    --domain DOMAIN     Check specific domain's subdomains
    --json              Output results in JSON format
    --verbose           Show detailed checking process
    --timeout SECONDS   Connection timeout (default: 3)
    -h, --help          Show this help message

Exit codes:
    0 - All services protected
    1 - Vulnerable services found
    2 - Error during execution
EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --json)
            OUTPUT_JSON=1
            shift
            ;;
        --verbose)
            VERBOSE=1
            shift
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Check if running as root (needed for full process info)
if [[ $EUID -ne 0 ]] && [[ $VERBOSE -eq 1 ]]; then
    echo -e "${YELLOW}Warning: Not running as root. Process information may be limited.${NC}" >&2
fi

# Initialize results
declare -a RESULTS=()
VULNERABLE_COUNT=0
PROTECTED_COUNT=0

# Log function
log_verbose() {
    if [[ $VERBOSE -eq 1 ]] && [[ $OUTPUT_JSON -eq 0 ]]; then
        echo -e "$@" >&2
    fi
}

# Check if a port is accessible without authentication
check_port_security() {
    local ip=$1
    local port=$2
    local process=$3

    # Skip localhost-only bindings
    if [[ "$ip" == "127.0.0.1" ]] || [[ "$ip" == "::1" ]]; then
        log_verbose "${GREEN}✓${NC} Port $port bound to localhost only (SAFE)"
        return 0
    fi

    log_verbose "Checking port $port ($process)..."

    local vulnerable=0
    local exposed_endpoints=()
    local status_code=""

    # Determine protocol (try HTTPS first for common secure ports)
    local protocols=("http")
    if [[ $port -eq 443 ]] || [[ $port -eq 8443 ]] || [[ $port -eq 20443 ]]; then
        protocols=("https" "http")
    fi

    for protocol in "${protocols[@]}"; do
        # Check root endpoint
        local url="${protocol}://127.0.0.1:${port}/"
        status_code=$(curl -s -o /dev/null -w "%{http_code}" \
            --connect-timeout "$TIMEOUT" \
            --max-time "$TIMEOUT" \
            -k "$url" 2>/dev/null || echo "000")

        if [[ "$status_code" != "000" ]]; then
            log_verbose "  ${protocol}:// - Status: $status_code"

            # 200 OK without auth is vulnerable
            if [[ "$status_code" == "200" ]]; then
                vulnerable=1
                exposed_endpoints+=("/ (HTTP $status_code)")
            fi

            # Check admin paths
            for path in "${ADMIN_PATHS[@]}"; do
                local admin_url="${protocol}://127.0.0.1:${port}${path}"
                local admin_status=$(curl -s -o /dev/null -w "%{http_code}" \
                    --connect-timeout "$TIMEOUT" \
                    --max-time "$TIMEOUT" \
                    -k "$admin_url" 2>/dev/null || echo "000")

                if [[ "$admin_status" == "200" ]]; then
                    vulnerable=1
                    exposed_endpoints+=("${path} (HTTP $admin_status)")
                    log_verbose "  ${RED}✗${NC} Admin panel accessible: $path"
                elif [[ "$admin_status" != "000" ]] && [[ "$admin_status" != "404" ]]; then
                    log_verbose "  ${YELLOW}!${NC} Admin path exists: $path (HTTP $admin_status)"
                fi
            done

            # Found working protocol, no need to try others
            break
        fi
    done

    # Prepare result
    local endpoints_json=""
    if [[ ${#exposed_endpoints[@]} -gt 0 ]]; then
        endpoints_json=$(printf ',"%s"' "${exposed_endpoints[@]}")
        endpoints_json="[${endpoints_json:1}]"
    else
        endpoints_json="[]"
    fi

    if [[ $vulnerable -eq 1 ]]; then
        RESULTS+=("{\"port\":$port,\"ip\":\"$ip\",\"process\":\"$process\",\"status\":\"VULNERABLE\",\"exposed_endpoints\":$endpoints_json}")
        VULNERABLE_COUNT=$((VULNERABLE_COUNT + 1))
        log_verbose "${RED}✗ VULNERABLE${NC}: Port $port is accessible without authentication"
    else
        RESULTS+=("{\"port\":$port,\"ip\":\"$ip\",\"process\":\"$process\",\"status\":\"PROTECTED\",\"exposed_endpoints\":$endpoints_json}")
        PROTECTED_COUNT=$((PROTECTED_COUNT + 1))
        log_verbose "${GREEN}✓ PROTECTED${NC}: Port $port requires authentication or is not HTTP"
    fi
}

# Get listening ports
get_listening_ports() {
    log_verbose "\nScanning listening TCP ports..."

    # Parse ss output
    # Format: State Recv-Q Send-Q Local Address:Port Peer Address:Port Process
    while IFS= read -r line; do
        # Skip header
        [[ "$line" =~ ^State ]] && continue

        # Extract IP and port
        local local_addr=$(echo "$line" | awk '{print $4}')
        local ip=$(echo "$local_addr" | sed 's/:\([^:]*\)$//' | sed 's/^\[//' | sed 's/\]$//')
        local port=$(echo "$local_addr" | sed 's/.*://')

        # Extract process info
        local process=$(echo "$line" | awk -F'users:' '{print $2}' | sed 's/[()"]*//g' | awk '{print $1}' | head -n1)
        [[ -z "$process" ]] && process="unknown"

        # Check if port is numeric
        if [[ "$port" =~ ^[0-9]+$ ]]; then
            check_port_security "$ip" "$port" "$process"
        fi
    done < <(ss -tlnp 2>/dev/null || ss -tln)
}

# Check domain subdomains (if specified)
check_domain_subdomains() {
    if [[ -z "$DOMAIN" ]]; then
        return
    fi

    log_verbose "\nChecking domain: $DOMAIN"

    # Common subdomains to check
    local subdomains=(
        "www"
        "admin"
        "api"
        "panel"
        "control"
        "manage"
        "dashboard"
        "cpanel"
        "webmail"
        "mail"
        "ftp"
        "ssh"
    )

    for sub in "${subdomains[@]}"; do
        local full_domain="${sub}.${DOMAIN}"
        log_verbose "Checking ${full_domain}..."

        # Try to resolve
        if host "$full_domain" >/dev/null 2>&1; then
            # Check HTTP
            for protocol in "http" "https"; do
                local url="${protocol}://${full_domain}/"
                local status=$(curl -s -o /dev/null -w "%{http_code}" \
                    --connect-timeout "$TIMEOUT" \
                    --max-time "$TIMEOUT" \
                    -k "$url" 2>/dev/null || echo "000")

                if [[ "$status" == "200" ]]; then
                    log_verbose "  ${RED}✗${NC} Accessible: $url"
                    RESULTS+=("{\"domain\":\"$full_domain\",\"protocol\":\"$protocol\",\"status\":\"ACCESSIBLE\",\"http_code\":$status}")
                    VULNERABLE_COUNT=$((VULNERABLE_COUNT + 1))
                elif [[ "$status" != "000" ]]; then
                    log_verbose "  ${YELLOW}!${NC} Responds: $url (HTTP $status)"
                fi
            done
        fi
    done
}

# Main execution
main() {
    log_verbose "${YELLOW}=== Security Audit: Exposed Services ===${NC}\n"

    # Check listening ports
    get_listening_ports

    # Check domain if specified
    check_domain_subdomains

    # Output results
    if [[ $OUTPUT_JSON -eq 1 ]]; then
        # JSON output
        local results_json=$(printf ',%s' "${RESULTS[@]}")
        results_json="[${results_json:1}]"

        cat << EOF
{
    "scan_time": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "total_services": $((VULNERABLE_COUNT + PROTECTED_COUNT)),
    "vulnerable_count": $VULNERABLE_COUNT,
    "protected_count": $PROTECTED_COUNT,
    "results": $results_json
}
EOF
    else
        # Human-readable output
        echo ""
        echo "=== Security Audit Summary ==="
        echo "Total services checked: $((VULNERABLE_COUNT + PROTECTED_COUNT))"
        echo -e "${GREEN}Protected: $PROTECTED_COUNT${NC}"
        echo -e "${RED}Vulnerable: $VULNERABLE_COUNT${NC}"

        if [[ $VULNERABLE_COUNT -gt 0 ]]; then
            echo ""
            echo -e "${RED}⚠ VULNERABLE SERVICES FOUND!${NC}"
            echo "Review the services marked as VULNERABLE above."
        else
            echo ""
            echo -e "${GREEN}✓ All services are properly protected.${NC}"
        fi
    fi

    # Exit with appropriate code
    if [[ $VULNERABLE_COUNT -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

# Run main function
main
