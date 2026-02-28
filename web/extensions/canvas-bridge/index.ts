const A2UI_MARKER = "__A2UI__";

export default function register(api: any) {
  let latestSurface: string | null = null;

  api.registerTool({
    name: "canvas_ui",
    description: `MANDATORY: Call this tool to render any visual content in the Canvas panel. Do NOT describe UI in chat text — the user cannot see it unless you call this tool. Any time you would show a dashboard, status, greeting, list, or interface, you MUST use this tool instead of writing markdown/text.

Input: A2UI v0.8 JSONL — each line is a JSON object. You MUST include at minimum a surfaceUpdate (with components) and a beginRendering (with root id). You MAY also include dataModelUpdate lines.

Available components (standard catalog):
- Text: {"Text":{"text":{"literalString":"..."},"usageHint":"h1"}} (usageHint: h1, h2, h3, h4, h5, body, caption, label)
- Column: {"Column":{"children":{"explicitList":["id1","id2"]},"distribution":"start","alignment":"start"}} (distribution: start|center|end|spaceBetween|spaceAround|spaceEvenly; alignment: start|center|end|stretch)
- Row: {"Row":{"children":{"explicitList":["id1","id2"]},"distribution":"start","alignment":"center"}}
- Button: {"Button":{"child":"text-comp-id","primary":true,"action":{"name":"submit","context":{"key":{"path":"/form/field"}}}}} (also accepts legacy: {"label":{"literalString":"..."},"action":"action-id"})
- Card: {"Card":{"child":"content-id"}} (also accepts legacy: {"children":{"explicitList":["id1"]}})
- Image: {"Image":{"url":{"literalString":"https://..."}}}
- Icon: {"Icon":{"name":{"literalString":"check"}}} (Material Icons: check, close, add, edit, delete, search, settings, star, info, warning, error, dashboard, analytics, code, terminal, etc.)
- TextField: {"TextField":{"label":{"literalString":"Email"},"text":{"path":"/form/email"},"placeholder":"Enter email","textFieldType":"shortText"}} (textFieldType: shortText|longText|number|date|obscured. Writes to data model on change.)
- CheckBox: {"CheckBox":{"label":{"literalString":"I agree"},"value":{"path":"/form/agreed"}}} (Writes to data model on toggle.)
- Slider: {"Slider":{"min":0,"max":100,"value":{"path":"/settings/volume"}}} (Writes to data model on change.)
- Toggle: {"Toggle":{"label":{"literalString":"Dark mode"},"value":{"path":"/settings/dark"}}} (Writes to data model on change.)
- Modal: {"Modal":{"entryPointChild":"open-btn-id","contentChild":"modal-content-id"}}
- Tabs: {"Tabs":{"tabItems":[{"title":{"literalString":"Tab 1"},"child":"tab1-content"},{"title":{"literalString":"Tab 2"},"child":"tab2-content"}]}}
- List: {"List":{"children":{"template":{"dataBinding":"/items","componentId":"item-template"}}}} (or explicitList)
- Progress: {"Progress":{"value":0.7}} (0.0-1.0 for determinate, omit value for indeterminate)
- Divider: {"Divider":{"axis":"horizontal"}} (axis: horizontal|vertical)
- Spacer: {"Spacer":{"height":16}}

Data binding — components can bind to a per-surface data model:
- Use {"literalString":"static value"} for static text
- Use {"path":"/data/field"} to bind to the data model
- Send dataModelUpdate to set/update data: {"dataModelUpdate":{"surfaceId":"main","path":"user","contents":[{"key":"name","valueString":"Alice"}]}}
- Input components (TextField, CheckBox, Slider, Toggle) automatically write back to the data model at their bound path

Button actions — structured userAction events:
- Use {"action":{"name":"action-name","context":{"fieldKey":{"path":"/form/field"}}}} for structured actions
- When clicked, context paths are resolved against the data model and sent as a userAction event
- Legacy {"action":"action-id"} string format is still supported

Component weight — use "weight" on any component for flex in Row/Column:
- {"id":"wide","weight":3,"component":{"Text":{"text":{"literalString":"Takes 3x space"}}}}

Incremental updates — surfaceUpdate is additive (upsert by component id). You can send multiple surfaceUpdate messages to build up a surface progressively.

Example JSONL:
{"surfaceUpdate":{"surfaceId":"main","components":[{"id":"root","component":{"Column":{"children":{"explicitList":["title","input","btn"]}}}},{"id":"title","component":{"Text":{"text":{"literalString":"Hello"},"usageHint":"h1"}}},{"id":"input","component":{"TextField":{"label":{"literalString":"Name"},"text":{"path":"/form/name"},"placeholder":"Enter name"}}},{"id":"btn","component":{"Button":{"child":"btn-text","primary":true,"action":{"name":"submit","context":{"name":{"path":"/form/name"}}}}}},{"id":"btn-text","component":{"Text":{"text":{"literalString":"Submit"}}}}]}}
{"dataModelUpdate":{"surfaceId":"main","contents":[{"key":"form","valueMap":[{"key":"name","valueString":""}]}]}}
{"beginRendering":{"surfaceId":"main","root":"root"}}`,
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
