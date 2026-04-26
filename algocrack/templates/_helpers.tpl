{{- define "algocrack.namespace" -}}
{{- .Values.namespace.name -}}
{{- end -}}

{{- define "algocrack.labels" -}}
app.kubernetes.io/name: algocrack
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "algocrack.selectorLabels" -}}
app.kubernetes.io/name: algocrack
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "algocrack.componentLabel" -}}
app.kubernetes.io/component: {{ . }}
{{- end -}}

{{- define "algocrack.componentSelectorLabels" -}}
{{- $ctx := .context -}}
{{- include "algocrack.selectorLabels" $ctx }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{- define "algocrack.appSecretName" -}}
{{- if .Values.secrets.useExisting -}}
{{- .Values.secrets.appSecretName -}}
{{- else -}}
algocrack-app-secrets
{{- end -}}
{{- end -}}

{{- define "algocrack.jwtSecretName" -}}
{{- if .Values.secrets.useExisting -}}
{{- .Values.secrets.jwtSecretName -}}
{{- else -}}
jwt-signing-keys
{{- end -}}
{{- end -}}

{{- define "algocrack.mysqlHost" -}}
{{- if and (not .Values.mysql.enabled) .Values.externalServices.mysql.host -}}
{{- .Values.externalServices.mysql.host -}}
{{- else -}}
mysql
{{- end -}}
{{- end -}}

{{- define "algocrack.mysqlPort" -}}
{{- if and (not .Values.mysql.enabled) .Values.externalServices.mysql.port -}}
{{- .Values.externalServices.mysql.port | toString -}}
{{- else -}}
3306
{{- end -}}
{{- end -}}

{{- define "algocrack.redisHost" -}}
{{- if and (not .Values.redis.enabled) .Values.externalServices.redis.host -}}
{{- .Values.externalServices.redis.host -}}
{{- else -}}
redis
{{- end -}}
{{- end -}}

{{- define "algocrack.redisPort" -}}
{{- if and (not .Values.redis.enabled) .Values.externalServices.redis.port -}}
{{- .Values.externalServices.redis.port | toString -}}
{{- else -}}
6379
{{- end -}}
{{- end -}}

{{- define "algocrack.storageClassName" -}}
{{- $local := .local -}}
{{- $global := .global -}}
{{- if $local -}}
storageClassName: {{ $local | quote }}
{{- else if $global -}}
storageClassName: {{ $global | quote }}
{{- end -}}
{{- end -}}

{{- define "algocrack.imagePullSecrets" -}}
{{- if .Values.global.imagePullSecrets }}
imagePullSecrets:
  {{- range .Values.global.imagePullSecrets }}
  - name: {{ . | quote }}
  {{- end }}
{{- end -}}
{{- end -}}
