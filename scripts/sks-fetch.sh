#!/usr/bin/env bash

strip_chars() {
    local chars
    chars="${1}"
    shift

    if [ "${#}" -gt 0 ]; then
        printf -- '%s\n' "${@}" | tr -d "${chars}"
    else
        tr -d "${chars}"
    fi
}

sks_fingerprint_file_name() {
    printf -- 'sks-%s.asc\n' "$(strip_chars ' ' "${*}")"
}

sks_get() {
    local url args search
    url='https://sks-keyservers.net/pks/lookup'
    args='?op=get&search='
    search="0x$(strip_chars ' ' "${*}")"

    printf -- '%s%s%s\n' "${url}" "${args}" "${search}"
}

remove_line_feeds() {
    local fn sedprog tmpfn
    sedprog='s,'$'\r''$,,'

    for fn; do
        tmpfn="${fn}.sedtmp.${$}"
        sed -e "${sedprog}" "${fn}" > "${tmpfn}" &&
            touch -r "${fn}" "${tmpfn}" &&
            mv "${tmpfn}" "${fn}"
    done
}

fetch() {
    local output regex tmpfn
    output="keys/$(sks_fingerprint_file_name "${*}")"
    regex='^-----END PGP PUBLIC KEY BLOCK-----$'
    tmpfn="${output}.tmp.${$}"

    curl -o "${tmpfn}" -sLRS "$(sks_get "${*}")" &&
        remove_line_feeds "${tmpfn}" &&
        grep >/dev/null 2>&1 "${regex}" "${tmpfn}" &&
        mv "${tmpfn}" "${output}"
    rm -f "${tmpfn}"
}

fetch "${@}"
