FROM debian:bullseye

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
         libfontconfig-dev \
         ca-certificates \
         curl \
         xz-utils \
    && curl https://ziglang.org/download/0.11.0/zig-linux-x86_64-0.11.0.tar.xz | tar -C /usr/local/ -xJ \
    && apt-get -y remove curl xz-utils  \
    && ln -s /usr/local/zig*/zig /usr/local/bin \
    && rm -rf /var/lib/apt/lists/*

ENTRYPOINT ["/usr/local/bin/zig"]
