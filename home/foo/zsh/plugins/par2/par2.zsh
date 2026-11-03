REDUNDENCY_PERCENTAGE="10"
PRINT_ON_SUCCESS=1

create_par2() {

  local current_file="${1}"
  if [ ! -e "${current_file}-5p.par2" ] && [ -s "${current_file}" ]; then
    if par2create -n1 -q -q -r"${REDUNDENCY_PERCENTAGE}" "${current_file}"; then

      if [ "${PRINT_ON_SUCCESS}" = 1 ]; then
        printf '\033[1;37m%s \033[1;34m%s \033[1;32m%s \033[0m\n' \
                'Creating par2 on' "${current_file}" 'successful'
      fi

      rm "${current_file}.par2"
      mv "${current_file}".vol*par2 "${current_file}-${REDUNDENCY_PERCENTAGE}p.par2"
      return 0

    else
      printf '\033[1;37m%s \033[1;34m%s \033[1;31m%s \033[0m\n' \
              'Creating par2 on' "${current_file}" 'failed'
      return 1
    fi
  fi
}

verify_par2() {

  local current_file="${1}"
  if [ -f "${current_file}-${REDUNDENCY_PERCENTAGE}p.par2" ]; then
    if par2verify -q -q "${current_file}-${REDUNDENCY_PERCENTAGE}p.par2"; then
      if [ "${PRINT_ON_SUCCESS}" = 1 ]; then
        printf '\033[1;37m%s \033[1;34m%s \033[1;32m%s \033[0m\n' \
                'Verifying par2 on' "${current_file}" 'successful'
      fi
      return 0
    else
      printf '\033[1;37m%s \033[1;34m%s \033[1;31m%s \033[0m\n' \
              'Verifying par2 on' "${current_file}" 'failed'
      return 1
    fi
  fi
}

repair_par2() {

  local current_file="${1}"
  if [ -f "${current_file}-${REDUNDENCY_PERCENTAGE}p.par2" ]; then
    if par2repair -p -q -q "${current_file}-${REDUNDENCY_PERCENTAGE}p.par2"; then
      if [ "${PRINT_ON_SUCCESS}" = 1 ]; then
        printf '\033[1;37m%s \033[1;34m%s \033[1;32m%s \033[0m\n' \
                'Repairing' "${current_file}" 'successful'
      fi
      return 0
    else
      printf '\033[1;37m%s \033[1;34m%s \033[1;31m%s \033[0m\n' \
              'Repairing' "${current_file}" 'failed'
      return 1
    fi
  fi
}

par2dir() {

  while read -r current_file; do
    # Create or verify
    if [ ! -e "${current_file}-${REDUNDENCY_PERCENTAGE}p.par2" ]; then
      create_par2 "$current_file"
    else
      if ! verify_par2 "$current_file"; then
        repair_par2 "$current_file"
      fi
    fi
  # We ignore the file itself, any par2/sig extension and any .git directory and print without the leading ./
  done < <(find . -type f ! -name '*par2loop.sh' ! -name '*par2' ! -name '*.sig' ! -path '*.git*' -prune -a -printf '%P\n' | shuf)
}