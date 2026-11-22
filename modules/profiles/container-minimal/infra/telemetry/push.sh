: "${TELEMETRY_HOST:?}"
: "${TELEMETRY_USER:?}"
: "${TELEMETRY_TOKEN_FILE:?}"
: "${TELEMETRY_URL:?}"

emit_services() {
  for svc in /run/finit/cond/service/*; do
    [ -d "$svc" ] || continue
    name=${svc##*/}
    st=0
    if [ -e "$svc/running" ]; then
      st=1
    fi
    printf 'node_service_state{service="%s",supervisor="finit"} %d\n' "$name" "$st"
    printf 'node_service_desired_state{service="%s",supervisor="finit"} 1\n' "$name"
  done
}

emit_cgroup_oom() {
  local f v
  for f in /sys/fs/cgroup/memory.events /sys/fs/cgroup/memory/memory.oom_control; do
    if [ -r "$f" ] && v=$(awk '$1 == "oom_kill" { print $2; exit }' "$f") && [ -n "$v" ]; then
      printf 'node_vmstat_oom_kill %s\n' "$v"
      return 0
    fi
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
      | sed \
        -e "s/^\\(node_uname_info{.*nodename=\"\\)[^\"]*\"/\\1${TELEMETRY_HOST}\"/" \
        -e '/^node_vmstat_oom_kill /d'
    emit_cgroup_oom
    emit_services
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
