{{/*
Resolve control plane count from sizing preset.
*/}}
{{- define "cluster.controlPlaneCount" -}}
{{- if eq .Values.sizing.preset "small" -}}
1
{{- else if eq .Values.sizing.preset "medium" -}}
3
{{- else if eq .Values.sizing.preset "large" -}}
3
{{- else -}}
{{ .Values.sizing.custom.controlPlaneCount }}
{{- end -}}
{{- end -}}

{{/*
Resolve worker count from sizing preset.
*/}}
{{- define "cluster.workerCount" -}}
{{- if eq .Values.sizing.preset "small" -}}
2
{{- else if eq .Values.sizing.preset "medium" -}}
3
{{- else if eq .Values.sizing.preset "large" -}}
5
{{- else -}}
{{ .Values.sizing.custom.workerCount }}
{{- end -}}
{{- end -}}

{{/*
Generate safe cluster name.
*/}}
{{- define "cluster.fullname" -}}
{{ .Values.cluster.name | default "rke2-kubeovn" | trunc 63 | trimSuffix "-" }}
{{- end -}}
