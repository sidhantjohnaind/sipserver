#!/bin/sh
set -eu
image=${1:-sipserver-audio-test}
results=${AUDIO_RESULTS_DIR:-test-results/wideband}
mkdir -p "$results"
results=$(cd "$results" && pwd)
docker run --rm --network none --memory 512m --cpus 2 \
    -e TEST_ROOT=/results \
    --mount "type=bind,src=$results,dst=/results" \
    --entrypoint /bin/sh "$image" -ec '
        openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=audio-test.invalid \
            -keyout /results/key.pem -out /results/cert.pem >/dev/null 2>&1
        python3 /app/tests/audio/wideband.py
    '
