set -e

display_and_run() {
  echo "*** $@"
  "$@"
}

# Vet
display_and_run go vet ./...

# Test
if [[ "$TRAVIS_OS_NAME" == "linux" ]]; then
    # Make sure everything can compile since some package may not have tests
    display_and_run go build ./...
    # Run tests with coverage report in each packages that has tests
    go list -f '{{if (len .TestGoFiles)}}{{.ImportPath}}{{end}}' ./... | grep -v /vendor > packages-with-tests || true
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
