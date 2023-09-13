#!/bin/sh
#shellcheck disable=SC1090,SC3028
# Quietly try to make the install directory.
mkdir -p "${JQ_EVAL_INSTALL_DIR}"

JQ_STR_VERSION="$(echo "${JQ_STR_VERSION}" | circleci env subst)"
JQ_EVAL_INSTALL_DIR="$(eval echo "${JQ_EVAL_INSTALL_DIR}")"

# Selectively export the SUDO command, depending if we have permission
# for a directory and whether we're running alpine.
if grep "Alpine" /etc/issue > /dev/null 2>&1; then # Check if we're root
    if [ "$ID" = 0 ]; then export SUDO="sudo"; else export SUDO=""; fi
else
    if [ "$EUID" = 0 ]; then export SUDO=""; else export SUDO="sudo"; fi
fi

# If our first mkdir didn't succeed, we needed to run as sudo.
if [ ! -w "${JQ_EVAL_INSTALL_DIR}" ]; then
    $SUDO mkdir -p "${JQ_EVAL_INSTALL_DIR}"
fi

echo "export PATH=$PATH:\"${JQ_EVAL_INSTALL_DIR}\"" >> "$BASH_ENV"
. "$BASH_ENV"

# check if jq needs to be installed
if command -v jq >> /dev/null 2>&1; then

    echo "jq is already installed..."

    if [ "${JQ_BOOL_OVERRIDE}" -eq 1 ]; then
    echo "removing it."
    $SUDO rm -f "$(command -v jq)"
    else
    echo "ignoring install request."
    exit 0
    fi
fi

# Set jq version
if [ "${JQ_STR_VERSION}" = "latest" ]; then
    JQ_VERSION=$(wget -q --server-response -O /dev/null "https://github.com/jqlang/jq/releases/latest" 2>&1 | awk '/^  Location: /{print $2}' | sed 's:.*/::')
    echo "Latest version of jq is $JQ_VERSION"
else
    JQ_VERSION="${JQ_STR_VERSION}"
fi

# extract version number
JQ_VERSION_NUMBER_STRING=$(echo "${JQ_VERSION}" | sed -E 's/-/ /')
JQ_VERSION_NUMBER="$(echo "$JQ_VERSION_NUMBER_STRING" | awk '{print $2}')"

# Set binary download URL for specified version
# handle mac version
if uname -a | grep Darwin > /dev/null 2>&1; then
    JQ_BINARY_URL="https://github.com/jqlang/jq/releases/download/${JQ_VERSION}/jq-osx-amd64"
else
    # linux version
    JQ_BINARY_URL="https://github.com/jqlang/jq/releases/download/${JQ_VERSION}/jq-linux64"
fi

jqBinary="jq-$PLATFORM"

if [ -d "$JQ_VERSION/sig" ]; then
    # import jq sigs

    if uname -a | grep Darwin > /dev/null 2>&1; then
    HOMEBREW_NO_AUTO_UPDATE=1 brew install gnupg coreutils

    PLATFORM=osx-amd64
    else
    if grep "Alpine" /etc/issue > /dev/null 2>&1; then
        $SUDO apk add gnupg > /dev/null 2>&1
    fi
    PLATFORM=linux64
    fi

    gpg --import "$JQ_VERSION/sig/jq-release.key" > /dev/null

    wget -q -O "$JQ_VERSION/sig/v$JQ_VERSION_NUMBER/jq-$PLATFORM" \
        --tries=3 --retry-connrefused "$JQ_BINARY_URL"

    # verify sha256sum, sig, install
    gpg --verify "$JQ_VERSION/sig/v$JQ_VERSION_NUMBER/jq-$PLATFORM.asc"

    cd "$JQ_VERSION/sig/v$JQ_VERSION_NUMBER" || exit

    grep "jq-$PLATFORM" "sha256sum.txt" > tmp_checksum.txt

    if grep "jq-$PLATFORM" "sha256sum.txt" -eq 0; then
        sha256sum -c tmp_checksum.txt
        status=$?

        rm tmp_checksum.txt

        if [ $status -eq 0 ]; then
            jqBinary="$JQ_VERSION/sig/v$JQ_VERSION_NUMBER/jq-$PLATFORM"
        else
            echo "Checksum verification failed. Please check checksum"
            exit 1
        fi
    else
        exit 1
    fi

    cd - >/dev/null || exit

else
    wget -O "$jqBinary" -q --tries=3 "$JQ_BINARY_URL"
fi

$SUDO mv "$jqBinary" "${JQ_EVAL_INSTALL_DIR}"/jq
$SUDO chmod +x "${JQ_EVAL_INSTALL_DIR}"/jq

# cleanup
[ -d "./$JQ_VERSION" ] && rm -rf "./$JQ_VERSION"

# verify version
echo "jq has been installed to $(which jq)"
echo "jq version:"
jq --version
