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

{{- define "algocrack.validate" -}}
{{- if .Values.secrets.useExisting }}
  {{- if not .Values.secrets.appSecretName }}
    {{- fail "secrets.appSecretName is required when secrets.useExisting=true" }}
  {{- end }}
  {{- if not .Values.secrets.jwtSecretName }}
    {{- fail "secrets.jwtSecretName is required when secrets.useExisting=true" }}
  {{- end }}
{{- else }}
  {{- if or (not .Values.auth.google.clientId) (eq .Values.auth.google.clientId "replace-me") }}
    {{- fail "auth.google.clientId must be set to a real value when secrets.useExisting=false" }}
  {{- end }}
  {{- if or (not .Values.auth.google.clientSecret) (eq .Values.auth.google.clientSecret "replace-me") }}
    {{- fail "auth.google.clientSecret must be set to a real value when secrets.useExisting=false" }}
  {{- end }}
  {{- if or (not .Values.mysql.auth.rootPassword) (eq .Values.mysql.auth.rootPassword "change-me") }}
    {{- fail "mysql.auth.rootPassword must be set to a real value when secrets.useExisting=false" }}
  {{- end }}
  {{- if or (not .Values.mysql.auth.password) (eq .Values.mysql.auth.password "change-me") }}
    {{- fail "mysql.auth.password must be set to a real value when secrets.useExisting=false" }}
  {{- end }}
  {{- if or (not .Values.auth.jwt.privateKeyPem) (contains "REPLACE_ME" .Values.auth.jwt.privateKeyPem) (contains "REPLACE_WITH_RSA_PRIVATE_KEY_PEM" .Values.auth.jwt.privateKeyPem) }}
    {{- fail "auth.jwt.privateKeyPem must be set to a real PEM value when secrets.useExisting=false" }}
  {{- end }}
  {{- if or (not .Values.auth.jwt.publicKeyPem) (contains "REPLACE_ME" .Values.auth.jwt.publicKeyPem) (contains "REPLACE_WITH_RSA_PUBLIC_KEY_PEM" .Values.auth.jwt.publicKeyPem) }}
    {{- fail "auth.jwt.publicKeyPem must be set to a real PEM value when secrets.useExisting=false" }}
  {{- end }}
{{- end }}

{{- if and (not .Values.mysql.enabled) (not .Values.externalServices.mysql.host) }}
  {{- fail "externalServices.mysql.host is required when mysql.enabled=false" }}
{{- end }}

{{- if and (not .Values.redis.enabled) (not .Values.externalServices.redis.host) }}
  {{- fail "externalServices.redis.host is required when redis.enabled=false" }}
{{- end }}

{{- if and .Values.ingress.enabled .Values.ingress.tls.enabled (not .Values.ingress.tls.secretName) }}
  {{- fail "ingress.tls.secretName is required when ingress.tls.enabled=true" }}
{{- end }}
{{- end -}}
