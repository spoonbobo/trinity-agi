{{/*
Generate a consistent resource name for this user's OpenClaw instance.
Uses a truncated userId to keep names within K8s length limits.
*/}}
{{- define "openclaw.name" -}}
openclaw-{{ .Values.userId | trunc 12 }}
{{- end }}

{{/*
Common labels for per-user instance resources.
*/}}
{{- define "openclaw.labels" -}}
app.kubernetes.io/name: openclaw-instance
app.kubernetes.io/instance: {{ include "openclaw.name" . }}
app.kubernetes.io/managed-by: gateway-orchestrator
app.kubernetes.io/part-of: trinity-platform
trinity.ai/user-id: {{ .Values.userId | quote }}
{{- range $key, $val := .Values.extraLabels }}
{{ $key }}: {{ $val | quote }}
{{- end }}
{{- end }}

{{/*
Selector labels for this user's instance.
*/}}
{{- define "openclaw.selectorLabels" -}}
app.kubernetes.io/name: openclaw-instance
app.kubernetes.io/instance: {{ include "openclaw.name" . }}
{{- end }}

{{/*
Image with optional registry prefix.
*/}}
{{- define "openclaw.image" -}}
{{- if .Values.imageRegistry -}}
{{ .Values.imageRegistry }}{{ .Values.image }}
{{- else -}}
{{ .Values.image }}
{{- end -}}
{{- end }}
