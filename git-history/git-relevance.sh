#!/bin/bash


git log --pretty=format:'%at' --name-only --no-merges --all | \
awk 'NF==1 && $1 ~ /^[0-9]+$/ {ts=$1; next} NF { if (!seen[$0]) seen[$0]=ts } END { for (f in seen) print seen[f] "\t" f }' | \
sort -n | \
awk '{ cmd="date -d @"$1" +\"%Y-%m-%d %H:%M:%S\""; cmd | getline d; close(cmd); $1=""; sub(/^[ \t]+/,""); print d "\t" $0 }'