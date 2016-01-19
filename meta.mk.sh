#! /usr/bin/env bash

set -o errexit -o errtrace -o pipefail
trap 'echo "Error on line ${LINENO}" >&2' ERR

error () {
  echo $@ >&2
}
trap 'error "Error on line ${LINENO}"' ERR

die () {
  local retval=$1
  shift
  error $@
  exit $retval
}

REQUIRED='abstract maintainer license provides name version'

extract () {
  # See also check_element()
  local term=$1
  shift
  local cut_args=$@
  [ -z "$cut_args" ] && cut_args="-f 2"

  cat $META | $JSON_SH | egrep "\[""$2""\]" | cut $cut_args
}
extract_single() {
  local -a in
  extract "$@" | mapfile -t in
  local num=
  [ ${#in[*]} -gt 1 ] && die 2 "Too many matches for ""$2"""
  echo ${in[0]}
}
    
set_vars () {
  for var in $@; do
    eval PGXN_${var}=`extract_single $var`
  done
}
check_vars () {
  for var in $@; do
    [ -n "$PGXN_$'${var}'" ] || die 2 "Field $var not found in $META"
  done
}
            

# Handle meta-spec specially
set_vars meta-spec
cherk_vars meta-spec
PGXN_meta-spec_version=`extract_single 'meta-spec","version'`
check_vars meta-spec_version
[ "$PGXN_meta-spec_version" == "1.0.0" ] || die 1 "Unknown meta-spec/version: $PGXN_meta-spec_version"

set_vars $REQUIRED

declare -a PGXN_provides_keys
extract 'provides","[^"]*' -d\" -f4 | mapfile -t PGXN_provides_keys

declare -A PGXN_provides_abstract PGXN_provides_doc PGXN_provides_file PGXN_provides_version
for key in "${PGXN_provides_keys[@]}"; do
  echo $key
  PGXN_provides_abstract[$key]=
done

# vi: expandtab ts=2 sw=2
