export default function MinikubePage() {
  return (
    <div className="prose prose-invert max-w-none">
      <div className="mb-8">
        <span className="mb-4 inline-block font-mono text-[10px] tracking-[3px] text-[#6ee7b7]">
          GUIDES
        </span>
        <h1 className="mb-4 font-sans text-4xl font-bold tracking-tight text-[#e5e5e5]">
          Minikube
        </h1>
        <p className="font-sans text-lg text-[#8b8b8b]">
          Deploy the full Trinity platform on a local Kubernetes cluster for
          development and testing.
        </p>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Prerequisites
        </h2>
        <ul className="mb-8 space-y-3 font-sans text-sm text-[#8b8b8b]">
          <li className="flex items-center gap-3">
            <span className="font-mono text-[#6ee7b7]">&rarr;</span>
            Docker Desktop (running)
          </li>
          <li className="flex items-center gap-3">
            <span className="font-mono text-[#6ee7b7]">&rarr;</span>
            minikube, kubectl, helm &mdash; the setup script installs these
            automatically via Homebrew if missing
          </li>
          <li className="flex items-center gap-3">
            <span className="font-mono text-[#6ee7b7]">&rarr;</span>
            At least 7 GB RAM and 4 CPU cores available for the cluster
          </li>
        </ul>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          One-Command Setup
        </h2>
        <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
          <pre className="overflow-x-auto font-mono text-sm text-[#8b8b8b]">
            <code>{`./k8s/minikube-setup.sh all`}</code>
          </pre>
        </div>
        <p className="mt-4 font-sans text-sm leading-relaxed text-[#8b8b8b]">
          This single command runs the entire setup end-to-end:
        </p>
        <ul className="mt-4 space-y-2 pl-6 font-sans text-sm text-[#8b8b8b]">
          <li className="list-disc">
            Installs <code className="text-[#6ee7b7]">minikube</code>,{" "}
            <code className="text-[#6ee7b7]">kubectl</code>, and{" "}
            <code className="text-[#6ee7b7]">helm</code> via Homebrew if missing
          </li>
          <li className="list-disc">Starts Docker Desktop if needed</li>
          <li className="list-disc">
            Starts Minikube with the ingress addon enabled
          </li>
          <li className="list-disc">
            Builds all container images inside Minikube&apos;s Docker daemon
          </li>
          <li className="list-disc">
            Deploys the Helm chart into the{" "}
            <code className="text-[#6ee7b7]">trinity</code> namespace
          </li>
          <li className="list-disc">
            Runs database migrations and seeds secrets into Vault
          </li>
          <li className="list-disc">
            Bootstraps the default superadmin account
          </li>
        </ul>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Available Commands
        </h2>
        <div className="space-y-3">
          {[
            {
              cmd: "install-tools",
              desc: "Install minikube, kubectl, and helm via Homebrew",
            },
            {
              cmd: "start",
              desc: "Start Minikube cluster with ingress addon",
            },
            {
              cmd: "build",
              desc: "Build all container images inside Minikube's Docker daemon",
            },
            {
              cmd: "deploy",
              desc: "Helm install + database migrations + bootstrap admin account",
            },
            { cmd: "status", desc: "Show pod status in the trinity namespace" },
            {
              cmd: "teardown",
              desc: "Uninstall Helm release and delete namespace",
            },
            { cmd: "all", desc: "Run everything end-to-end (default)" },
          ].map((item) => (
            <div
              key={item.cmd}
              className="flex items-start gap-4 rounded-xl border border-[#2a2a2a] bg-[#141414] p-4"
            >
              <code className="shrink-0 font-mono text-sm text-[#6ee7b7]">
                {item.cmd}
              </code>
              <span className="font-sans text-sm text-[#8b8b8b]">
                {item.desc}
              </span>
            </div>
          ))}
        </div>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Access the App
        </h2>
        <p className="mb-4 font-sans text-sm text-[#8b8b8b]">
          Start the tunnel in a separate terminal and keep it running:
        </p>
        <div className="mb-6 rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
          <pre className="overflow-x-auto font-mono text-sm text-[#8b8b8b]">
            <code>{`minikube tunnel`}</code>
          </pre>
        </div>
        <p className="mb-4 font-sans text-sm text-[#8b8b8b]">
          Then open these URLs:
        </p>
        <div className="overflow-x-auto rounded-xl border border-[#2a2a2a]">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-[#2a2a2a] bg-[#141414]">
                <th className="px-4 py-3 text-left font-mono text-[10px] tracking-[2px] text-[#6b6b6b]">
                  URL
                </th>
                <th className="px-4 py-3 text-left font-mono text-[10px] tracking-[2px] text-[#6b6b6b]">
                  SERVICE
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-[#1a1a1a]">
              {[
                { url: "http://localhost", svc: "Trinity UI (Flutter shell)" },
                {
                  url: "http://site.localhost",
                  svc: "Marketing site (Next.js)",
                },
                {
                  url: "http://localhost/keycloak",
                  svc: "Keycloak admin console",
                },
                { url: "http://vault.localhost/ui/", svc: "Vault UI" },
                { url: "http://grafana.localhost", svc: "Grafana dashboards" },
                {
                  url: "http://loki.localhost/ready",
                  svc: "Loki readiness check",
                },
                { url: "http://lightrag.localhost", svc: "LightRAG API" },
              ].map((row) => (
                <tr key={row.url}>
                  <td className="px-4 py-2 font-mono text-xs text-[#6ee7b7]">
                    {row.url}
                  </td>
                  <td className="px-4 py-2 font-sans text-[#8b8b8b]">
                    {row.svc}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <div className="mt-6 rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
          <p className="mb-1 font-mono text-[10px] tracking-[2px] text-[#6b6b6b]">
            DEFAULT CREDENTIALS
          </p>
          <pre className="overflow-x-auto font-mono text-sm text-[#8b8b8b]">
            <code>{`Trinity admin:  admin@trinity.work / admin123
Keycloak admin: admin / trinity-kc-admin-123`}</code>
          </pre>
        </div>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Rebuilding Images
        </h2>
        <p className="mb-4 font-sans text-sm text-[#8b8b8b]">
          After code changes, rebuild the relevant image inside Minikube&apos;s
          Docker daemon and restart the deployment:
        </p>
        <div className="space-y-4">
          <div>
            <p className="mb-2 font-mono text-xs text-[#6b6b6b]">
              FRONTEND (Flutter)
            </p>
            <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
              <pre className="overflow-x-auto font-mono text-sm text-[#8b8b8b]">
                <code>{`eval $(minikube docker-env)
docker build --no-cache -t trinity-frontend:latest app/frontend/
kubectl rollout restart deployment/nginx -n trinity`}</code>
              </pre>
            </div>
          </div>
          <div>
            <p className="mb-2 font-mono text-xs text-[#6b6b6b]">
              SITE (Next.js)
            </p>
            <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
              <pre className="overflow-x-auto font-mono text-sm text-[#8b8b8b]">
                <code>{`eval $(minikube docker-env)
docker build --no-cache -t trinity-site:latest site/
kubectl rollout restart deployment/site -n trinity`}</code>
              </pre>
            </div>
          </div>
          <div>
            <p className="mb-2 font-mono text-xs text-[#6b6b6b]">
              BACKEND SERVICES
            </p>
            <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
              <pre className="overflow-x-auto font-mono text-sm text-[#8b8b8b]">
                <code>{`eval $(minikube docker-env)
docker build -t trinity-auth-service:latest app/auth-service/
kubectl rollout restart deployment/auth-service -n trinity`}</code>
              </pre>
            </div>
          </div>
        </div>
      </div>

      <div className="mt-12 rounded-xl border border-[#6ee7b7]/20 bg-[#0a1a10] p-6">
        <h3 className="mb-2 font-mono text-xs tracking-[2px] text-[#6ee7b7]">
          NEXT STEPS
        </h3>
        <p className="font-sans text-sm text-[#8b8b8b]">
          Read the{" "}
          <a
            href="/docs/configuration"
            className="text-[#6ee7b7] underline"
          >
            Configuration
          </a>{" "}
          guide to customise secrets, RBAC, and LLM providers, or the{" "}
          <a
            href="/docs/architecture"
            className="text-[#6ee7b7] underline"
          >
            Architecture
          </a>{" "}
          guide to understand the service topology.
        </p>
      </div>
    </div>
  );
}
