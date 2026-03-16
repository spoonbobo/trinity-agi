import type { Metadata } from "next";
import { Space_Mono, Space_Grotesk } from "next/font/google";
import "./globals.css";

const spaceMono = Space_Mono({
  variable: "--font-space-mono",
  subsets: ["latin"],
  weight: ["400", "700"],
});

const spaceGrotesk = Space_Grotesk({
  variable: "--font-space-grotesk",
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
});

export const metadata: Metadata = {
  title: "Trinity — One Brain. Every User.",
  description:
    "An empty screen. A single intelligence. Every person who connects teaches it something new. Private conversations, collective wisdom. The system doesn't exist until you speak.",
  openGraph: {
    title: "Trinity — One Brain. Every User.",
    description:
      "An empty screen. A single intelligence that grows with every user. Private conversations, collective wisdom.",
    type: "website",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className="dark">
      <body
        className={`${spaceMono.variable} ${spaceGrotesk.variable} antialiased bg-[#0a0a0a] text-[#e5e5e5]`}
      >
        {children}
      </body>
    </html>
  );
}
