'use client';

import { useState, useEffect, useCallback, useRef } from 'react';
import {
  ChevronLeft,
  ChevronRight,
  CheckCircle,
  Circle,
  Sparkles,
  Stethoscope,
  Settings,
  Terminal,
} from 'lucide-react';
import { ToastService } from '@/components/ui/Toast';
import { useTerminalStore, createScopedTerminalClient } from '@/lib/stores/terminal-store';
import { useAuthStore } from '@/lib/stores/auth-store';
import { TerminalView } from '@/components/terminal/TerminalView';

/* ------------------------------------------------------------------ */
/*  Types                                                              */
/* ------------------------------------------------------------------ */

type WizardStep = 'welcome' | 'status' | 'configure' | 'terminal';

const steps: WizardStep[] = ['welcome', 'status', 'configure', 'terminal'];

const stepMeta: Record<WizardStep, { label: string; Icon: typeof Sparkles }> = {
  welcome: { label: 'Welcome', Icon: Sparkles },
  status: { label: 'Status', Icon: Stethoscope },
  configure: { label: 'Configure', Icon: Settings },
  terminal: { label: 'Terminal', Icon: Terminal },
};

/* ------------------------------------------------------------------ */
/*  OnboardingWizard                                                   */
/* ------------------------------------------------------------------ */

interface OnboardingWizardProps {
  onComplete: () => void;
}

