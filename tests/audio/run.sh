#!/bin/sh
set -eu
image=${1:-sipserver-audio-test}
mkdir -p test-results
docker run --rm --network none --memory 512m --cpus 2 \
    -e TEST_ROOT=/results -e TEST_RESULTS=/results \
    --mount "type=bind,src=$PWD/test-results,dst=/results" \
    --entrypoint /bin/sh "$image" -ec '
        openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=audio-test.invalid \
            -keyout /results/key.pem -out /results/cert.pem >/dev/null 2>&1
        python3 /app/tests/audio/test_converter.py
        python3 /app/tests/audio/analyze.py > /results/analysis.json
        python3 /app/tests/audio/verify.py
    '
