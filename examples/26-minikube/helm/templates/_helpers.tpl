{{/*
Labels shared by every object. app.kubernetes.io/name is the workload name
(quarkus, python, edge, lgtm) and, with instance, the only pair a selector uses:
labels may change on an upgrade, selectors may not.
*/}}
{{- define "gql.labels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
app.kubernetes.io/part-of: gql-tracking
app.kubernetes.io/version: {{ .root.Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .root.Chart.Name .root.Chart.Version | replace "+" "_" }}
{{- end }}

{{- define "gql.selector" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
{{- end }}

{{/* The edge certificate Secret. */}}
{{- define "gql.tlsSecretName" -}}
{{ .Release.Name }}-edge-tls
{{- end }}

{{/* Ports the edge listens on: TLS 1.3 listeners, or plain ones behind a router. */}}
{{- define "gql.edgePort" -}}
{{- if .root.Values.edge.tls.enabled -}}
{{ ternary 8443 8444 (eq .stack "quarkus") }}
{{- else -}}
{{ ternary 8080 8081 (eq .stack "quarkus") }}
{{- end -}}
{{- end }}

{{/* The ConfigMap of one stack. Its rendering also feeds the checksum annotation. */}}
{{- define "gql.stackConfigMap" -}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .name }}-config
  namespace: {{ .root.Release.Namespace }}
  labels:
    {{- include "gql.labels" (dict "root" .root "name" .name "component" "backend") | nindent 4 }}
data:
  {{- range $key, $value := .stack.env }}
  {{ $key }}: {{ $value | toString | quote }}
  {{- end }}
{{- end }}

{{/* The restricted-profile container context, one place for every workload. */}}
{{- define "gql.containerSecurityContext" -}}
{{- toYaml .Values.containerSecurityContext }}
{{- end }}
