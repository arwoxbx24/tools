# U24 (dcfg-tf331.5, владелец 17.10): отказ GitHub по биллингу/квоте -> 70 (INFRA), обычный красный CI -> 40.
# Доступны $d, $GH_TEST_DIR, p, f. ga_ci_wait зовёт gh через timeout (--watch), поэтому заглушка — исполняемый файл в PATH.
. "$bin/git-auto-lib"

mkdir -p "$d/u24-bin"
cat > "$d/u24-bin/gh" <<'EOF'
#!/usr/bin/env bash
case $1 in
	pr) case $* in
		*--watch*) exit 0 ;;
		*bucket,link*) echo 'https://github.com/x/rep/actions/runs/5/job/117434901882' ;;
		*name,bucket*) echo build ;;
		*) echo fail ;;
	esac ;;
	api) cat "$GH_TEST_DIR/annot" ;;
esac
EOF
chmod +x "$d/u24-bin/gh"
printf 'fail\n' > "$d/bucket"

# u24-a: упавший job, аннотация — текст отказа биллинга -> 70.
printf '%s\n' "The job was not started because recent account payments have failed or your spending limit needs to be increased. Please check the 'Billing & plans' section in your settings" > "$d/annot"
(PATH="$d/u24-bin:$PATH"; export PATH; GA_CI_POLL=1 ga_ci_wait pr x/rep 7 >/dev/null 2>&1); billing_rc=$?

# u24-b: упавший job, обычная аннотация -> 40.
printf '%s\n' 'Process completed with exit code 1.' > "$d/annot"
(PATH="$d/u24-bin:$PATH"; export PATH; GA_CI_POLL=1 ga_ci_wait pr x/rep 7 >/dev/null 2>&1); red_rc=$?

rm -rf "$d/u24-bin"; rm -f "$d/bucket" "$d/annot"
[[ $billing_rc == 70 ]] && p u24-a || f u24-a
[[ $red_rc == 40 ]] && p u24-b || f u24-b
echo "AC5 billing_rc=$billing_rc red_rc=$red_rc"
