# syntax=docker/dockerfile:1

# ---- Build stage --------------------------------------------------------
# Pin the builder to the same Go line as go.mod (1.26). A builder older than the
# module's `go` directive refuses to compile, so this tag must track go.mod.
FROM golang:1.26 AS build
WORKDIR /src

# Copy only the manifests first, then download modules. Docker caches each layer;
# keeping this step dependent on just go.mod/go.sum means edits to application
# source reuse the cached download instead of re-fetching every dependency.
COPY go.mod go.sum ./
RUN go mod download

# Now bring in the rest of the source and compile.
# CGO_ENABLED=0 forces a statically linked binary (no libc), which is what lets
# it run on the distroless runtime image. GOOS/GOARCH pin the target to Fargate's
# linux/amd64. -ldflags "-s -w" strips debug info to shrink the binary.
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -ldflags="-s -w" -o /app ./cmd/server

# ---- Runtime stage ------------------------------------------------------
# A fresh, near-empty image is all that ships. distroless/static has no shell,
# no package manager, and no libc, so a static binary is all it can (and needs
# to) run. The :nonroot tag runs as an unprivileged user (uid 65532), so a
# container breakout does not land as root.
FROM gcr.io/distroless/static:nonroot

# Bridge across the stage boundary: pull ONLY the compiled binary out of the
# build stage. The toolchain, source, and module cache are all left behind.
COPY --from=build /app /app

# Documentation only: declares the port the service listens on (main.go binds
# :8080). It does not publish the port; orchestrators read this as metadata.
EXPOSE 8080

# Run-time command (contrast with RUN, which is build-time). The exec form runs
# the binary directly as PID 1 with no shell wrapper, which distroless lacks
# anyway.
ENTRYPOINT ["/app"]