export function OnboardingWizard({ onComplete }: OnboardingWizardProps) {
  const mainClient = useTerminalStore((s) => s.client);
  const token = useAuthStore((s) => s.token);
  const role = useAuthStore((s) => s.role);
  const activeOpenClawId = useAuthStore((s) => s.activeOpenClawId);

  const [currentStep, setCurrentStep] = useState<WizardStep>('welcome');
  const currentIndex = steps.indexOf(currentStep);

  // Scoped terminal client for wizard
  const scopedClientRef = useRef(
    createScopedTerminalClient(token ?? '', role, activeOpenClawId),
  );

  useEffect(() => {
    const sc = scopedClientRef.current;
    sc.token = token ?? '';
    sc.openClawId = activeOpenClawId;
    sc.connect().catch(() => {});
    return () => sc.disconnect();
  }, [token, activeOpenClawId]);

  /* ---------------------------------------------------------------- */
  /*  Status step: run doctor                                          */
  /* ---------------------------------------------------------------- */

  const [doctorOutput, setDoctorOutput] = useState<string>('');
  const [doctorLoading, setDoctorLoading] = useState(false);

  const runDoctor = useCallback(async () => {
    setDoctorLoading(true);
    try {
      await scopedClientRef.current.connect();
      const output = await scopedClientRef.current.executeCommandForOutput('doctor');
      setDoctorOutput(output);
    } catch (err: any) {
      setDoctorOutput(`Error: ${err.message ?? 'Failed to run doctor'}`);
    } finally {
      setDoctorLoading(false);
    }
  }, []);

  useEffect(() => {
    if (currentStep === 'status') runDoctor();
  }, [currentStep, runDoctor]);

  /* ---------------------------------------------------------------- */
  /*  Configure step: quick links                                      */
  /* ---------------------------------------------------------------- */

  const quickLinks = [
    { label: 'Configure providers', cmd: 'configure --section providers' },
    { label: 'Validate config', cmd: 'config validate' },
    { label: 'View models', cmd: 'models' },
    { label: 'System health', cmd: 'health' },
  ];

  const [configOutput, setConfigOutput] = useState<string>('');
  const [configLoading, setConfigLoading] = useState(false);

  const runConfigCommand = useCallback(async (cmd: string) => {
    setConfigLoading(true);
    try {
      await scopedClientRef.current.connect();
      const output = await scopedClientRef.current.executeCommandForOutput(cmd);
      setConfigOutput(output);
    } catch (err: any) {
      setConfigOutput(`Error: ${err.message ?? 'Failed to execute command'}`);
    } finally {
      setConfigLoading(false);
    }
  }, []);

  useEffect(() => {
    if (currentStep === 'configure') {
      runConfigCommand('configure --section providers');
    }
  }, [currentStep, runConfigCommand]);

  /* ---------------------------------------------------------------- */
  /*  Navigation                                                       */
  /* ---------------------------------------------------------------- */

  const canGoBack = currentIndex > 0;
  const canGoNext = currentIndex < steps.length - 1;
  const isLast = currentIndex === steps.length - 1;

  const goBack = () => {
    if (canGoBack) setCurrentStep(steps[currentIndex - 1]);
  };
  const goNext = () => {
    if (canGoNext) setCurrentStep(steps[currentIndex + 1]);
  };
  const finish = () => {
    ToastService.showInfo('Setup complete');
    onComplete();
  };

  /* ---------------------------------------------------------------- */
  /*  Render                                                           */
  /* ---------------------------------------------------------------- */

  return (
    <div className="flex h-full flex-col bg-surface-base">
      {/* Step indicators (top bar) */}
      <div className="flex items-center justify-center gap-1 border-b border-border-shell py-3">
        {steps.map((step, i) => {
          const { label, Icon } = stepMeta[step];
          const isActive = step === currentStep;
          const isDone = i < currentIndex;

          return (
            <button
              key={step}
              onClick={() => setCurrentStep(step)}
              className={`flex items-center gap-1.5 px-3 py-1 text-xs transition-colors ${
                isActive
                  ? 'text-accent-primary'
                  : isDone
                    ? 'text-fg-secondary'
                    : 'text-fg-muted'
              }`}
            >
              {isDone ? (
                <CheckCircle size={12} className="text-accent-primary" />
              ) : isActive ? (
                <Icon size={12} />
              ) : (
                <Circle size={12} />
              )}
              {label}
              {i < steps.length - 1 && (
                <ChevronRight size={10} className="ml-2 text-fg-disabled" />
              )}
            </button>
          );
        })}
      </div>

      {/* Step content */}
      <div className="flex-1 overflow-y-auto p-6">
        {currentStep === 'welcome' && <WelcomeStep />}
        {currentStep === 'status' && (
          <StatusStep
            output={doctorOutput}
            loading={doctorLoading}
            onRetry={runDoctor}
          />
        )}
        {currentStep === 'configure' && (
          <ConfigureStep
            quickLinks={quickLinks}
            output={configOutput}
            loading={configLoading}
            onRunCommand={runConfigCommand}
          />
        )}
        {currentStep === 'terminal' && (
          <TerminalStep client={scopedClientRef.current} />
        )}
      </div>

      {/* Navigation bar (bottom) */}
      <div className="flex items-center justify-between border-t border-border-shell px-6 py-3">
        <button
          onClick={goBack}
          disabled={!canGoBack}
          className="flex items-center gap-1 text-xs text-fg-muted hover:text-fg-secondary disabled:text-fg-disabled"
        >
          <ChevronLeft size={12} />
          back
        </button>
        <div className="text-[10px] text-fg-muted">
          {currentIndex + 1} / {steps.length}
        </div>
        {isLast ? (
          <button
            onClick={finish}
            className="flex items-center gap-1 border border-accent-primary px-3 py-1 text-xs text-accent-primary hover:bg-accent-primary-muted"
          >
            finish
          </button>
        ) : (
          <button
            onClick={goNext}
            disabled={!canGoNext}
            className="flex items-center gap-1 text-xs text-fg-muted hover:text-fg-secondary disabled:text-fg-disabled"
          >
            next
            <ChevronRight size={12} />
          </button>
        )}
      </div>
    </div>
  );
}

/* ================================================================== */
/*  Step: Welcome                                                      */
/* ================================================================== */

function WelcomeStep() {
  return (
    <div className="mx-auto max-w-lg pt-8">
      <div className="mb-6 flex items-center gap-3">
        <Sparkles size={20} className="text-accent-primary" />
        <h2 className="text-sm font-medium text-fg-primary">Welcome to Trinity</h2>
      </div>
      <div className="flex flex-col gap-4 text-xs text-fg-secondary leading-relaxed">
        <p>
          Trinity is your Universal Command Center — a featureless shell that becomes
          whatever you need. This setup wizard will help you verify your environment
          and configure the essentials.
        </p>
        <p>
          The wizard walks through four steps:
        </p>
        <ul className="flex flex-col gap-2 pl-4">
          <li className="flex items-start gap-2">
            <Stethoscope size={12} className="mt-0.5 shrink-0 text-fg-muted" />
            <span><strong className="text-fg-primary">Status</strong> — run diagnostics to check your environment</span>
          </li>
          <li className="flex items-start gap-2">
            <Settings size={12} className="mt-0.5 shrink-0 text-fg-muted" />
            <span><strong className="text-fg-primary">Configure</strong> — set up providers and API keys</span>
          </li>
          <li className="flex items-start gap-2">
            <Terminal size={12} className="mt-0.5 shrink-0 text-fg-muted" />
            <span><strong className="text-fg-primary">Terminal</strong> — run any command to finalize your setup</span>
          </li>
        </ul>
        <p className="text-fg-muted">
          Click <strong className="text-fg-secondary">next</strong> to begin.
        </p>
      </div>
    </div>
  );
}

