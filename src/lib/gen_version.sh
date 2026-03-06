#!/bin/sh
v=$(git describe --exact-match HEAD 2>/dev/null | sed 's/^v//')
[ -z "$v" ] && v=dev
h=$(git rev-parse HEAD 2>/dev/null)
[ -z "$h" ] && h=unknown
printf 'let version = "%s"\nlet git_hash = "%s"\n' "$v" "$h"
