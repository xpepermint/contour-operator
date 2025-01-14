#! /usr/bin/env bash

readonly KIND=${KIND:-kind}
readonly CLUSTERNAME=${CLUSTERNAME:-contour}
readonly HERE=$(cd "$(dirname "$0")" && pwd)
readonly REPO=$(cd "${HERE}/.." && pwd)
readonly PROGNAME=$(basename "$0")
readonly IMAGE="$1"
readonly OLD_VERSION="$2"
readonly VERSION="$3"

if [ -z "$IMAGE" ] || [ -z "$OLD_VERSION" ] || [ -z "$VERSION" ]; then
    printf "Usage: %s IMAGE OLD_VERSION VERSION\n" "$PROGNAME"
    exit 1
fi

set -o errexit
set -o nounset
set -o pipefail

# Wrap sed to deal with GNU and BSD sed flags.
run::sed() {
    local -r vers="$(sed --version < /dev/null 2>&1 | grep -q GNU && echo gnu || echo bsd)"
    case "$vers" in
        gnu) sed -i "$@" ;;
        *) sed -i '' "$@" ;;
    esac
}

kind::cluster::exists() {
    ${KIND} get clusters | grep -q "$1"
}

kind::cluster::load() {
    ${KIND} load docker-image \
        --name "${CLUSTERNAME}" \
        "$@"
}

if ! kind::cluster::exists "${CLUSTERNAME}" ; then
    echo "cluster ${CLUSTERNAME} does not exist"
    exit 2
fi

# Update the image pull policy so the operator's image is served by
# the kind cluster. Set the pull policy with kustomize when
# https://github.com/kubernetes-sigs/kustomize/issues/1493 is fixed.
for file in config/manager/manager.yaml examples/operator/operator.yaml ; do
  echo "setting \"imagePullPolicy: IfNotPresent\" for $file"
  run::sed \
    "-es|imagePullPolicy: Always|imagePullPolicy: IfNotPresent|" \
    "$file"
done

# Update the operator's image.
for file in config/manager/manager.yaml examples/operator/operator.yaml ; do
  echo "setting \"image: ${IMAGE}:${VERSION}\" for $file"
  run::sed \
    "-es|image: ${IMAGE}:${OLD_VERSION}|image: ${IMAGE}:${VERSION}|" \
    "$file"
done

# Push the contour-operator build image to kind cluster.
# Note: The operator's image pull policy is "IfNotPresent", so
# the image from kind::cluster::load will be used.
echo "Loading image ${IMAGE}:${VERSION} to kind cluster ${CLUSTERNAME}..."
kind::cluster::load "${IMAGE}:${VERSION}"
