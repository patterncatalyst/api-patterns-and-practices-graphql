{{/*
Labels on every object this chart adds. The dependency labels its own objects.
*/}}
{{- define "appa.labels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
app.kubernetes.io/part-of: gql-tracking
app.kubernetes.io/version: {{ .root.Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .root.Chart.Name .root.Chart.Version | replace "+" "_" }}
{{- end }}

{{/*
The host of a Route: <route>-<project>.<ingress domain>, the name the router
would generate. The identity issuer in values.yaml is the keycloak host.
*/}}
{{- define "appa.host" -}}
{{ printf "%s-%s.%s" .name .root.Release.Namespace .root.Values.openshift.domain }}
{{- end }}

{{/* The image stream a stack's image lives in: the last segment of its repository. */}}
{{- define "appa.imageName" -}}
{{ last (splitList "/" .) }}
{{- end }}
