# 44 (ADR-25): one без CI auto-merge только непустой all-.md diff; mixed остаётся wait-owner.
mkrepo r44docs; w44docs=$(mkwt r44docs claude/z44docs); printf 'docs\n' > "$w44docs/README.md"
: > "$GH_JOURNAL"; rm -f "$GH_CREATED"
out_docs=$(ship "$w44docs" 2>&1); rc_docs=$?
grep -q '^pr merge' "$GH_JOURNAL"; merge_docs=$?
ci_wait_docs=$(grep -c '^run list' "$GH_JOURNAL" || true)

mkrepo r44mixed; w44mixed=$(mkwt r44mixed claude/z44mixed)
printf 'docs\n' > "$w44mixed/README.md"; printf 'runtime\n' > "$w44mixed/x.sh"
: > "$GH_JOURNAL"; rm -f "$GH_CREATED"
out_mixed=$(ship "$w44mixed" 2>&1); rc_mixed=$?
grep -q '^pr merge' "$GH_JOURNAL"; merge_mixed=$?

[[ $rc_docs == 0 && $out_docs == *'gate:auto docs-only'* && $out_docs != *'prod:wait-owner'* \
	&& $merge_docs == 0 && $ci_wait_docs == 0 && $rc_mixed == 0 \
	&& $out_mixed == *'prod:wait-owner no-ci'* && $merge_mixed != 0 ]] && p 44 || f 44
