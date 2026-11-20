FROM debian:bookworm-slim

ARG picosdk_version
ARG picofido2_ref

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        git \
        ca-certificates \
        python3 \
        pkg-config \
        gcc-arm-none-eabi \
        libnewlib-arm-none-eabi \
        libstdc++-arm-none-eabi-newlib \
        libusb-1.0-0-dev \
    && rm -rf /var/lib/apt/lists/*

# clone pico-sdk
WORKDIR /src
RUN git clone --depth 1 --branch "$picosdk_version" https://github.com/raspberrypi/pico-sdk \
 && git -C pico-sdk submodule update --init --depth 1 # includes mbedtls for `seal`
ENV PICO_SDK_PATH=/src/pico-sdk

# clone librekeys/pico-fido2
RUN git clone https://github.com/librekeys/pico-fido2 \
 && git -C pico-fido2 checkout "$picofido2_ref" \
 && git -C pico-fido2 submodule update --init --recursive

# build firmware
RUN cmake -S pico-fido2 -B pico-fido2/build \
      -DPICO_BOARD=pico2 \
      -DENABLE_EDDSA=1 \
      -DCMAKE_BUILD_TYPE=MinSizeRel \
 && cmake --build pico-fido2/build -j"$(nproc)"

CMD ["sleep", "infinity"]
