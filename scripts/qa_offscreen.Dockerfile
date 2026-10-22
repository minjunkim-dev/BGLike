# Offscreen Forward+ QA for scripts/manual_qa.py: Xvfb + Mesa llvmpipe Vulkan, no macOS window.
# Build context is scripts/, so the pinned Godot archive is checked by install_godot.sh.
FROM ubuntu:24.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates curl unzip xvfb xauth mesa-vulkan-drivers libvulkan1 libgl1 libegl1 \
    libxcursor1 libxinerama1 libxrandr2 libxi6 libxkbcommon0 libfontconfig1 libdbus-1-3 fonts-noto-cjk \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /opt/bglike
COPY godot.env godot_environment.sh install_godot.sh scripts/
RUN export GODOT_DIR=/opt/godot && bash scripts/install_godot.sh \
    && bash -c 'source scripts/godot_environment.sh && ln -s "$GODOT_BINARY" /usr/local/bin/godot'
