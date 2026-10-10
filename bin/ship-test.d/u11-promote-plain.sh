# U11 (spec:099 v5): plain переносит открытый PR только на dev-ready SHA.

cat > "$d/bin/bd" <<'EOF'
#!/usr/bin/env bash
printf 'bd %s\n' "$*" >> "$GH_TEST_DIR/bd.log"
[[ ${1:-} == show && ${3:-} == --json ]] && printf '[{"status":"%s","notes":"%s"}]\n' "$(cat "$GH_TEST_DIR/u11-status" 2>/dev/null || echo open)" "$(cat "$GH_TEST_DIR/u11-notes" 2>/dev/null || echo '')"
exit 0
EOF
chmod +x "$d/bin/bd"

cat > "$d/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_JOURNAL"
case $1:$2 in
	pr:list)
		[[ -f "$GH_TEST_DIR/u11-no-pr" ]] && exit 0
		printf '{"number":17,"headRefName":"%s","headRefOid":"%s","title":"%s"}\n' \
			"$(cat "$GH_TEST_DIR/u11-head")" "$(cat "$GH_TEST_DIR/u11-head-oid")" "$(cat "$GH_TEST_DIR/u11-title")" ;;
	pr:merge)
		sha=$(cat "$GH_TEST_DIR/u11-head-oid")
		[[ " $* " == *" --match-head-commit $sha "* ]] || exit 1
		origin=$(git -C "$PWD" config remote.origin.url)
		head=$(cat "$GH_TEST_DIR/u11-head")
		prod=$(cat "$GH_TEST_DIR/u11-prod")
		tmp=$(mktemp -d "$GH_TEST_DIR/u11-merge.XXXXXX")
		git clone -q "$origin" "$tmp" && git -C "$tmp" config user.email t@t \
			&& git -C "$tmp" config user.name t \
			&& git -C "$tmp" fetch -q origin "refs/heads/$head:refs/remotes/origin/$head" \
			&& git -C "$tmp" checkout -q -B "$prod" "origin/$prod" \
			&& git -C "$tmp" merge --squash "origin/$head" \
			&& git -C "$tmp" commit -q -m squash \
			&& git -C "$tmp" push -q origin "HEAD:refs/heads/$prod" \
			&& git -C "$tmp" rev-parse HEAD > "$GH_TEST_DIR/u11-merge-sha" || exit 1 ;;
	pr:view) cat "$GH_TEST_DIR/u11-merge-sha" ;;
	run:list) printf '[{"status":"completed","conclusion":"success"}]\n' ;;
esac
EOF
chmod +x "$d/bin/gh"

u11_repo(){ # <name> — one-branch PR and its independently verified dev SHA
	local n=$1 w head sha
	mkrepo "$n"
	w="$GA_WT_ROOT/claude/$n"
	head="claude/$n"
	git -C "$GA_PROJECTS/$n" worktree add -q -b "$head" "$w" origin/main
	printf '%s\n' "$n" > "$w/u11.txt"
	git -C "$w" add u11.txt
	git -C "$w" commit -q -m u11
	git -C "$w" push -q -u origin "$head"
	git -C "$GA_PROJECTS/$n" fetch -q origin
	sha=$(git -C "$w" rev-parse HEAD)
	git -C "$GA_PROJECTS/$n" update-ref "refs/dev-ready/$head" "$sha"
	printf '%s\n' "$head" > "$d/u11-head"
	printf '%s\n' "$sha" > "$d/u11-head-oid"
	printf '%s: plain\n' "$atom" > "$d/u11-title"
	printf 'main\n' > "$d/u11-prod"
}

u11_merges(){ grep -c '^pr merge' "$GH_JOURNAL" 2>/dev/null || true; }

# u11-1: plain открытый PR со ссылкой dev-ready переносится только на этот SHA.
u11_repo u11plain
: > "$GH_JOURNAL"; : > "$d/bd.log"; rm -f "$d/u11-status" "$d/u11-notes"
( cd "$GA_PROJECTS/u11plain" && "$bin/ship-promote" "$GA_PROJECTS/u11plain" --atom "$atom" --quote 'цитата U11' ) 2>"$d/u111.err" >/dev/null; rc=$?
sha=$(<"$d/u11-head-oid"); merge_sha=$(<"$d/u11-merge-sha")
grep -Fq "pr merge 17 -R - --squash --match-head-commit $sha" "$GH_JOURNAL" && merge_ok=1 || merge_ok=0
grep -Fq "promote: $merge_sha pr=17 dev=$sha quote=цитата U11" "$d/bd.log" && note_ok=1 || note_ok=0
[[ $rc == 0 && $merge_ok == 1 && $note_ok == 1 && $(<"$d/bd.log") == *close* ]] && p u11-1 || f u11-1

