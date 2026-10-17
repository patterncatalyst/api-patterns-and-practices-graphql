#!/usr/bin/env bash
# examples/25-docker-compose/gen-certs.sh <dir>
#
# Writes a throwaway certificate authority and one server certificate into <dir>:
#   ca.crt    the CA certificate: what a client trusts (curl --cacert, NODE_EXTRA_CA_CERTS)
#   edge.crt  the edge's server certificate, signed by the CA, with SANs localhost, edge, 127.0.0.1
#   edge.key  the edge's private key (PKCS#8, EC P-256); compose mounts it as a secret
# Both certificates are valid for 2 days. The files are test fixtures for this lab:
# nothing here is committed (certs/ is git-ignored), and a private key never belongs
# in a repository. The key is mode 0644 only because the edge reads it as uid 1001,
# not as the owner of the bind-mounted secret file.
set -euo pipefail

dir="${1:?usage: gen-certs.sh <dir>}"
mkdir -p "$dir"
dir="$(cd "$dir" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$work/ca.key" 2>/dev/null
openssl req -new -x509 -key "$work/ca.key" -sha256 -days 2 -subj "/CN=Ch25 lab CA" \
  -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" \
  -out "$dir/ca.crt"

openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$dir/edge.key" 2>/dev/null
openssl req -new -key "$dir/edge.key" -subj "/CN=localhost" -out "$work/tls.csr"
cat >"$work/ext.cnf" <<'CNF'
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = serverAuth
subjectAltName = DNS:localhost, DNS:edge, IP:127.0.0.1
CNF
openssl x509 -req -in "$work/tls.csr" -CA "$dir/ca.crt" -CAkey "$work/ca.key" -CAserial "$work/ca.srl" -CAcreateserial \
  -sha256 -days 2 -extfile "$work/ext.cnf" -out "$dir/edge.crt" 2>/dev/null

chmod 0644 "$dir/ca.crt" "$dir/edge.crt" "$dir/edge.key"
echo "gen-certs.sh: wrote ca.crt, edge.crt and edge.key to $dir"
