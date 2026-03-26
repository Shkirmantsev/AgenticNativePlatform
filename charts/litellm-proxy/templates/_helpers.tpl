{{- define "litellm-proxy.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "litellm-proxy.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- include "litellm-proxy.name" . -}}
{{- end -}}
{{- end -}}

{{- define "litellm-proxy.namespace" -}}
{{- .Release.Namespace -}}
{{- end -}}

{{- define "litellm-proxy.labels" -}}
app: {{ include "litellm-proxy.fullname" . }}
app.kubernetes.io/name: {{ include "litellm-proxy.name" . }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{- define "litellm-proxy.selectorLabels" -}}
app: {{ include "litellm-proxy.fullname" . }}
app.kubernetes.io/name: {{ include "litellm-proxy.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "litellm-proxy.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "litellm-proxy.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- required "serviceAccount.name must be set when serviceAccount.create=false" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}
