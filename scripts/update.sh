#!/usr/bin/env bash

url='https://www.internic.net/domain'

lastupdate="${url}/last_update.txt"
hints="${url}/named.root"
hints_checksum="${hints}.md5"
hints_signature="${hints}.sig"
signatures="${url}/INTERNIC_ROOT_ZONE.signatures"
signatures_signature="${signatures}.asc"

output="$(mktemp -q -d domain.XXXXXX || printf -- '%s\n' domain.${$})"

cleanup() {
    git checkout -
    rm -rf "${output}"
}

commit() {
    local hints_fn
    hints_fn="${hints##*/}"

    git add "${hints_fn}"
    git add "${hints_checksum##*/}"
    git add "${hints_signature##*/}"
    git add "${signatures_signature##*/}"
    git add "${signatures##*/}"

    git add ../domain
    git commit -m "Domain data: $(root_zone_serial "${hints_fn}")"
}

compare_checksums() {
    local cur matched prev
    matched='true'
    prev="${1}"
    shift

    for cur; do
	test -s .prev || printf >.prev -- '%s\n' "$(printf -- '%s\n' "${prev}" | awk '{ print toupper($0); }')"
	printf >.cur -- '%s\n' "$(printf -- '%s\n' "${cur}" | awk '{ print toupper($0); }')"
	diff -u .prev .cur || matched='false'
        rm -f .prev
        mv .cur .prev
        prev="${cur}"
    done

    rm -f .prev .cur
    if "${matched}"; then
        return 0
    fi
    return 1
}

current_root_zone_serial() {
    local awkprog server
    awkprog='"." == $1 { print $(NF-4); exit; }'
    server="$(pick_root_server)"

    dig ${server:+"@${server}"} +noall +answer -t SOA . | awk "${awkprog}"
}

fetch() {
    local url
    for url; do
        curl ${CURL_ARGS:--sSJRLO} "${url}"
    done
}

get() {
    local fn
    fn="${lastupdate##*/}"

    cp -p "../domain/${fn}" "${fn}" || :
    CURL_ARGS="-JRLSsz ./${fn} -o ./${fn}" \
        fetch "${lastupdate}"
    test -s "${fn}" || return 1
    diff -us "../domain/${fn}" "${fn}" && return 2
    fetch \
        "${signatures_signature}" "${signatures}" \
        "${hints_signature}" "${hints_checksum}" "${hints}"
}

gpg_verify() {
    local hints_fn hints_signature_fn signatures_fn
    hints_fn="${hints##*/}"
    hints_signature_fn="${hints_signature##*/}"
    signatures_fn="${signatures_signature##*/}"

    gpg --verify "${signatures_fn}" &&
    gpg --verify "${hints_signature_fn}" "${hints_fn}"
}

latest_root_zone_serial() {
    local glob sedprog
    glob='domain-??????????'
    sedprog='s/^domain-//'

    ls -1d ${glob} | tail -n 1 | sed -e "${sedprog}"
}

pick_root_server() {
    local hfmt n nfmt
    hfmt='%b.root-servers.net.\n'
    n="$(( 100 + RANDOM % 2 ))"
    nfmt='\\x%02x'

    printf -- \
        "${hfmt}" \
        "$(printf -- "${nfmt}" "${n}")"
}

root_zone_serial() {
    awk '/version of root zone:/ { print $NF; exit; }' "${1}"
}

verify() {
    local awkprog computed hints_fn metadata signatures_fn signed stored verified
    awkprog='$0 ~ m { o=1; next; } o && /:/ { print; } /^$/ { o=""; }'
    hints_fn="${hints##*/}"
    signatures_fn="${signatures_signature##*/}"
    stored="$(< "${hints_checksum##*/}")"
    verified='true'

    gpg_verify || verified='false'

    computed="$(gpg --print-md md5 "${hints_fn}" | cut -d : -f 2- | tr -d ' ')"

    metadata="$(awk -v "m=${hints_fn}" "${awkprog}" "${signatures_fn}")"
    #printf -- '%s\n' "${metadata}"

    signed="$(printf -- '%s\n' "${metadata}" | awk 'tolower($1) == "md5" { print $NF; exit; }')"

    compare_checksums "${signed}" "${computed}" "${stored}" || verified='false'

    if "${verified}"; then
        if [ ! -d "../domain-${computed}" ]; then
            cp -a "${output}" "../domain-${computed}"
        fi
        mv -f "${lastupdate##*/}" "../domain-${computed}/"
        ln -v -s "domain-${computed}" .checksum-link
        ln -v -s "domain-${computed}" ".domain-$(root_zone_serial "${hints_fn}")"
        return 0
    fi

    return 1
}

GNUPGHOME="${PWD}/.gnupg"
export GNUPGHOME

mkdir -p "${output}"
trap cleanup EXIT
git checkout domains
crzs="$(current_root_zone_serial)"
lrzs="$(latest_root_zone_serial)"
cd "${output}" && output="$(pwd)" || exit 1

if  [ -n "${crzs}" ] &&
    [ -n "${lrzs}" ] &&
    [ "${crzs}" -le "${lrzs}" ]
then
    exit 2
fi

chmod 0700 "${GNUPGHOME}"
chmod 0600 "${GNUPGHOME}"/*

if get && verify; then
    rm -rf ../domain
    mv .checksum-link ../domain
    for f in .domain-* ; do
        rm -f "../${f#.}"
        mv -v "${f}" "../${f#.}"
        git add "../${f#.}"
    done; unset -v f
    cd ../domain && commit || exit 3
fi

touch "../domain-${crzs}"
