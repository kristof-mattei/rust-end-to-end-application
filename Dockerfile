FROM --platform=$BUILDPLATFORM rust:1.79.0@sha256:2c454db58842de39b18057df0617d24eb4f94f77d99ea8dfc0788387d0c9dc81 as builder

ARG TARGET=x86_64-unknown-linux-musl
ARG APPLICATION_NAME

RUN rustup target add ${TARGET}

RUN rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

# borrowed (Ba Dum Tss!) from
# https://github.com/pablodeymo/rust-musl-builder/blob/7a7ea3e909b1ef00c177d9eeac32d8c9d7d6a08c/Dockerfile#L48-L49
RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt \
    dpkg --add-architecture arm64 && \
    apt-get update && \
    apt-get --no-install-recommends install -y \
    build-essential \
    musl-dev \
    musl-tools \
    libc6-dev-arm64-cross \
    gcc-aarch64-linux-gnu

# The following block
# creates an empty app, and we copy in Cargo.toml and Cargo.lock as they represent our dependencies
# This allows us to copy in the source in a different layer which in turn allows us to leverage Docker's layer caching
# That means that if our dependencies don't change rebuilding is much faster
WORKDIR /build
RUN cargo new ${APPLICATION_NAME}
WORKDIR /build/${APPLICATION_NAME}
COPY .cargo ./.cargo
COPY Cargo.toml Cargo.lock ./
RUN --mount=type=cache,id=cargo-dependencies,target=/build/${APPLICATION_NAME}/target \
    cargo build --release --target ${TARGET}

# now we copy in the source which is more prone to changes and build it
COPY src ./src

# --release not needed, it is implied with install
RUN --mount=type=cache,id=full-build,target=/build/${APPLICATION_NAME}/target \
    cargo install --path . --target ${TARGET} --root /output

FROM alpine:3.13.4@sha256:ec14c7992a97fc11425907e908340c6c3d6ff602f5f13d899e6b7027c9b4133a

ARG APPLICATION_NAME

RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

WORKDIR /app
COPY --from=builder /output/bin/${APPLICATION_NAME} /app/entrypoint

ENV RUST_BACKTRACE=full
ENTRYPOINT ["/app/entrypoint"]
