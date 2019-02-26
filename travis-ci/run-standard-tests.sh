#!/bin/bash
set -e

display_and_run() {
    echo "***" "$@"
	eval $(printf '%q ' "$@")
}

# reset workdir to state from git (to remove possible rewritten dependencies)
display_and_run git reset --hard

# Fmt check
echo "*** go fmt ./..."
find . -name '*.go' -exec gofmt -l {} + > go-fmt.out
if [[ -s go-fmt.out ]]; then
	echo "ERROR: some files not gofmt'ed:"
	cat go-fmt.out
	exit 1
fi


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
    # OSX has a default file limit of 256, for some tests we need a
    # maximum of 8192.
    ulimit -Sn 8192
fi

: "${BUILD_DEPTYPE:=gx}"
case $BUILD_DEPTYPE in
gx)
    echo "*** Installing gx"
    display_and_run go get github.com/whyrusleeping/gx
    display_and_run go get github.com/whyrusleeping/gx-go
    export GO111MODULE=off
	echo "*** Installing gx deps and rewriting"
    display_and_run gx install --nofancy
    display_and_run gx-go rw
    ;;
gomod)
    export GO111MODULE=on
    ;;
*)
    echo "Unknown dependency build type: $BUILD_DEPTYPE"
    exit 2
    ;;
esac




list_buildable() {
    go list -f '{{if (len .GoFiles)}}{{.ImportPath}} {{if .Module}}{{.Module.Dir}}{{else}}{{.Dir}}{{end}}{{end}}' ./... | grep -v /vendor/
}

build_all() {
    # Make sure everything can compile since some package may not have tests
    # Note: that "go build ./..." will fail if some packages have only
    #   tests (will get "no buildable Go source files" error) so we
    #   have to do this the hard way.
    list_buildable | while read -r pkg dir; do
        echo '*** go build' "$pkg"
        ( cd "$dir"; go build -o /dev/null "$pkg")
    done
}

list_testable() {
    go list -f '{{if or (len .TestGoFiles) (len .XTestGoFiles)}}{{.ImportPath}}{{end}}' ./... | grep -v /vendor/ || true
}

# Test
if [[ "$TRAVIS_OS_NAME" == "linux" ]]; then
    # build all packages in the repo
    build_all

    list_testable > packages-with-tests
    # Run tests with coverage report in each packages that has tests
    if [[ -s packages-with-tests ]]; then
        while read -r pkg; do
            profile="coverage.$(echo "$pkg" | md5sum | head -c 16).txt"
            display_and_run go test -v "${GOTFLAGS[@]}" -coverprofile="$profile" -covermode=atomic "$pkg"
        done < packages-with-tests

        # Doesn't count as a failure.
        echo "*** Processing coverage report"
        bash <(curl -s https://codecov.io/bash) || echo "Uploading to codecov failed"
    else
        echo "*** No tests!!!"
    fi
else
    build_all
    display_and_run go test -v "${GOTFLAGS[@]}" ./...
fi
