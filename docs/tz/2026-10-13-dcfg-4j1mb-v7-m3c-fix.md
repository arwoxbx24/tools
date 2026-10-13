# TZ dcfg-4j1mb v7 M3c — one-line fix, paste only
Reason: the case arm is reached only after `bd show` succeeded, so an `unknown-atom` receipt is stale there; `continue` would park the atom forever.
File: `bin/ship-post`. Replace the line
```
	   prod-hold|unknown-atom) continue ;;
```
with the two lines
```
	   prod-hold) continue ;;
	   unknown-atom) rm -f -- "$rf" ;; # atom now visible in its Beads root: deliver it
```
Run `bash -n bin/ship-post`; output rc and `git diff --stat`. Nothing else.
