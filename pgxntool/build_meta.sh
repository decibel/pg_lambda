#!/bin/bash

set -e

error () {
    echo $@ >&2
}
die () {
    return=$1
    shift
    error $@
    exit $return
}

[ $# -eq 2 ] || die 2 Invalid number of arguments $#

in=$1
out=$2

# Ensure we can safely rewrite the file
[ `head -n1 $in` == '{' ] || die 2 First line of $in must be '{'

cat << _PRE_ > $out
{
    "X_WARNING": "AUTO-GENERATED FILE, DO NOT MODIFY!",
    "X_WARNING": "Generated from $in by $0",

_PRE_

# Pattern is meant to match ': "" ,' or ': [ "", ' where spaces are optional.
# This is to strip things like '"key": "",' and '"key": [ "", "" ]'.
#
# NOTE! We intentionally don't match ': ""', to support '"X_end": ""'
tail -n +2 $in | egrep -v ':\s*(\[\s*)?""\s*,' >> $out
