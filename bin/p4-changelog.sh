#!/bin/bash
#
#
set -o pipefail

if [ $# -eq 0 ]; then
    set -- -m 10 ...
fi
if ! echo "$*" | grep -q -- '-m'; then
    set -- -m 5 "$@"
fi

export LC_ALL=C
export LANG=C

TMP=/tmp/p4-changelog/$$
mkdir -p "$TMP"
rm -rf "$TMP/a" "$TMP/b"
FTMP=$TMP/p4-changes.diff
FDIFF=/tmp/p4-changes.diff
FIGN=$TMP/p4-ignore.txt

cat > $FIGN <<EOF
map
pdb
exe
dll
vcxproj
csproj
xml
sln
exe
xaml.cs
EOF

for CL in $(p4 changes -s submitted "$@" | tr -d '\r' | grep -Eow '^Change ([0-9]+)' | awk '{print $2}'); do
    [[ -z "$CL" ]] && continue
    p4 describe -s $CL | tr -d '\r' >> $FTMP
    p4 describe -s $CL | tr -d '\r' | sed -n -Ee 's@^\.\.\. ([^#]+)#([0-9]+) (.*)$@\1 \2 \3@p' | \
    while read DEPOT CHANGE ACTION; do
        LASTC=$(( CHANGE - 1 ))
        EXT="$(echo ${DEPOT##*.} | tr A-Z a-z)"
        FDEPOT="${DEPOT#//}"
        printf >&2 "\033[2KChange %d %s (%s)\r" "$CL" "$DEPOT#{$LASTC,$CHANGE}" "$ACTION"

        mkdir -p $TMP/a/$(dirname $FDEPOT) $TMP/b/$(dirname $FDEPOT)

        # Ignore this extension
        if grep -i -q "^$EXT\$" $FIGN; then
            printf >&2 "\n#Ignoring diff for %s\n" "${DEPOT}"
            echo "diff -ds a/${DEPOT#//} b/${DEPOT#//}" >> $FTMP
            p4 diff2 -ds "$DEPOT#$LASTC" "$DEPOT#$CHANGE" | tr -d '\r' | sed '1d' >> $FTMP
            continue
        fi

        if [ $LASTC -eq 0 ]; then
            touch $TMP/a/$FDEPOT
        else
            p4 print -q "//${FDEPOT}#${LASTC}" | tr -d '\r' > $TMP/a/$FDEPOT
        fi
        if [ "$ACTION" = "deleted" ]; then
            touch $TMP/b/${FDEPOT}
        else
            p4 print -q "//${FDEPOT}#${CHANGE}" | tr -d '\r' > $TMP/b/$FDEPOT
        fi
        echo "diff -U 5 a/$FDEPOT  b/$FDEPOT" >> $FTMP
        (cd $TMP && diff -U 5 {a,b}/$FDEPOT | tr -d '\r' >> $FTMP )
        continue
        #echo "diff -du a/${DEPOT#//} b/${DEPOT#//}" >> $FTMP
        #echo "--- a/${FDEPOT}" >> $FTMP
        #echo "+++ b/${FDEPOT} >> $FTMP
        #p4 diff2 -du5 -db -dw -dl "$DEPOT#$LASTC" "$DEPOT#$CHANGE" | tr -d '\r' | sed '1d' >> $FTMP
    done
    #p4 describe -dbwl -du $CL | tr -d '\r' | sed -re 's|^==== //([^/]*)/([^#]*).*$|diff -U 2 a/\2 b/\2\n--- a/\2\n+++ b/\2|' >> $FTMP
done
printf >&2 "\n"

mv $FTMP $FDIFF
rm -rf "$TMP"

exec ${EDITOR:-vim} $FDIFF
