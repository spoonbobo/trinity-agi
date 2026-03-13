'use client';

import { AppUpdateGate } from '@/components/shell/AppUpdateGate';
import { AuthGuard } from '@/components/auth/AuthGuard';
import { ShellPage } from '@/components/shell/ShellPage';
import { ToastContainer } from '@/components/ui/Toast';

export default function Home() {
  return (
    <AppUpdateGate>
      <AuthGuard>
        <ShellPage />
      </AuthGuard>
      <ToastContainer />
    </AppUpdateGate>
  );
}
