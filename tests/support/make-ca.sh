#!/usr/bin/env sh
# Throwaway CAs and server certificates for the TLS checks (never real material; keys stay in the directory).
# Usage: tests/support/make-ca.sh <dir>
# Creates: ca.crt/ca.key (trusted), other-ca.crt/other-ca.key (an unrelated CA),
#          server.crt/server.key (SAN catalog-api, signed by ca), wrong-name.crt/wrong-name.key (SAN other-service, signed by ca),
#          untrusted.crt/untrusted.key (SAN catalog-api, signed by other-ca).
set -eu
# Git Bash on Windows would rewrite the leading "/" of the -subj values as a path.
export MSYS2_ARG_CONV_EXCL="*"
dir="$1"
mkdir -p "$dir"
cd "$dir"

new_ca() {  # name
  openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=throwaway $1" \
    -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign" \
    -keyout "$1.key" -out "$1.crt" 2>/dev/null
}
new_leaf() {  # file name, san, ca name
  openssl req -newkey rsa:2048 -nodes -subj "/CN=$2" -keyout "$1.key" -out "$1.csr" 2>/dev/null
  printf 'subjectAltName=DNS:%s\nbasicConstraints=CA:FALSE\n' "$2" > "$1.ext"
  openssl x509 -req -in "$1.csr" -CA "$3.crt" -CAkey "$3.key" -CAcreateserial -days 1 -extfile "$1.ext" -out "$1.crt" 2>/dev/null
}

new_ca ca
new_ca other-ca
new_leaf server catalog-api ca
new_leaf wrong-name other-service ca
new_leaf untrusted catalog-api other-ca
chmod 644 ./*.key ./*.crt