# u11-2: closed допустим в mode one; закрытый атом повторно не закрывается.
u11_repo u11closed
: > "$GH_JOURNAL"; : > "$d/bd.log"; printf 'closed\n' > "$d/u11-status"; rm -f "$d/u11-notes"
( cd "$GA_PROJECTS/u11closed" && "$bin/ship-promote" "$GA_PROJECTS/u11closed" --atom "$atom" --quote 'цитата U11' ) 2>"$d/u112.err" >/dev/null; rc=$?
grep -q '^bd close' "$d/bd.log"; close_rc=$?
[[ $rc == 0 && $close_rc != 0 ]] && p u11-2 || f u11-2

# u11-3: dev-ready SHA отличается от head PR — merge не вызывается.
u11_repo u11sha
head=$(<"$d/u11-head")
wrong=$(git -C "$GA_PROJECTS/u11sha" rev-parse origin/main)
git -C "$GA_PROJECTS/u11sha" update-ref "refs/dev-ready/$head" "$wrong"
: > "$GH_JOURNAL"; rm -f "$d/u11-status" "$d/u11-notes"
( cd "$GA_PROJECTS/u11sha" && "$bin/ship-promote" "$GA_PROJECTS/u11sha" --atom "$atom" --quote 'цитата U11' ) 2>"$d/u113.err" >/dev/null; rc=$?
[[ $rc == 50 && $(<"$d/u113.err") == *'SHA PR не тот, что проверен в dev'* && $(u11_merges) == 0 ]] && p u11-3 || f u11-3

# u11-4: у atom нет открытого PR.
u11_repo u11none
: > "$GH_JOURNAL"; : > "$d/u11-no-pr"; rm -f "$d/u11-status" "$d/u11-notes"
( cd "$GA_PROJECTS/u11none" && "$bin/ship-promote" "$GA_PROJECTS/u11none" --atom "$atom" --quote 'цитата U11' ) 2>"$d/u114.err" >/dev/null; rc=$?
rm -f "$d/u11-no-pr"
[[ $rc == 10 && $(<"$d/u114.err") == *'у атома нет открытого PR'* && $(u11_merges) == 0 ]] && p u11-4 || f u11-4

# u11-5: пустая цитата не вызывает gh.
: > "$GH_JOURNAL"
( cd "$GA_PROJECTS/u11none" && "$bin/ship-promote" "$GA_PROJECTS/u11none" --atom "$atom" --quote '' ) 2>"$d/u115.err" >/dev/null; rc=$?
[[ $rc == 10 && ! -s "$GH_JOURNAL" ]] && p u11-5 || f u11-5

# u11-6: guarded one-branch — prod-hold, без GitHub.
[[ -e "$GA_PROJECTS/stroyremont/.git" ]] || mkrepo stroyremont
: > "$GH_JOURNAL"; rm -f "$d/u11-status" "$d/u11-notes"
( cd "$GA_PROJECTS/stroyremont" && "$bin/ship-promote" "$GA_PROJECTS/stroyremont" --atom "$atom" --quote 'цитата U11' ) 2>"$d/u116.err" >/dev/null; rc=$?
[[ $rc == 0 && $(<"$d/u116.err") == *'prod:hold guarded allowlist'* && ! -s "$GH_JOURNAL" ]] && p u11-6 || f u11-6

# u11-7: guarded repository with origin/dev becomes staged and uses existing promote().
sr="$GA_PROJECTS/stroyremont"
git -C "$sr" branch dev origin/main
git -C "$sr" checkout -q dev
printf 'staged\n' > "$sr/u11-staged.txt"
git -C "$sr" add u11-staged.txt
git -C "$sr" commit -q -m u11-staged
staged_sha=$(git -C "$sr" rev-parse HEAD)
git -C "$sr" push -q -u origin dev
git -C "$sr" fetch -q origin
: > "$GH_JOURNAL"; : > "$d/bd.log"; rm -f "$d/u11-status" "$d/u11-notes"
( cd "$sr" && "$bin/ship-promote" "$sr" --atom "$atom" --quote 'цитата U11' ) 2>"$d/u117.err" >/dev/null; rc=$?
main_sha=$(git -C "$sr" rev-parse refs/remotes/origin/main)
[[ $rc == 0 && $main_sha == "$staged_sha" ]] && p u11-7 || f u11-7

# u11-8: duplicate promote note blocks a repeat before GitHub.
: > "$GH_JOURNAL"; printf 'promote: done\n' > "$d/u11-notes"; rm -f "$d/u11-status"
( cd "$GA_PROJECTS/u11plain" && "$bin/ship-promote" "$GA_PROJECTS/u11plain" --atom "$atom" --quote 'цитата U11' ) 2>"$d/u118.err" >/dev/null; rc=$?
rm -f "$d/u11-notes"
[[ $rc == 10 && $(<"$d/u118.err") == *'атом закрыт или уже перенесён'* && ! -s "$GH_JOURNAL" ]] && p u11-8 || f u11-8

rm -f "$GH_CREATED" "$d/u11-status" "$d/u11-notes" "$d/bd-status"
: > "$GH_JOURNAL"; : > "$d/bd.log"
git -C "$GA_PROJECTS/stroyremont" checkout -q main
