FROM ghcr.io/cirruslabs/flutter:stable

WORKDIR /app

# Download fonts from GitHub releases (using archive links)
RUN mkdir -p fonts && \
    curl -sL "https://github.com/IBM/plex/releases/download/v6.4.0/IBM-Plex-Mono.zip" -o /tmp/ibm.zip && \
    unzip -q /tmp/ibm.zip -d /tmp/ibm && \
    cp /tmp/ibm/IBM-Plex-Mono/fonts/complete/ttf/IBMPlexMono-Regular.ttf fonts/ && \
    cp /tmp/ibm/IBM-Plex-Mono/fonts/complete/ttf/IBMPlexMono-Bold.ttf fonts/ && \
    cp /tmp/ibm/IBM-Plex-Mono/fonts/complete/ttf/IBMPlexMono-Italic.ttf fonts/ && \
    rm -rf /tmp/ibm* && \
    curl -sL "https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip" -o /tmp/jb.zip && \
    unzip -q /tmp/jb.zip -d /tmp/jb && \
    cp /tmp/jb/fonts/ttf/JetBrainsMono-Regular.ttf fonts/ && \
    cp /tmp/jb/fonts/ttf/JetBrainsMono-Bold.ttf fonts/ && \
    cp /tmp/jb/fonts/ttf/JetBrainsMono-Italic.ttf fonts/ && \
    rm -rf /tmp/jb*

COPY pubspec.yaml pubspec.lock* ./
RUN flutter pub get

COPY . .
ARG GATEWAY_TOKEN=replace-me-with-a-real-token
ARG TERMINAL_WS_URL=ws://localhost/terminal/
ARG AUTH_SERVICE_URL=http://localhost
ARG SUPABASE_ANON_KEY=
RUN flutter build web --release \
    --dart-define=GATEWAY_TOKEN=$GATEWAY_TOKEN \
    --dart-define=TERMINAL_WS_URL=$TERMINAL_WS_URL \
    --dart-define=AUTH_SERVICE_URL=$AUTH_SERVICE_URL \
    --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY

CMD ["cp", "-r", "/app/build/web/.", "/output/"]
