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
Whether organization CA bundle injection is enabled.
*/}}
{{- define "nebari-rayserve.orgCABundle.enabled" -}}
{{- if and .Values.orgCABundle .Values.orgCABundle.configMapName -}}
true
{{- end }}
{{- end }}

{{/*
initContainers block for the combined-CA bundle build step. Renders empty
when orgCABundle injection is disabled. Used by both head and worker pod
specs so the SSL_CERT_FILE bundle exists before the main container starts.
*/}}
{{- define "nebari-rayserve.orgCABundle.initContainers" -}}
{{- if include "nebari-rayserve.orgCABundle.enabled" . -}}
- name: build-ca-bundle
  image: {{ .Values.orgCABundle.initImage | quote }}
  command:
    - sh
    - -c
    - |
      cat /etc/ssl/certs/ca-certificates.crt \
          /var/local/org-ca/ca.crt > /shared/combined-ca.crt
  volumeMounts:
    - name: org-ca
      mountPath: /var/local/org-ca
      readOnly: true
    - name: combined-ca
      mountPath: /shared
{{- end }}
{{- end }}

{{/*
Volumes block for the org-ca ConfigMap (deployer-supplied) + the shared
emptyDir that the initContainer writes the combined bundle into. Renders
empty when orgCABundle injection is disabled.
*/}}
{{- define "nebari-rayserve.orgCABundle.volumes" -}}
{{- if include "nebari-rayserve.orgCABundle.enabled" . -}}
- name: org-ca
  configMap:
    name: {{ .Values.orgCABundle.configMapName | quote }}
- name: combined-ca
  emptyDir: {}
{{- end }}
{{- end }}

{{/*
Container volumeMounts for the combined-CA bundle (read-only). The main
Ray container mounts only the combined-ca volume — it never sees the raw
org-ca ConfigMap. Renders empty when orgCABundle injection is disabled.
*/}}
{{- define "nebari-rayserve.orgCABundle.volumeMounts" -}}
{{- if include "nebari-rayserve.orgCABundle.enabled" . -}}
- name: combined-ca
  mountPath: /shared
  readOnly: true
{{- end }}
{{- end }}

{{/*
Container env entries pointing the standard OpenSSL trust-store env vars
at the combined-CA bundle. Anything that honors SSL_CERT_FILE /
REQUESTS_CA_BUNDLE / CURL_CA_BUNDLE picks it up automatically.
Renders empty when orgCABundle injection is disabled.
*/}}
{{- define "nebari-rayserve.orgCABundle.env" -}}
{{- if include "nebari-rayserve.orgCABundle.enabled" . -}}
- name: SSL_CERT_FILE
  value: /shared/combined-ca.crt
- name: REQUESTS_CA_BUNDLE
  value: /shared/combined-ca.crt
- name: CURL_CA_BUNDLE
  value: /shared/combined-ca.crt
{{- end }}
{{- end }}
