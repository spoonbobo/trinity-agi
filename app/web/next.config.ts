import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  output: 'export',
  trailingSlash: true,
  images: { unoptimized: true },
  // Env vars available client-side (NEXT_PUBLIC_ prefix)
  // NEXT_PUBLIC_GATEWAY_WS_URL, NEXT_PUBLIC_TERMINAL_WS_URL,
  // NEXT_PUBLIC_AUTH_SERVICE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY
};

export default nextConfig;
