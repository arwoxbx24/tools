# v9 (dcfg-80rgm.6): CI не появился, но PR уже CONFLICTING -> 50 (конфликт), а не 30 (CI не появился).
# Доступны $d, $GH_TEST_DIR, ship, mkrepo, mkwt, p, f. Заглушка gh отдаёт mergeable: UNKNOWN на первом вызове, CONFLICTING дальше.
mkrepo v9a 1; w=$(mkwt v9a claude/v9a); printf 'v9a\n' >> "$w/f.txt"
cp -p "$d/bin/gh" "$d/bin/gh.real"
cat > "$d/bin/gh" <<'V9GH'
#!/usr/bin/env bash
if [[ $1:$2 == pr:view && " $* " == *' --json mergeable '* ]]; then
	n=$(cat "$GH_TEST_DIR/mergeable-n" 2>/dev/null || echo 0); echo $((n + 1)) > "$GH_TEST_DIR/mergeable-n"
	(( n == 0 )) && echo UNKNOWN || echo CONFLICTING; exit 0
fi
exec "$GH_TEST_DIR/bin/gh.real" "$@"
V9GH
chmod +x "$d/bin/gh"
printf '[]\n' > "$d/runs-pr"; : > "$d/bucket"; rm -f "$d/mergeable-n"
GA_CI_APPEAR=0 GA_CI_POLL=0 ship "$w" >/dev/null 2>"$d/v9a.err"; rc=$?
err=$(<"$d/v9a.err")
rm -f "$d/runs-pr" "$d/bucket" "$d/mergeable-n"
[[ $rc == 50 && $err == *'конфликтует'* ]] && p v9a || f v9a "rc=$rc: $err"
