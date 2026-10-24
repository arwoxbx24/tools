#!/bin/sh
# tests the node/npm/npx shims against a fake NVM_DIR (the real nvm is never touched)
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

mkdir -p "$tmp/alias" "$tmp/versions/node/v24.0.0/bin"
for cmd in node npm npx; do
    printf '#!/bin/sh\necho "stub-%s $*"\n' "$cmd" > "$tmp/versions/node/v24.0.0/bin/$cmd"
    chmod +x "$tmp/versions/node/v24.0.0/bin/$cmd"
done

ok=0
failed=0
report() {
    if [ "$1" -eq 0 ]; then
        ok=$((ok + 1))
        echo "ok $2 $3"
    else
        failed=$((failed + 1))
        echo "FAIL $2 $3"
    fi
}

cd "$here" || exit 1

for cmd in node npm npx; do
    for c in alias-24 alias-v24.0.0 alias-99 no-alias; do
        case $c in
            alias-24) printf '24\n' > "$tmp/alias/default" ;;
            alias-v24.0.0) printf 'v24.0.0\n' > "$tmp/alias/default" ;;
            alias-99) printf '99\n' > "$tmp/alias/default" ;;
            no-alias) rm -f "$tmp/alias/default" ;;
        esac
        out=$(NVM_DIR="$tmp" "./$cmd" --version 2>"$tmp/err")
        rc=$?
        case $c in
            alias-24|alias-v24.0.0)
                [ "$rc" -eq 0 ] && [ "$out" = "stub-$cmd --version" ] ;;
            alias-99)
                [ "$rc" -eq 127 ] && grep -q 'not installed' "$tmp/err" ;;
            no-alias)
                [ "$rc" -eq 127 ] ;;
        esac
        report $? "$cmd" "$c"
    done
done

echo "ok=$ok failed=$failed"
[ "$failed" -eq 0 ]
