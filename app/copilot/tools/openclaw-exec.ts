import { tool } from "@opencode-ai/plugin"

export default tool({
  description:
    "Run an OpenClaw CLI command on a per-user OpenClaw pod via kubectl exec. " +
    "The pod name is derived from the OPENCLAW_POD env var (defaults to 'openclaw-tender-claw'). " +
    "Examples: 'status', 'models', 'sessions', 'health --json', 'skills list --json', 'doctor'.",
  args: {
    command: tool.schema
      .string()
      .describe(
        "The openclaw subcommand and arguments, e.g. 'status' or 'sessions --json'"
      ),
    pod: tool.schema
      .string()
      .optional()
      .describe(
        "Override the deployment name (e.g. 'openclaw-dev-team'). Defaults to OPENCLAW_POD env var."
      ),
  },
  async execute(args) {
    const podName = args.pod || process.env.OPENCLAW_POD || "openclaw-tender-claw"
    const namespace = process.env.OPENCLAW_NAMESPACE || "trinity"
    const parts = args.command.split(/\s+/)
    const result =
      await Bun.$`kubectl exec deploy/${podName} -n ${namespace} -- openclaw ${parts}`.text()
    return result.trim()
  },
})
