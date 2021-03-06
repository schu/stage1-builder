#!/bin/bash

set -eu
set -o pipefail

# The kernel versions we want to run the tests on
readonly kernel_versions=("4.9.96")

# The rkt version which is set as a dependency for
# the custom stage1-kvm images
readonly rkt_version="1.30.0"

# Directory where this file is, used in the example below
readonly dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Download rkt if not available yet as Semaphore CI
# doesn't have rkt at the time of writing
if [[ ! -f "./rkt/rkt" ]] ||
  [[ ! "$(./rkt/rkt version | awk '/rkt Version/{print $3}')" == "${rkt_version}" ]]; then

  curl -LsS "https://github.com/coreos/rkt/releases/download/v${rkt_version}/rkt-v${rkt_version}.tar.gz" \
    -o rkt.tgz

  mkdir -p rkt
  tar -xvf rkt.tgz -C rkt --strip-components=1
fi

# Pre-fetch stage1 dependency due to rkt#2241
# https://github.com/coreos/rkt/issues/2241
sudo ./rkt/rkt image fetch --insecure-options=image "coreos.com/rkt/stage1-kvm:${rkt_version}" >/dev/null

for kernel_version in "${kernel_versions[@]}"; do
  # The stage1-kvm image to use for the tests
  stage1_name="kinvolk.io/aci/rkt/stage1-kvm:${rkt_version},kernelversion=${kernel_version}"

  # Make sure there's no stale rkt-uuid file
  rm -f ./rkt-uuid

  # You most likely want to provide source code to the
  # container in order to run the tests. You can do this
  # with volumes:
  # https://coreos.com/rkt/docs/latest/subcommands/run.html#mounting-volumes

  # Depending on the level of privileges you need,
  # `--insecure-options=all-run` might be necessary:
  # https://coreos.com/rkt/docs/latest/commands.html#global-options

  # timeout can be used to make sure tests finish in
  # a reasonable amount of time
  sudo timeout --foreground --kill-after=10 5m \
    ./rkt/rkt \
    run --interactive \
    --uuid-file-save=./rkt-uuid \
    --insecure-options=image \
    --dns=8.8.8.8 \
    --stage1-name="${stage1_name}" \
    --volume=here,kind=host,source="${dir}" \
    --mount=volume=here,target=/stage1-builder/examples \
    docker://golang:alpine \
    --exec=/bin/sh -- -c \
    'printf "\n\nRUN YOUR TESTS HERE (on kernel $(uname -r))\n\n\n"'

  # Determine exit code from pod status due to rkt#2777
  # https://github.com/coreos/rkt/issues/2777
  test_status=$(sudo ./rkt/rkt status "$(<rkt-uuid)" | awk '/app-/{split($0,a,"=")} END{print a[2]}')
  if [[ $test_status -ne 0 ]]; then
    exit "$test_status"
  fi
  echo "Test successful on ${kernel_version}"
done
