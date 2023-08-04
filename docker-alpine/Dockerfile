FROM alpine

RUN true \
    && apk add --no-cache \
         fontconfig-static \
         fontconfig \
         fontconfig-dev \
         expat-static \
         ca-certificates \
         curl \
         xz \
    && curl https://ziglang.org/download/0.11.0/zig-linux-x86_64-0.11.0.tar.xz | tar -C /usr/local/ -xJ \
    && apk del curl xz  \
    && ln -s /usr/local/zig*/zig /usr/local/bin \
    && true

ENTRYPOINT ["/usr/local/bin/zig"]
