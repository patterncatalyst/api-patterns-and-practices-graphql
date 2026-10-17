#!/usr/bin/env bash
# examples/17-transport-security/gen-certs.sh <dir>
#
# Writes a throwaway certificate authority and one server certificate into <dir>:
#   ca.crt   the CA certificate: what a client trusts (curl --cacert, NODE_EXTRA_CA_CERTS)
#   tls.crt  the server certificate, signed by the CA, with SANs
#            localhost, quarkus, python, quarkus-internal, python-internal, 127.0.0.1
#   tls.key  the server's private key (PKCS#8, EC P-256)
# Both certificates are valid for 2 days. The files are test fixtures for this lab:
# nothing here is committed (certs/ is git-ignored), and a private key never belongs
# in a repository. The key is mode 0644 only because the containers read it as
# uid 185 (Quarkus) and uid 1001 (Python), not as the owner of the mount.
set -euo pipefail

dir="${1:?usage: gen-certs.sh <dir>}"
mkdir -p "$dir"
dir="$(cd "$dir" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$work/ca.key" 2>/dev/null
openssl req -new -x509 -key "$work/ca.key" -sha256 -days 2 -subj "/CN=Ch17 lab CA" \
  -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" \
  -out "$dir/ca.crt"

openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$dir/tls.key" 2>/dev/null
openssl req -new -key "$dir/tls.key" -subj "/CN=localhost" -out "$work/tls.csr"
cat >"$work/ext.cnf" <<'CNF'
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = serverAuth
subjectAltName = DNS:localhost, DNS:quarkus, DNS:python, DNS:quarkus-internal, DNS:python-internal, IP:127.0.0.1
CNF
openssl x509 -req -in "$work/tls.csr" -CA "$dir/ca.crt" -CAkey "$work/ca.key" -CAserial "$work/ca.srl" -CAcreateserial \
  -sha256 -days 2 -extfile "$work/ext.cnf" -out "$dir/tls.crt" 2>/dev/null

chmod 0644 "$dir/ca.crt" "$dir/tls.crt" "$dir/tls.key"
echo "gen-certs.sh: wrote ca.crt, tls.crt and tls.key to $dir"
