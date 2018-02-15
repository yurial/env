#!/bin/sh

SELF=$(readlink -f "$0")
BASEDIR=$(dirname "$SELF")


install() {
SRCDIR="$BASEDIR/$USER"
DSTDIR="$HOME"

echo "$SRCDIR/ -> $DSTDIR/"

rsync -rv "$SRCDIR/" "$DSTDIR/"
}

ln -s ../../post-checkout .git/hooks/ 2>/dev/null
case "$1_" in
    "_")
        install;;
    "all_")
        find $BASEDIR -mindepth 1 -maxdepth 1 -type d ! -name '.*' -exec "$SELF" {} \; ;;
    *)
        USERNAME=$(basename $1)
        su -c "$SELF" -l $USERNAME
    esac

