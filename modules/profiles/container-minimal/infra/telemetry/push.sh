: "${TELEMETRY_HOST:?}"
: "${TELEMETRY_USER:?}"
: "${TELEMETRY_TOKEN_FILE:?}"
: "${TELEMETRY_URL:?}"

emit_runit() {
  for svc in /etc/service/*; do
    [ -d "$svc/supervise" ] || continue
    name=${svc##*/}
    st=0
    if [ -r "$svc/supervise/stat" ] && read -r s < "$svc/supervise/stat" && [ "$s" = "run" ]; then
      st=1
    fi
    des=1
    if [ -e "$svc/down" ]; then
      des=0
    fi
    printf 'node_service_state{service="%s",supervisor="runit"} %d\n' "$name" "$st"
    printf 'node_service_desired_state{service="%s",supervisor="runit"} %d\n' "$name" "$des"
  done
}

push_once() {
  local token
  token=$(cat "$TELEMETRY_TOKEN_FILE")
  (
    nano-exporter --stdout \
      --cpu-on --filefd-on --filesystem-on --loadavg-on --meminfo-on \
      --netdev-on --netif-on --pressure-on --stat-on --uname-on --vmstat-on \
      --filesystem-include-device='/*,overlay' \
      | sed "s/^\\(node_uname_info{.*nodename=\"\\)[^\"]*\"/\\1${TELEMETRY_HOST}\"/"
    emit_runit
  ) | gzip -c | {
    exec 3<<EOF
user = "${TELEMETRY_USER}:${token}"
EOF
    curl -fsS --max-time 30 \
      -K /proc/self/fd/3 \
      -H 'Content-Encoding: gzip' \
      --data-binary @- \
      "$TELEMETRY_URL"
  }
}

push_once
