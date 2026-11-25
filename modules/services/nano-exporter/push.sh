: "${NANO_EXPORTER_URL:?}"

NANO_EXPORTER_DEFAULT_FLAGS=(
  --cpu-on --filefd-on --filesystem-on --loadavg-on --meminfo-on
  --netdev-on --netif-on --pressure-on --stat-on --uname-on --vmstat-on
  --filesystem-include-device='/*,overlay'
)

emit_cgroup_oom() {
  local f v
  for f in /sys/fs/cgroup/memory.events /sys/fs/cgroup/memory/memory.oom_control; do
    if [ -r "$f" ] && v=$(awk '$1 == "oom_kill" { print $2; exit }' "$f") && [ -n "$v" ]; then
      printf 'node_vmstat_oom_kill %s\n' "$v"
      return 0
    fi
  done
  return 1
}

emit_services() {
  if [ -d /run/finit/cond/service ]; then
    local svc name st
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
  elif [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
    systemctl list-units --no-legend --plain \
      | awk 'NF >= 3 { printf "node_systemd_unit_state{name=\"%s\",state=\"failed\"} %d\n", $1, ($3 == "failed") }'
  fi
}

emit_extra_collectors() {
  local c
  for c in "${NANO_EXPORTER_COLLECTORS[@]}"; do
    [ -x "$c" ] || continue
    "$c" || printf 'nano_exporter: collector %s failed\n' "${c##*/}" >&2
  done
}

push_once() {
  local cgroup_oom
  cgroup_oom=$(emit_cgroup_oom || true)

  local sed_args=()
  if [ -n "${NANO_EXPORTER_NODENAME:-}" ]; then
    sed_args+=(-e "s/^\\(node_uname_info{.*nodename=\"\\)[^\"]*\"/\\1${NANO_EXPORTER_NODENAME}\"/")
  fi
  if [ -n "$cgroup_oom" ]; then
    sed_args+=(-e '/^node_vmstat_oom_kill /d')
  fi

  local nano_flags=(
    "${NANO_EXPORTER_DEFAULT_FLAGS[@]}"
    "${NANO_EXPORTER_EXTRA_FLAGS[@]}"
  )

  (
    if [ "${#sed_args[@]}" -gt 0 ]; then
      nano-exporter --stdout "${nano_flags[@]}" | sed "${sed_args[@]}"
    else
      nano-exporter --stdout "${nano_flags[@]}"
    fi
    if [ -n "$cgroup_oom" ]; then
      printf '%s\n' "$cgroup_oom"
    fi
    emit_services
    emit_extra_collectors
  ) | gzip -c | {
    if [ -n "${NANO_EXPORTER_PASSWORD_FILE:-}" ]; then
      local password
      password=$(cat "$NANO_EXPORTER_PASSWORD_FILE")
      exec 3<<EOF
user = "${NANO_EXPORTER_USER:-}:${password}"
EOF
      curl -fsS --max-time 30 \
        -K /proc/self/fd/3 \
        -H 'Content-Encoding: gzip' \
        --data-binary @- \
        "$NANO_EXPORTER_URL"
    else
      curl -fsS --max-time 30 \
        -H 'Content-Encoding: gzip' \
        --data-binary @- \
        "$NANO_EXPORTER_URL"
    fi
  }
}

push_once