/* ================================================================== */
/*  Step: Status                                                       */
/* ================================================================== */

function StatusStep({
  output,
  loading,
  onRetry,
}: {
  output: string;
  loading: boolean;
  onRetry: () => void;
}) {
  return (
    <div className="mx-auto max-w-2xl">
      <div className="mb-4 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Stethoscope size={14} className="text-accent-primary" />
          <span className="text-xs font-medium text-fg-primary">System Status</span>
        </div>
        <button
          onClick={onRetry}
          className="flex items-center gap-1 text-[10px] text-fg-muted hover:text-fg-secondary"
        >
          <CheckCircle size={10} />
          re-run
        </button>
      </div>
      <div className="border border-border-shell bg-surface-card p-4">
        {loading ? (
          <div className="flex items-center gap-2 text-xs text-fg-muted">
            <div className="h-3 w-3 animate-spin rounded-full border border-fg-muted border-t-transparent" />
            Running doctor...
          </div>
        ) : (
          <pre className="whitespace-pre-wrap font-mono text-[10px] text-fg-secondary leading-relaxed select-text">
            {output || '(no output)'}
          </pre>
        )}
      </div>
    </div>
  );
}

/* ================================================================== */
/*  Step: Configure                                                    */
/* ================================================================== */

function ConfigureStep({
  quickLinks,
  output,
  loading,
  onRunCommand,
}: {
  quickLinks: Array<{ label: string; cmd: string }>;
  output: string;
  loading: boolean;
  onRunCommand: (cmd: string) => void;
}) {
  return (
    <div className="mx-auto max-w-2xl">
      <div className="mb-4 flex items-center gap-2">
        <Settings size={14} className="text-accent-primary" />
        <span className="text-xs font-medium text-fg-primary">Configuration</span>
      </div>

      {/* Quick links */}
      <div className="mb-4 flex flex-wrap gap-2">
        {quickLinks.map((link) => (
          <button
            key={link.cmd}
            onClick={() => onRunCommand(link.cmd)}
            className="border border-border-shell px-2.5 py-1 text-[10px] text-fg-muted hover:text-accent-primary hover:border-accent-primary"
          >
            {link.label}
          </button>
        ))}
      </div>

      {/* Output */}
      <div className="border border-border-shell bg-surface-card p-4">
        {loading ? (
          <div className="flex items-center gap-2 text-xs text-fg-muted">
            <div className="h-3 w-3 animate-spin rounded-full border border-fg-muted border-t-transparent" />
            Executing...
          </div>
        ) : (
          <pre className="whitespace-pre-wrap font-mono text-[10px] text-fg-secondary leading-relaxed select-text">
            {output || '(run a command above)'}
          </pre>
        )}
      </div>
    </div>
  );
}

/* ================================================================== */
/*  Step: Terminal                                                     */
/* ================================================================== */

function TerminalStep({ client }: { client: any }) {
  const suggestedCommands = [
    'status',
    'health',
    'models',
    'doctor',
    'config validate',
    'skills list',
  ];

  return (
    <div className="mx-auto flex h-full max-w-2xl flex-col">
      <div className="mb-4 flex items-center gap-2">
        <Terminal size={14} className="text-accent-primary" />
        <span className="text-xs font-medium text-fg-primary">Terminal</span>
      </div>
      <p className="mb-4 text-[10px] text-fg-muted">
        Run any command to finalize your setup. Try the suggestions below or type your own.
      </p>
      <div className="flex-1 min-h-0 border border-border-shell bg-surface-card">
        <TerminalView
          client={client}
          showInput
          suggestedCommands={suggestedCommands}
        />
      </div>
    </div>
  );
}
