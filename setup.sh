#!/usr/bin/env bash

set -o errexit -o errtrace -o pipefail
trap 'echo "Error on line ${LINENO}"' ERR

[ -d .git ] || git init

if ! git diff --cached --exit-code; then
    echo "Git repository is not clean; please commit and try again." >&2
    exit 1
fi

safecreate () {
    file=$1
    shift
    if [ -e $file ]; then
        echo "$file already exists"
    else
        echo "Creating $file"
        echo $@ > $file
        git add $file
    fi
}

safecp () {
    [ $# -eq 2 ] || exit 1
    local src=$1
    local dest=$2
    if [ -e $dest ]; then
        echo $dest already exists
    else
        echo Copying $src to $dest and adding to git
        cp $src $dest
        git add $dest
    fi
}

safecp pgxntool/_.gitignore .gitignore
safecp pgxntool/META.in.json META.in.json

safecreate Makefile include pgxntool/base.mk

make META.json
git add META.json

mkdir -p sql test src

cd test
safecp ../pgxntool/test/deps.sql deps.sql
[ -d pgxntool ] || ln -s ../pgxntool/test/pgxntool .
git add pgxntool
git status

echo "If you won't be creating C code then you can:

rmdir src

If everything looks good then

git commit -am 'Add pgxntool (https://github.com/decibel/pgxntool/tree/release)'"
