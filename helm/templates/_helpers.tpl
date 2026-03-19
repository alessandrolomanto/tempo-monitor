{{/*
Expand the name of the chart.
*/}}
{{- define "tempo-monitor.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "tempo-monitor.fullname" -}}
{{- if .Values.fullnameOverride }}
{{-   .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{-   .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Create a combined name for validator / RPC resources.
*/}}
{{- define "tempo-monitor.nodeName" -}}
{{- $name := include "tempo-monitor.fullname" . -}}
{{- printf "%s-%s" $name .name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Tempo image.
*/}}
{{- define "tempo-monitor.image" -}}
{{- printf "%s:%s" .Values.tempo.image.repository .Values.tempo.image.tag | default .Values.tempo.image }}
{{- end }}

{{/*
Tempo consensus network seed — first validator address.
*/}}
{{- define "tempo-monitor.leaderAddress" -}}
{{- index .Values.validators.hosts 0 | printf "http://%s:8545" }}
{{- end }}

{{/*
Template label (stable identity across upgrades).
*/}}
{{- define "tempo-monitor.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "." "-" }}
app.kubernetes.io/name: {{ include "tempo-monitor.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "tempo-monitor.selectorLabels" -}}
app.kubernetes.io/name: {{ include "tempo-monitor.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Service port for RPC HTTP.
*/}}
{{- define "tempo-monitor.rpcPort" -}}
{{- .Values.tempo.rpc.port | default 8545 }}
{{- end }}

{{/*
Consensus metrics port.
*/}}
{{- define "tempo-monitor.consensusMetricsPort" -}}
{{- .Values.tempo.consensus.metricsPort | default 8001 }}
{{- end }}

{{/*
Execution metrics port.
*/}}
{{- define "tempo-monitor.executionMetricsPort" -}}
{{- .Values.tempo.execution.metricsPort | default 9001 }}
{{- end }}

{{/*
WS RPC port.
*/}}
{{- define "tempo-monitor.wsPort" -}}
{{- .Values.tempo.rpc.wsPort | default 8546 }}
{{- end }}

{{/*
Build a PersistentVolumeClaim manifest.

Call with:
  include "tempo-monitor.pvc" (dict
    "root"         $root
    "enabled"      true
    "name"         "<pvc-name>"
    "component"    "<component-label>"
    "storageClass" "<storageClass or \"\">"
    "size"         "<size>"
  )

Produces a PVC manifest if .enabled is true, empty string otherwise.
*/}}
{{- define "tempo-monitor.pvc" -}}
{{- $root := .root -}}
{{- if .enabled }}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{ .name }}
  namespace: {{ $root.Release.Namespace }}
  labels:
    app.kubernetes.io/component: {{ .component }}
    {{- include "tempo-monitor.labels" $root | nindent 4 }}
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: {{ .storageClass | default "" | quote }}
  resources:
    requests:
      storage: {{ .size }}
{{- end }}
{{- end }}
