FROM ghcr.io/cirruslabs/flutter:stable

WORKDIR /app

# Download fonts from GitHub releases (using archive links)
RUN mkdir -p fonts && \
    # --- IBM Plex Mono (monospace) ---
    curl -sL "https://github.com/IBM/plex/releases/download/v6.4.0/IBM-Plex-Mono.zip" -o /tmp/ibm.zip && \
    unzip -q /tmp/ibm.zip -d /tmp/ibm && \
    cp /tmp/ibm/IBM-Plex-Mono/fonts/complete/ttf/IBMPlexMono-Regular.ttf fonts/ && \
    cp /tmp/ibm/IBM-Plex-Mono/fonts/complete/ttf/IBMPlexMono-Bold.ttf fonts/ && \
    cp /tmp/ibm/IBM-Plex-Mono/fonts/complete/ttf/IBMPlexMono-Italic.ttf fonts/ && \
    rm -rf /tmp/ibm* && \
    # --- JetBrains Mono (monospace) ---
    curl -sL "https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip" -o /tmp/jb.zip && \
    unzip -q /tmp/jb.zip -d /tmp/jb && \
    cp /tmp/jb/fonts/ttf/JetBrainsMono-Regular.ttf fonts/ && \
    cp /tmp/jb/fonts/ttf/JetBrainsMono-Bold.ttf fonts/ && \
    cp /tmp/jb/fonts/ttf/JetBrainsMono-Italic.ttf fonts/ && \
    rm -rf /tmp/jb* && \
    # --- Inter (sans-serif, general/readable) ---
    curl -sL "https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip" -o /tmp/inter.zip && \
    unzip -q /tmp/inter.zip -d /tmp/inter && \
    cp /tmp/inter/extras/ttf/Inter-Regular.ttf fonts/ && \
    cp /tmp/inter/extras/ttf/Inter-Bold.ttf fonts/ && \
    cp /tmp/inter/extras/ttf/Inter-Italic.ttf fonts/ && \
    rm -rf /tmp/inter* && \
    # --- Geist Sans (sans-serif, modern geometric by Vercel) ---
    curl -sL "https://github.com/vercel/geist-font/releases/download/1.7.0/geist-font-1.7.0.zip" -o /tmp/geist.zip && \
    unzip -q /tmp/geist.zip -d /tmp/geist && \
    cp /tmp/geist/geist-font-1.7.0/fonts/Geist/ttf/Geist-Regular.ttf fonts/ && \
    cp /tmp/geist/geist-font-1.7.0/fonts/Geist/ttf/Geist-Bold.ttf fonts/ && \
    cp /tmp/geist/geist-font-1.7.0/fonts/Geist/ttf/Geist-RegularItalic.ttf fonts/ && \
    rm -rf /tmp/geist* && \
    # --- Monofur (monospace, playful rounded) ---
    curl -sL "https://github.com/chrissimpkins/codeface/raw/master/fonts/monofur/monof55.ttf" -o fonts/monofur-Regular.ttf && \
    curl -sL "https://github.com/chrissimpkins/codeface/raw/master/fonts/monofur/monof56.ttf" -o fonts/monofur-Bold.ttf

COPY pubspec.yaml pubspec.lock* ./
RUN flutter pub get

COPY . .
ARG GATEWAY_TOKEN=replace-me-with-a-real-token
ARG GATEWAY_WS_URL=ws://localhost/ws
ARG TERMINAL_WS_URL=ws://localhost/terminal/
ARG AUTH_SERVICE_URL=http://localhost
ARG SUPABASE_ANON_KEY=
RUN flutter build web --release \
    --dart-define=GATEWAY_TOKEN=$GATEWAY_TOKEN \
    --dart-define=GATEWAY_WS_URL=$GATEWAY_WS_URL \
    --dart-define=TERMINAL_WS_URL=$TERMINAL_WS_URL \
    --dart-define=AUTH_SERVICE_URL=$AUTH_SERVICE_URL \
    --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY

CMD ["cp", "-r", "/app/build/web/.", "/output/"]
