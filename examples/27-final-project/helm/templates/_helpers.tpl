{{/*
Labels shared by every object. app.kubernetes.io/name is the workload name
(quarkus, quarkus-internal, python, python-internal, edge, keycloak, lgtm) and,
with instance, the only pair a selector uses: labels may change on an upgrade,
selectors may not.
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

{{/* The workload name of an instance: the public one keeps the stack's name, the edge's upstream. */}}
{{- define "gql.instanceName" -}}
{{- if eq .kind "public" }}{{ .stack }}{{ else }}{{ .stack }}-{{ .kind }}{{ end }}
{{- end }}

{{/* The component label of an instance; a network policy selects on it. */}}
{{- define "gql.instanceComponent" -}}
{{ ternary "backend" "internal" (eq .kind "public") }}
{{- end }}

{{/*
The environment of one instance, as a YAML map: the stack's contract, what an
instance with introspection off adds, the identity values under the names the
stack reads them as, then the instance's own overrides.
*/}}
{{- define "gql.instanceEnv" -}}
{{- $env := deepCopy .stack.env -}}
{{- if not .inst.introspection -}}
{{- $env = mergeOverwrite $env (deepCopy .stack.introspectionOff) -}}
{{- end -}}
{{- $identity := .root.Values.identity -}}
{{- range $role, $key := .stack.identityEnv -}}
{{- if eq $role "issuer" -}}
{{- $_ := set $env $key $identity.issuer -}}
{{- else if eq $role "authServer" -}}
{{- $_ := set $env $key $identity.authServerUrl -}}
{{- else if eq $role "jwks" -}}
{{- $_ := set $env $key (printf "%s/protocol/openid-connect/certs" $identity.authServerUrl) -}}
{{- end -}}
{{- end -}}
{{- $env = mergeOverwrite $env (deepCopy (default (dict) .inst.env)) -}}
{{- toYaml $env -}}
{{- end }}

{{/* The ConfigMap of one instance. Its rendering also feeds the checksum annotation. */}}
{{- define "gql.instanceConfigMap" -}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .name }}-config
  namespace: {{ .root.Release.Namespace }}
  labels:
    {{- include "gql.labels" (dict "root" .root "name" .name "component" .component) | nindent 4 }}
data:
  {{- range $key, $value := (include "gql.instanceEnv" (dict "root" .root "stack" .stack "inst" .inst) | fromYaml) }}
  {{ $key }}: {{ $value | toString | quote }}
  {{- end }}
{{- end }}

{{/* The restricted-profile container context, one place for every workload. */}}
{{- define "gql.containerSecurityContext" -}}
{{- toYaml .Values.containerSecurityContext }}
{{- end }}
