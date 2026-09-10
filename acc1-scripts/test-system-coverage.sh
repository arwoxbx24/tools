#!/bin/bash
PROFILE="${1:-/root/workspaces/tools/acc1-scripts}"
SCORE=0

echo "=========================================="
echo "  FINAL SYSTEM TEST"
echo "=========================================="
echo ""

# TEST 1: Identity (fixed case sensitivity)
grep -qi "Engineer\|Executor\|Builder" "$PROFILE/CLAUDE.md" && \
grep -qi "action over discussion" "$PROFILE/CLAUDE.md" && \
echo "✅ TEST 1: Identity PASS" && ((SCORE++)) || echo "❌ TEST 1: Identity FAIL"

# TEST 2: Memory
[ -f "$PROFILE/skills/task-memory.md" ] && \
grep -q "gh issue create" "$PROFILE/skills/task-memory.md" && \
echo "✅ TEST 2: Memory PASS" && ((SCORE++)) || echo "❌ TEST 2: Memory FAIL"

# TEST 3: Autonomy (UPDATED PORT RANGE 20000-65000)
grep -q "20000-65000" "$PROFILE/CLAUDE.md" && \
grep -q "Maximum questions: 3" "$PROFILE/CLAUDE.md" && \
echo "✅ TEST 3: Autonomy PASS" && ((SCORE++)) || echo "❌ TEST 3: Autonomy FAIL"

# TEST 4: Subagents
grep -q "25x cheaper" "$PROFILE/CLAUDE.md" && \
echo "✅ TEST 4: Subagents PASS" && ((SCORE++)) || echo "❌ TEST 4: Subagents FAIL"

# TEST 5: Disagreement
grep -q "Disagree when needed" "$PROFILE/CLAUDE.md" && \
grep -q "No emotional validation" "$PROFILE/CLAUDE.md" && \
echo "✅ TEST 5: Disagreement PASS" && ((SCORE++)) || echo "❌ TEST 5: Disagreement FAIL"

# TEST 6: Checkpoints
grep -q "NEVER patch broken" "$PROFILE/CLAUDE.md" && \
echo "✅ TEST 6: Checkpoints PASS" && ((SCORE++)) || echo "❌ TEST 6: Checkpoints FAIL"

# TEST 7: Security
[ -f "$PROFILE/skills/security.md" ] && \
grep -q "Zero hardcoded secrets" "$PROFILE/CLAUDE.md" && \
echo "✅ TEST 7: Security PASS" && ((SCORE++)) || echo "❌ TEST 7: Security FAIL"

# TEST 8: Skills
SKILLS_COUNT=$(find "$PROFILE/skills" -name "*.md" -type f 2>/dev/null | wc -l)
[ $SKILLS_COUNT -ge 7 ] && \
echo "✅ TEST 8: Skills PASS ($SKILLS_COUNT/7)" && ((SCORE++)) || echo "❌ TEST 8: Skills FAIL ($SKILLS_COUNT/7)"

# TEST 9: Working Directory
grep -q "/root/claude-projects/task-" "$PROFILE/CLAUDE.md" && \
grep -q "NEVER pollute" "$PROFILE/CLAUDE.md" && \
echo "✅ TEST 9: Working Directory PASS" && ((SCORE++)) || echo "❌ TEST 9: Working Directory FAIL"

# TEST 10: Communication
grep -q "No time estimates" "$PROFILE/CLAUDE.md" && \
grep -qi "AI cannot estimate" "$PROFILE/CLAUDE.md" && \
echo "✅ TEST 10: Communication PASS" && ((SCORE++)) || echo "❌ TEST 10: Communication FAIL"

# BONUS: Commands system
COMMANDS_COUNT=$(find "$PROFILE/commands" -name "*.md" ! -name "README.md" -type f 2>/dev/null | wc -l)
echo ""
echo "=========================================="
echo "  BONUS CHECKS"
echo "=========================================="
[ $COMMANDS_COUNT -ge 7 ] && \
echo "✅ BONUS: Commands system ($COMMANDS_COUNT commands)" || echo "⚠️  BONUS: Commands incomplete ($COMMANDS_COUNT/7)"

grep -q "/tasks\|/status\|/checkpoint" "$PROFILE/CLAUDE.md" && \
echo "✅ BONUS: Commands documented in CLAUDE.md" || echo "⚠️  BONUS: Commands not documented"

echo ""
echo "=========================================="
echo "  FINAL SCORE: $SCORE/10"
echo "=========================================="
[ $SCORE -ge 8 ] && echo "✅ SYSTEM READY FOR PRODUCTION" || echo "❌ SYSTEM NOT READY"
