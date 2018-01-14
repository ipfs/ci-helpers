#!/bin/bash
set -e

display_and_run() {
  echo "***" "$@"
  "$@"
}

# Fmt check
GITDIR="$(pwd)"
display_and_run cd "$(mktemp -d)"
display_and_run git -c advice.detachedHead=false clone -q -s "$GITDIR" .
echo "*** go fmt ./..." &&
go fmt ./... > go-fmt.out &&
if [[ -s go-fmt.out ]]; then
    echo "ERROR: some files not gofmt'ed:"
    cat go-fmt.out
    exit 1
fi
display_and_run cd "$GITDIR"
echo

# Vet
: "${GOVETCMD:=go vet}"
display_and_run $GOVETCMD ./...
echo

# Environment
echo "*** Setting up test environment"
if [[ "$TRAVIS_OS_NAME" == "linux" ]]; then
    if [[ "$TRAVIS_SUDO" == true ]]; then
        # Ensure that IPv6 is enabled.
        # While this is unsupported by TravisCI, it still works for localhost.
        sudo sysctl -w net.ipv6.conf.lo.disable_ipv6=0
        sudo sysctl -w net.ipv6.conf.default.disable_ipv6=0
        sudo sysctl -w net.ipv6.conf.all.disable_ipv6=0
    fi
else
    if [[ "$TRAVIS_SUDO" == true ]]; then
        # OSX has a default file limit of 256, for some tests we need a
        # maximum of 8192.
        sudo launchctl limit maxfiles 8192 8192
        ulimit -n 8192
    fi
fi

# Test
if [[ "$TRAVIS_OS_NAME" == "linux" ]]; then
    # Make sure everything can compile since some package may not have tests
    # Note: that "go build ./..." will fail if some packages have only
    #   tests (will get "no buildable Go source files" error) so we
    #   have to do this the hard way.
    go list -f '{{if (len .GoFiles)}}{{.ImportPath}}{{end}}' ./... | grep -v /vendor/ | \
        while read pkg; do
            (
                cd "$(mktemp -d)" && display_and_run go build "$pkg"
            )
        done
    echo
    # Run tests with coverage report in each packages that has tests
    go list -f '{{if (len .TestGoFiles)}}{{.ImportPath}}{{end}}' ./... | grep -v /vendor/ > packages-with-tests || true
    if [[ -s packages-with-tests ]]; then
        cat packages-with-tests | while read pkg; do
            profile="coverage.$(echo "$pkg" | md5sum | head -c 16).txt"
            display_and_run go test -v $GOTFLAGS -coverprofile="$profile" -covermode=atomic "$pkg"
        done
        # Doesn't count as a failure.
        echo "*** Processing coverage report"
        bash <(curl -s https://codecov.io/bash) || true
    else
        echo "*** No tests!"
    fi
else
    display_and_run go test -v $GOTFLAGS ./...
fi
