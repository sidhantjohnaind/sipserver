FROM debian:trixie-slim AS build
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential pkg-config python3 curl ca-certificates libssl-dev \
    libopencore-amrnb-dev libopencore-amrwb-dev libvo-amrwbenc-dev \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /build
RUN curl -fsSL https://github.com/pjsip/pjproject/archive/refs/tags/2.15.1.tar.gz -o pjproject.tar.gz \
    && echo '8f3bd99caf003f96ed8038b8a36031eb9d8cd9eaea1eaff7e01c2eef6bd55706  pjproject.tar.gz' | sha256sum -c - \
    && tar xzf pjproject.tar.gz
COPY docker/linux/patch_amr.py .
RUN python3 patch_amr.py
WORKDIR /build/pjproject-2.15.1
RUN printf '#define PJSIP_MAX_URL_SIZE 2048\n#define PJMEDIA_HAS_OPENCORE_AMRNB_CODEC 1\n#define PJMEDIA_HAS_OPENCORE_AMRWB_CODEC 1\n' > pjlib/include/pj/config_site.h
RUN ./configure --prefix=/opt/pj --disable-video --disable-sound \
    --disable-libyuv --disable-ffmpeg --disable-v4l2 --disable-opus \
    --disable-libwebrtc --disable-sdl --disable-openh264 --disable-vpx \
    --disable-gsm-codec --disable-speex-codec --disable-speex-aec \
    --disable-ilbc-codec --disable-g7221-codec \
    --disable-l16-codec CFLAGS='-O2 -fPIC' CXXFLAGS='-O2 -fPIC'
RUN make dep && make -j2 lib && make install
COPY src/b2bua.cpp /build/b2bua.cpp
RUN g++ -std=c++17 -O2 /build/b2bua.cpp -o /build/b2bua \
    $(PKG_CONFIG_PATH=/opt/pj/lib/pkgconfig pkg-config --cflags --libs --static libpjproject)

FROM build AS reference-build
COPY tests/audio/reference_resample.c /build/reference_resample.c
RUN gcc -O2 /build/reference_resample.c -o /build/reference-resample \
    $(PKG_CONFIG_PATH=/opt/pj/lib/pkgconfig pkg-config --cflags --libs --static libpjproject)

FROM debian:trixie-slim AS runtime-deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl3t64 libstdc++6 ca-certificates \
    libopencore-amrnb0 libopencore-amrwb0 libvo-amrwbenc0 \
    && rm -rf /var/lib/apt/lists/*
USER 65532:65532
WORKDIR /config
ENTRYPOINT ["/usr/local/bin/b2bua"]

FROM runtime-deps AS test-deps
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-numpy ffmpeg openssl && rm -rf /var/lib/apt/lists/*
FROM test-deps AS test
COPY --from=reference-build /build/reference-resample /usr/local/bin/reference-resample
COPY --from=build /build/b2bua /usr/local/bin/b2bua
COPY tests/audio /app/tests/audio

FROM runtime-deps AS runtime
COPY --from=build /build/b2bua /usr/local/bin/b2bua
