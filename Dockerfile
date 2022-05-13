# This dockerfile defines two docker images, namely the base image used for
# distribution as well as an extended image used for building the code through
# `dazel`.

FROM ubuntu:latest AS respect-base-image

RUN apt-get update && apt-get install -y \
    python-is-python3 \
    && rm -rf /var/lib/apt/lists/* \
    # Confirm that python3 is installed.
    && test -e /usr/bin/python3 \
    # And that "python" (aka python3) is installed.
    && test -e /usr/bin/python

# Support running asan builds: install a version libasan that matches the
# installed gcc (gcc-9 on focal https://packages.ubuntu.com/focal/gcc).
# libasan6 is for gcc9: https://askubuntu.com/a/1024068
# TODO(alexmc): Should this be pre-installed with GCC?
# TODO(alexmc): Shouldn't we be installing libasan6 per above, not libasan5?
# Why are gcc9-built binaries looking for libasan5?
RUN apt-get update && apt-get install -y \
    libasan5 \
    && rm -rf /var/lib/apt/lists/*


FROM respect-base-image AS dazel-respect

# This should match the company-wide bazel version in eventuals:
# https://github.com/3rdparty/eventuals/blob/main/Dockerfile.dazel
ARG BAZEL_VERSION=5.1.1
ARG CLANG_VERSION=14

RUN apt-get update \
    # Install various prerequisite packages need for building as well as
    # packages that aid developing and debugging.
    #
    # As the list/version of packages is not changing too often, we optimize
    # for image layer size and run all `apt` related commands (that includes
    # the invokation of `llvm.sh`) in one `RUN` statement.
    #
    # If you are adding packages to the list below, please add a comment here
    # as well.
    #
    # Additional mandatory packages we install:
    #  * autoconf: required to build cc_image targets (alexmc: I think!).
    #  * build-essential: get gcc and std headers.
    #  * ca-certificates: dependency for curl to make https calls.
    #  * curl: not strictly needed (while-false: I think) outside of image
    #    building but small (~100kb) and useful for debugging. Might be used
    #    internally by bazel to fetch `http_archives`.
    #  * gnupg: for image and package signing.
    #  * git: Used by `bazel` to fetch a `git_repository`.
    #  * lsb-release: to allow install scripts/(debugging )developers to figure
    #    out what system they are on.
    #  * make: required to build cc_image targets (alexmc: I think!).
    #  * openssh-client: much needed dependency of `git`.
    #  * python3-dev: python source code needed for building grpc bindings.
    #  * python3-distutils: for building and compiling python packages.
    #  * wget: see `curl`.
    #
    # Additional optional packages we install:
    #  * gdb: debugger
    #  * htop: replacement for top.
    #  * iputils-ping: to get `ping`.
    #  * vim: it's vi improved!
    #
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    # Mandatory packages:
    autoconf \
    build-essential \
    ca-certificates \
    curl \
    gnupg \
    git \
    lsb-release \
    make \
    openssh-client \
    python3-dev \
    python3-distutils \
    software-properties-common \
    wget \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    # Optional packages:
    gdb \
    htop \
    iputils-ping \
    vim \
    # Install docker. Instructions
    # https://docs.docker.com/engine/install/ubuntu/
    && curl -fsSL https://get.docker.com | sh \
    # Install Bazel. Instructions:
    # https://docs.bazel.build/versions/main/install-ubuntu.html
    && echo "deb [arch=amd64] http://storage.googleapis.com/bazel-apt stable jdk1.8" > \
    /etc/apt/sources.list.d/bazel.list \
    && curl -fsSL https://bazel.build/bazel-release.pub.gpg | apt-key add - \
    && apt-get update && apt-get install -y \
    bazel=${BAZEL_VERSION} \
    # Install clang. Instructions:
    # https://apt.llvm.org/
    && wget -O /tmp/llvm.sh "https://apt.llvm.org/llvm.sh" \
    && chmod +x /tmp/llvm.sh \
    && /tmp/llvm.sh ${CLANG_VERSION} \
    && rm /tmp/llvm.sh \
    # Make clang mean clang-xx
    && ln -s /usr/bin/clang-${CLANG_VERSION} /usr/bin/clang \
    # Cleanup.
    && apt-get purge --auto-remove -y \
    && rm -rf /etc/apt/sources.list.d/bazel.list \
    && rm -rf /var/lib/apt/lists/*


# Install k3d.io which we'll use to run integration tests inside this dazel
# container. See https://k3d.io/v5.3.0/#install-specific-release
ARG K3D_VERSION=v5.3.0
RUN curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | TAG=${K3D_VERSION} bash

# Install kubectl which we'll use to run integration tests. Must be compatible
# (+/- 1 version) with the k3d installation above.
# See https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/#install-kubectl-binary-with-curl-on-linux
ARG KUBECTL_VERSION=v1.23.0
RUN curl -LO  https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/kubectl

# Install Istio. Must match version in Makefile.
# See https://istio.io/latest/docs/setup/getting-started/
ARG ISTIO_VERSION=1.11.4
RUN curl -L https://istio.io/downloadIstio | ISTIO_VERSION=${ISTIO_VERSION} TARGET_ARCH=x86_64 sh - \
    && cd istio-${ISTIO_VERSION}/bin \
    && chmod +x istioctl \
    && mv istioctl /usr/local/bin/istioctl

# If no target is given, default to the base image
FROM respect-base-image
