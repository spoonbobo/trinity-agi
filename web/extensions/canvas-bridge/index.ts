const A2UI_MARKER = "__A2UI__";

export default function register(api: any) {
  let latestSurface: string | null = null;

  api.registerTool({
    name: "canvas_ui",
    description: `Render visual content in the Canvas panel. MANDATORY for any UI output — never describe UI in chat text. Pass A2UI v0.8 JSONL as the 'jsonl' parameter: one JSON object per line. You MUST include a surfaceUpdate (with components) and a beginRendering (with root id). See the system prompt for the full component catalog and examples.`,
    parameters: {
      type: "object",
      properties: {
        jsonl: {
          type: "string",
          description:
            "A2UI v0.8 JSONL lines. Each line is a JSON object: surfaceUpdate, dataModelUpdate, beginRendering, or deleteSurface.",
        },
      },
      required: ["jsonl"],
    },
    async execute(_id: string, params: { jsonl: string }) {
      latestSurface = params.jsonl;
      return {
        content: [
          {
            type: "text",
            text: `${A2UI_MARKER}\n${params.jsonl}`,
          },
        ],
      };
    },
  });

}
