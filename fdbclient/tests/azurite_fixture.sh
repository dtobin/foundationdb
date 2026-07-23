#!/usr/bin/env bash
#
# Functions for dealing w/ Azurite, the Azure Blob Storage emulator.
# See https://github.com/Azure/Azurite
#
# This fixture assumes Azurite is ALREADY RUNNING locally (this script does not
# start or stop it). By default it targets the standard Azurite blob endpoint at
# 127.0.0.1:10000 using the well-known emulator account "devstoreaccount1", but
# every value is configurable via environment variables:
#
#   AZURITE_HOST               Host Azurite is listening on   (default: 127.0.0.1)
#   AZURITE_PORT               Blob service port              (default: 10000)
#   AZURITE_ACCOUNT            Storage account name           (default: devstoreaccount1)
#   AZURITE_KEY                Shared key (base64)            (default: well-known Azurite key)
#   AZURITE_CONTAINER          Container/bucket to use        (default: fdbbackup)
#   AZURITE_SECURE_CONNECTION  1 for https, 0 for http        (default: 0)
#
# You can start a matching Azurite with, e.g.:
#   azurite-blob --blobHost 127.0.0.1 --blobPort 10000 --location /tmp/azurite
#
# NOTE: Azurite defaults to emulator-style ("path-style") URLs where the account
# name is the first path segment (http://127.0.0.1:10000/devstoreaccount1/<container>).
# The FoundationDB Azure endpoint currently issues production-style requests (the
# account name lives in the Host header, not the request path). To interoperate with
# this fixture, run Azurite so it resolves the account from the request (production
# style), e.g. by mapping "<account>.blob.core.windows.net" to 127.0.0.1, or run a
# path-style-aware endpoint. This fixture only produces the connection config; it
# does not manage that resolution.
#
# Here is how to use this fixture:
#
#  # First source this fixture.
#  if ! source "${cwd}/azurite_fixture.sh"; then
#    err "Failed to source azurite_fixture.sh"
#    exit 1
#  fi
#  if ! TEST_SCRATCH_DIR=$( create_azurite_dir "${scratch_dir}" ); then
#    err "Failed creating local azurite_dir"
#    exit 1
#  fi
#  readonly TEST_SCRATCH_DIR
#  if ! azurite_output=$(azurite_setup "${build_dir}" "${TEST_SCRATCH_DIR}"); then
#    err "Failed azurite_setup"
#    exit 1
#  fi
#  IFS=$'\n' read -r -d '' account host bucket blob_credentials_file secure_connection <<< "${azurite_output}" || true
#  ...
#  # When done, call shutdown_azurite
#  shutdown_azurite "${TEST_SCRATCH_DIR}"
#

# Well-known Azurite / Azure Storage Emulator account and key.
# These are published defaults, not secrets.
readonly AZURITE_DEFAULT_ACCOUNT="devstoreaccount1"
readonly AZURITE_DEFAULT_KEY="Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw=="

# Cleanup any mess we've made. For calling from signal trap on exit.
# Azurite itself is externally managed, so we only remove the scratch directory.
# $1 The azurite scratch directory to clean up on exit.
function shutdown_azurite {
  local local_scratch_dir="${1}"
  if [[ -d "${local_scratch_dir}" ]]; then
    rm -rf "${local_scratch_dir}"
  fi
}

# Create directory for the azurite test to use writing temporary data.
# $1 Directory where we want to write data and logs.
function create_azurite_dir {
  local dir="${1}"
  local azurite_dir
  azurite_dir=$(mktemp -d "${dir}/azurite.$$.XXXX")
  if [[ ! -d "${azurite_dir}" ]]; then
    echo "ERROR: Failed create of azurite directory ${azurite_dir}" >&2
    return 1
  fi
  echo "${azurite_dir}"
}

# Write out blob_credentials for Azurite.
# $1 The shared key (base64-encoded)
# $2 Hostname for Azurite (without port; matches the IBlobStoreEndpoint credential key)
# $3 The scratch dir to write the blob credentials file into
# Echos the blob_credentials file path.
function write_azurite_blob_credentials {
  local shared_key="${1}"
  local host="${2}"
  local dir="${3}"
  # Credential file key is "@host" (matching the IBlobStoreEndpoint convention).
  # The endpoint parses "account@host:port" into host="host" (no port), so key on the
  # bare host here.
  local cred_key="@${host}"
  local blob_credentials_str="{\"accounts\": { \"${cred_key}\": {\"secret\": \"${shared_key}\"}}}"
  local blob_credentials_file="${dir}/blob_credentials.json"
  echo "${blob_credentials_str}" > "${blob_credentials_file}"
  echo "${blob_credentials_file}"
}

# Set up access to a locally-running Azurite emulator.
# $1 build_dir (unused; kept for parity with the other fixtures)
# $2 azurite_dir (created by create_azurite_dir)
# Returns: account, host(:port), container, blob_credentials_file, secure_connection
#          (newline-separated)
function azurite_setup {
  local local_build_dir="${1}"
  local local_azurite_dir="${2}"

  local azurite_host="${AZURITE_HOST:-127.0.0.1}"
  local azurite_port="${AZURITE_PORT:-10000}"
  local account="${AZURITE_ACCOUNT:-${AZURITE_DEFAULT_ACCOUNT}}"
  local key="${AZURITE_KEY:-${AZURITE_DEFAULT_KEY}}"
  local container="${AZURITE_CONTAINER:-fdbbackup}"
  local secure_connection="${AZURITE_SECURE_CONNECTION:-0}"

  # Host portion of the blobstore URL, including the port Azurite listens on.
  local host="${azurite_host}:${azurite_port}"

  local blob_credentials_file
  if ! blob_credentials_file=$(write_azurite_blob_credentials "${key}" "${azurite_host}" "${local_azurite_dir}"); then
    echo "Failed to write credentials file" >&2
    exit 1
  fi

  # Output: account (for URL cred), host:port, container, credentials_file, secure_connection
  printf "%s\n%s\n%s\n%s\n%s" "${account}" "${host}" "${container}" "${blob_credentials_file}" "${secure_connection}"
}
