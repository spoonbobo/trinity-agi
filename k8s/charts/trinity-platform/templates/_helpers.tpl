{{/*
Common labels applied to all resources.
*/}}
{{- define "trinity.labels" -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: trinity-platform
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
{{- end }}

{{/*
Selector labels for a specific component.
Usage: {{ include "trinity.selectorLabels" (dict "component" "auth-service") }}
*/}}
{{- define "trinity.selectorLabels" -}}
app.kubernetes.io/name: {{ .component }}
app.kubernetes.io/instance: {{ .component }}
{{- end }}

{{/*
Full labels for a specific component (common + selector).
Usage: {{ include "trinity.componentLabels" (dict "component" "auth-service" "Release" $.Release "Chart" $.Chart) }}
*/}}
{{- define "trinity.componentLabels" -}}
app.kubernetes.io/name: {{ .component }}
app.kubernetes.io/instance: {{ .component }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: trinity-platform
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
{{- end }}

{{/*
Namespace helper.
*/}}
{{- define "trinity.namespace" -}}
{{ .Values.global.namespace | default "trinity" }}
{{- end }}

{{/*
Image with optional registry prefix.
Usage: {{ include "trinity.image" (dict "image" .Values.supabaseDb.image "global" .Values.global) }}
*/}}
{{- define "trinity.image" -}}
{{- if .global.imageRegistry -}}
{{ .global.imageRegistry }}{{ .image }}
{{- else -}}
{{ .image }}
{{- end -}}
{{- end }}

{{/*
Storage class helper. Returns the configured storageClass or omits it for cluster default.
*/}}
{{- define "trinity.storageClass" -}}
{{- if .Values.global.storageClass -}}
storageClassName: {{ .Values.global.storageClass }}
{{- end -}}
{{- end }}
