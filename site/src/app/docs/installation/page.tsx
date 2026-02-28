export default function InstallationPage() {
  return (
    <div className="prose prose-invert max-w-none">
      <div className="mb-8">
        <span className="mb-4 inline-block font-mono text-[10px] tracking-[3px] text-[#6ee7b7]">
          SETUP
        </span>
        <h1 className="mb-4 font-sans text-4xl font-bold tracking-tight text-[#e5e5e5]">
          Installation
        </h1>
        <p className="font-sans text-lg text-[#8b8b8b]">
          Detailed installation instructions for all platforms.
        </p>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          System Requirements
        </h2>
        <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
          <ul className="space-y-3 font-sans text-sm text-[#8b8b8b]">
            <li className="flex items-center gap-3">
              <span className="font-mono text-[#6ee7b7]">CPU:</span>
              2+ cores recommended
            </li>
            <li className="flex items-center gap-3">
              <span className="font-mono text-[#6ee7b7]">RAM:</span>
              4GB minimum, 8GB recommended
            </li>
            <li className="flex items-center gap-3">
              <span className="font-mono text-[#6ee7b7]">Storage:</span>
              1GB for application + memory storage
            </li>
            <li className="flex items-center gap-3">
              <span className="font-mono text-[#6ee7b7]">Network:</span>
              Outbound HTTPS for API calls
            </li>
          </ul>
        </div>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Docker Installation
        </h2>
        <p className="mb-6 font-sans text-sm text-[#8b8b8b]">
          The easiest way to run Trinity AGI is using Docker:
        </p>
        <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
          <pre className="overflow-x-auto font-mono text-sm text-[#8b8b8b]">
            <code>{`# Pull the latest image
docker pull spoonbobo/trinity-agi:latest

# Run the container
docker run -d \\
  -p 3000:3000 \\
  -e OPENAI_API_KEY=sk-... \\
  -v trinity-data:/app/data \\
  spoonbobo/trinity-agi:latest`}</code>
          </pre>
        </div>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Manual Installation
        </h2>
        <p className="mb-6 font-sans text-sm text-[#8b8b8b]">
          For development or custom setups:
        </p>
        <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
          <pre className="overflow-x-auto font-mono text-sm text-[#8b8b8b]">
            <code>{`# Clone repository
git clone https://github.com/spoonbobo/trinity-agi/
cd trinity-agi

# Install Node dependencies
npm install

# Build the project
npm run build

# Start the server
npm start`}</code>
          </pre>
        </div>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Verifying Installation
        </h2>
        <p className="mb-6 font-sans text-sm text-[#8b8b8b]">
          After installation, verify Trinity AGI is running:
        </p>
        <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
          <pre className="overflow-x-auto font-mono text-sm text-[#8b8b8b]">
            <code>{`# Check health endpoint
curl http://localhost:3000/api/health

# Expected response:
# { "status": "healthy", "version": "0.1.0" }`}</code>
          </pre>
        </div>
      </div>
    </div>
  );
}
