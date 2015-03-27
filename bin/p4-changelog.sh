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

#export LC_ALL=C
#export LANG=C
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

DIFFCMD="${DIFFCMD:-diff -N -E -w -r -U 5}"
VISUAL=${VISUAL:-${EDITOR:-vim -c ':e! ++enc=utf8'}}
LOGNAME=${LOGNAME:-$(id -un)}

T=/tmp/${LOGNAME}/p4-changelog
FTMP=$T/p4-changes.$$
FDIFF=$T/p4-changes.diff
FIGN=$T/p4-ignore.txt

mkdir -p "$T"

cat > ${FIGN}.$$ <<EOF
bat
c
cc
cfg
cmd
cpp
csproj
cxx
gdt
gsc
h
hh
hpp
hxx
inl
lua
mk
py
sh
sln
vcxproj
xml
EOF
mv ${FIGN}.$$ ${FIGN}

for CL in $(p4 changes -s submitted "$@" | grep -Eow '^Change ([0-9]+)' | awk '{print $2}'); do
    [[ -z "$CL" ]] && continue
    TMP="$T/c/$CL"
    rm -rf $TMP/{a,b}
    mkdir -p $TMP/{a,b}
    p4 describe -s $CL | tee -a ${FTMP} > $TMP/p4-describe.txt
    grep '^\.\.\.' $TMP/p4-describe.txt | sed -n -Ee 's@^\.\.\. ([^#]+)#([0-9]+) (.*)$@\1 \2 \3@p' | \
    while read DEPOT CHANGE ACTION; do
        LASTC=$(( CHANGE - 1 ))
        if [ $? -ne 0 ]; then
            continue
        fi
        EXT="$(echo ${DEPOT##*.} | tr A-Z a-z)"
        FDEPOT="${DEPOT#//}"
        printf >&2 "\033[2K# Change %d %s (%s)\r" "$CL" "$DEPOT#{$LASTC,$CHANGE}" "$ACTION"

        mkdir -p $TMP/a/$(dirname $FDEPOT) $TMP/b/$(dirname $FDEPOT)

        # Ignore extensions in $FIGN
        if ! grep -i -q "^$EXT\$" $FIGN; then
            continue
#           dprintf >&2 "\n#Ignoring diff for %s\n" "${DEPOT}"
#           echo "diff -ds a/${DEPOT#//} b/${DEPOT#//}" >> $FTMP
#            Dp4 diff2 -ds "$DEPOT#$LASTC" "$DEPOT#$CHANGE" | sed '1d' >> $FTMP
        else

            if [ $LASTC -eq 0 ]; then
                touch $TMP/a/$FDEPOT
            else
                p4 print -q "//${FDEPOT}#${LASTC}" > $TMP/a/$FDEPOT
            fi
            if [ "$ACTION" = "deleted" ]; then
                touch $TMP/b/${FDEPOT}
            else
                p4 print -q "//${FDEPOT}#${CHANGE}" > $TMP/b/$FDEPOT
            fi
            #echo "diff -U 5 a/$FDEPOT  b/$FDEPOT" >> $FTMP
            #echo "diff -du a/${DEPOT#//} b/${DEPOT#//}" >> $FTMP
            #echo "--- a/${FDEPOT}" >> $FTMP
            #echo "+++ b/${FDEPOT} >> $FTMP
            #p4 diff2 -du5 -db -dw -dl "$DEPOT#$LASTC" "$DEPOT#$CHANGE" | tr -d '\r' | sed '1d' >> $FTMP
        fi
    done
    #p4 describe -dbwl -du $CL | tr -d '\r' | sed -re 's|^==== //([^/]*)/([^#]*).*$|diff -U 2 a/\2 b/\2\n--- a/\2\n+++ b/\2|' >> $FTMP
    # -N: treat missing file as empty, -E ignore tab/space conversions, -w ignore other whitespace changes
    (cd $TMP && ${DIFFCMD} {a,b} >> $FTMP)
done
printf >&2 "\n"

tr -d '\r' < $FTMP > ${FDIFF}.$$
mv "${FDIFF}.$$" "${FDIFF}"
rm -f $FTMP

echo >&2 "Diff is in:"
echo "$FDIFF"
if [ -n "$DIFF" ]; then
    echo >&2 "Invoking \$DIFF=$DIFF in $TMP"
    # The xargs bash -c trick is to reopen stdin to be the controling tty
    cd $TMP && diff -qr a b | sed -En -e 's#Files (.*) and (.*) differ$#\1\n\2#p' | head -2 | xargs -n2 bash -c '</dev/tty '$DIFF' "$@"' $(which $DIFF)
else
    exec $VISUAL $FDIFF
fi
