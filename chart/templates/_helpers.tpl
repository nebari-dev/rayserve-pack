{{/*
Expand the name of the chart.
*/}}
{{- define "nebari-rayserve.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "nebari-rayserve.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "nebari-rayserve.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "nebari-rayserve.labels" -}}
helm.sh/chart: {{ include "nebari-rayserve.chart" . }}
{{ include "nebari-rayserve.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "nebari-rayserve.selectorLabels" -}}
app.kubernetes.io/name: {{ include "nebari-rayserve.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Ray head service name - RayService creates a service named <rayservice-name>-head-svc.
*/}}
{{- define "nebari-rayserve.head-service-name" -}}
{{- printf "%s-head-svc" (include "nebari-rayserve.fullname" .) }}
{{- end }}

{{/*
Ray serve service name - RayService creates a service named <rayservice-name>-serve-svc.
*/}}
{{- define "nebari-rayserve.serve-service-name" -}}
{{- printf "%s-serve-svc" (include "nebari-rayserve.fullname" .) }}
{{- end }}

{{/*
Tolerations for a Ray group (head or worker). Pass the group config
(.Values.head or .Values.worker).

When the group's resources request an NVIDIA GPU, the nvidia.com/gpu
toleration is injected automatically so GPU pods can schedule onto nodes
tainted nvidia.com/gpu=...:NoSchedule (e.g. nebari-infrastructure-core's
auto-tainted AWS GPU node groups). operator: Exists matches any taint
value. Any explicit tolerations from the group config are appended.

Renders nothing when no GPU is requested and no explicit tolerations are
set, so non-GPU pods are unchanged.
*/}}
{{- define "nebari-rayserve.tolerations" -}}
{{- $config := . -}}
{{- $tolerations := $config.tolerations | default list -}}
{{- $resources := $config.resources | default dict -}}
{{- $limits := $resources.limits | default dict -}}
{{- $requests := $resources.requests | default dict -}}
{{- if or (hasKey $limits "nvidia.com/gpu") (hasKey $requests "nvidia.com/gpu") -}}
{{- $tolerations = append $tolerations (dict "key" "nvidia.com/gpu" "operator" "Exists" "effect" "NoSchedule") -}}
{{- end -}}
{{- if $tolerations -}}
{{- toYaml $tolerations -}}
{{- end -}}
{{- end }}
