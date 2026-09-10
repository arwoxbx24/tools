#!/usr/bin/env bash
# =============================================================================
# diagnostic-modules/firewall.sh — Firewall / port visibility module
# Sourced by diagnose-service.sh. Exports: run_module_firewall()
# Usage note: accepts optional PORT argument via MODULE_ARG_PORT env var
# =============================================================================

run_module_firewall() {
  local module_label="Firewall"
  local status="PASS"
  local detail=""
  local cause=""
  local fix=""

  # --- Check 1: UFW ---
  local ufw_status
  if command -v ufw >/dev/null 2>&1; then
    ufw_status=$(ufw status 2>/dev/null | head -1)
    local ufw_rules_count
    ufw_rules_count=$(ufw status 2>/dev/null | grep -cE "ALLOW|DENY|REJECT" || echo 0)
    detail="ufw=${ufw_status}, rules=${ufw_rules_count}"
    if echo "$ufw_status" | grep -qi "inactive"; then
      detail="ufw=inactive (no firewall active)"
    fi
  fi

  # --- Check 2: iptables snapshot ---
  local ipt_drop_count
  if command -v iptables >/dev/null 2>&1; then
    ipt_drop_count=$(iptables -L -n 2>/dev/null | grep -c "DROP\|REJECT" || echo 0)
    detail="${detail:+$detail, }iptables DROP/REJECT rules=${ipt_drop_count}"
  fi

  # --- Check 3: nftables ---
  local nft_status
  if command -v nft >/dev/null 2>&1; then
    local nft_rules
    nft_rules=$(nft list ruleset 2>/dev/null | grep -c "drop\|reject" || echo 0)
    nft_status="nft rules with drop/reject: ${nft_rules}"
    detail="${detail:+$detail, }nftables_blocks=${nft_rules}"
  fi

  # --- Check 4: What's listening (ss) ---
  local listening_ports
  if command -v ss >/dev/null 2>&1; then
    listening_ports=$(ss -tlnp 2>/dev/null | grep LISTEN | awk '{print $4}' | grep -oE ':[0-9]+$' | tr -d ':' | sort -n | tr '\n' ',' | sed 's/,$//')
    detail="${detail:+$detail, }listening=[${listening_ports:-none}]"
  fi

  # --- Check 5: Specific port test (if MODULE_ARG_PORT set) ---
  local target_port="${MODULE_ARG_PORT:-}"
  if [[ -n "$target_port" ]]; then
    local port_open
    if command -v nc >/dev/null 2>&1; then
      timeout 3 nc -z localhost "$target_port" 2>/dev/null && port_open="yes" || port_open="no"
    else
      timeout 3 curl -s --connect-timeout 2 "telnet://localhost:${target_port}" >/dev/null 2>&1 \
        && port_open="yes" || port_open="no"
    fi
    if [[ "$port_open" == "no" ]]; then
      status="WARN"
      cause="Port ${target_port} not responding on localhost"
      fix="Verify service is bound to 0.0.0.0:${target_port} (not 127.0.0.1 only); check ufw allow ${target_port}/tcp"
    else
      detail="${detail:+$detail, }port=${target_port}:OPEN"
    fi
  fi

  # --- Output ---
  if [[ -z "$detail" ]]; then
    detail="no firewall tooling found (ufw/iptables/nft)"
  fi

  if [[ "$status" == "PASS" ]]; then
    printf "[MODULE] %-14s ... \xE2\x9C\x85 PASS (%s)\n" "$module_label" "$detail"
  elif [[ "$status" == "WARN" ]]; then
    printf "[MODULE] %-14s ... \xE2\x9A\xA0 WARN (%s)\n" "$module_label" "$detail"
    [[ -n "$cause" ]] && printf "  ROOT CAUSE: %s\n" "$cause"
    [[ -n "$fix"  ]] && printf "  FIX: %s\n" "$fix"
  else
    printf "[MODULE] %-14s ... \xE2\x9D\x8C FAIL (%s)\n" "$module_label" "$detail"
    [[ -n "$cause" ]] && printf "  ROOT CAUSE: %s\n" "$cause"
    [[ -n "$fix"  ]] && printf "  FIX: %s\n" "$fix"
  fi

  return 0
}
