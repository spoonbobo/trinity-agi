FROM ghcr.io/cirruslabs/flutter:stable

WORKDIR /app
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
