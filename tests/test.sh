#!/usr/bin/env bash

#
#  Copyright 2023 F5, Inc.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#

set -o errexit   # abort on nonzero exit status
set -o pipefail  # don't hide errors within pipes

test_fail_exit_code=2
no_dep_exit_code=3
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
test_dir="${script_dir}"
test_compose_config="${test_dir}/docker/docker-compose.yml"
test_compose_project="ngt"
ssl_dir="${test_dir}/docker/build_context/etc/ssl/"


p() {
  printf "\033[34;1m▶\033[0m "
  echo "$1"
}

e() {
  >&2 echo "$1"
}

usage() { e "Usage: $0 [--latest-njs <default:false>] [--unprivileged <default:false>] [--type <default:oss|plus>" 1>&2; exit 1; }

for arg in "$@"; do
  shift
  case "$arg" in
    '--help')           set -- "$@" '-h'   ;;
    '--latest-njs')     set -- "$@" '-j'   ;;
    '--unprivileged')   set -- "$@" '-u'   ;;
    '--type')           set -- "$@" '-t'   ;;
    *)                  set -- "$@" "$arg" ;;
  esac
done

while getopts "hjut:" arg; do
    case "${arg}" in
        j)
            njs_latest="1"
            ;;
        u)
            unprivileged="1"
            ;;
        t)
            nginx_type="${OPTARG}"
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

startup_message=""

if [ -z "${nginx_type}" ]; then
  nginx_type="oss"
  startup_message="Starting NGINX ${nginx_type} (default)"
elif ! { [ ${nginx_type} == "oss" ] || [ ${nginx_type} == "plus" ]; }; then
    e "Invalid NGINX type: ${nginx_type} - must be either 'oss' or 'plus'"
    usage
else
  startup_message="Starting NGINX ${nginx_type}"
fi

if [ -z "${njs_latest}" ]; then
  njs_latest="0"
  startup_message="${startup_message} with the release NJS module (default)"
elif [ ${njs_latest} -eq 1 ]; then
  startup_message="${startup_message} with the latest NJS module"
else
  startup_message="${startup_message} with the release NJS module"
fi

if [ -z "${unprivileged}" ]; then
  unprivileged="0"
  startup_message="${startup_message} in privileged mode (default)"
elif [ ${unprivileged} -eq 1 ]; then
  startup_message="${startup_message} in unprivileged mode"
else
  startup_message="${startup_message} in privileged mode"
fi

e "${startup_message}"

set -o nounset   # abort on unbound variable

docker_cmd="$(command -v docker)"
if ! [ -x "${docker_cmd}" ]; then
  e "required dependency not found: docker not found in the path or not executable"
  exit ${no_dep_exit_code}
fi

docker_compose_cmd="$(command -v docker-compose)"
if ! [ -x "${docker_compose_cmd}" ]; then
  e "required dependency not found: docker-compose not found in the path or not executable"
  exit ${no_dep_exit_code}
fi

curl_cmd="$(command -v curl)"
if ! [ -x "${curl_cmd}" ]; then
  e "required dependency not found: curl not found in the path or not executable"
  exit ${no_dep_exit_code}
fi

wait_for_it_cmd="$(command -v wait-for-it || true)"
if [ -x "${wait_for_it_cmd}" ]; then
  wait_for_it_installed=1
else
  e "wait-for-it command not available, consider installing to prevent race conditions"
  wait_for_it_installed=0
fi

if [ "${nginx_type}" = "plus" ]; then
  if [ ! -f "${ssl_dir}/nginx-repo.crt" ]; then
    e "NGINX Plus certificate file not found: ${ssl_dir}/nginx-repo.crt"
    exit ${no_dep_exit_code}
  fi

    if [ ! -f "${ssl_dir}/nginx-repo.key" ]; then
    e "NGINX Plus key file not found: ${ssl_dir}/nginx-repo.key"
    exit ${no_dep_exit_code}
  fi
fi

compose() {
  # Hint to docker-compose the internal port to map for the container
  if [ ${unprivileged} -eq 1 ]; then
    export NGINX_INTERNAL_PORT=8080
  else
    export NGINX_INTERNAL_PORT=80
  fi

  "${docker_compose_cmd}" -f "${test_compose_config}" -p "${test_compose_project}" "$@"
}

finish() {
  result=$?

  if [ $result -ne 0 ]; then
    e "Error running tests - outputting container logs"
    compose logs
  fi

  p "Cleaning up Docker compose environment"
  docker kill nginx_aws_signature_test 2> /dev/null || true
  docker rmi  nginx_aws_signature_test 2> /dev/null || true

  exit ${result}
}
trap finish EXIT ERR SIGTERM SIGINT

### BUILD

p "Building NGINX AWS Signature Lib Test Docker image"
docker-compose -f ${test_compose_config} up -d

### UNIT TESTS

runUnitTestWithOutSessionToken() {
  test_code="$1"
  docker exec \
    -e "S3_DEBUG=true"                    \
    -e "S3_STYLE=virtual"                 \
    -e "AWS_ACCESS_KEY_ID=unit_test"      \
    -e "AWS_SECRET_ACCESS_KEY=unit_test"  \
    -e "S3_BUCKET_NAME=unit_test"         \
    -e "S3_SERVER=unit_test"              \
    -e "S3_SERVER_PROTO=https"            \
    -e "S3_SERVER_PORT=443"               \
    -e "S3_REGION=test-1"                 \
    -e "AWS_SIGS_VERSION=4"               \
    nginx_aws_signature_test njs /var/tmp/${test_code}
}

runUnitTestWithSessionToken() {
  test_code="$1"

  docker exec \
    -e "S3_DEBUG=true"                    \
    -e "S3_STYLE=virtual"                 \
    -e "AWS_ACCESS_KEY_ID=unit_test"      \
    -e "AWS_SECRET_ACCESS_KEY=unit_test"  \
    -e "AWS_SESSION_TOKEN=unit_test"      \
    -e "S3_BUCKET_NAME=unit_test"         \
    -e "S3_SERVER=unit_test"              \
    -e "S3_SERVER_PROTO=https"            \
    -e "S3_SERVER_PORT=443"               \
    -e "S3_REGION=test-1"                 \
    -e "AWS_SIGS_VERSION=4"               \
    nginx_aws_signature_test njs /var/tmp/${test_code}
}

p "Running unit tests for utils"
runUnitTestWithSessionToken "utils_test.js"

p "Running unit tests with an access key ID and a secret key in Docker image"
runUnitTestWithOutSessionToken "awscredentials_test.js"
runUnitTestWithOutSessionToken "awssig2_test.js"
runUnitTestWithOutSessionToken "awssig4_test.js"

p "Running unit tests with an session token in Docker image"
runUnitTestWithSessionToken "awscredentials_test.js"
runUnitTestWithSessionToken "awssig2_test.js"
runUnitTestWithSessionToken "awssig4_test.js"
