#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="4.0.0"

DEFAULT_INTERVAL=60
DEFAULT_DISTANCE=1
DEFAULT_HOLD=0.15
DEFAULT_PIDFILE="${XDG_RUNTIME_DIR:-/tmp}/mouse-jiggler.pid"

INTERVAL="$DEFAULT_INTERVAL"
DISTANCE="$DEFAULT_DISTANCE"
HOLD="$DEFAULT_HOLD"
DEVICE=""
PIDFILE="$DEFAULT_PIDFILE"
VERBOSE=0

LAST_ACTIVITY=0
MONITOR_PID=""

log() {
  printf '[mouse-jiggler] %s\n' "$*"
}

err() {
  printf '[mouse-jiggler] ERRO: %s\n' "$*" >&2
}

usage() {
  cat <<EOF
Uso:
  $(basename "$0") <comando> [opções]

Comandos:
  run                     Executa em foreground
  start                   Executa em background
  stop                    Para a instância em execução
  status                  Mostra o status
  restart                 Reinicia em background
  toggle                  Alterna: se estiver rodando, para; se não, inicia
  list-devices            Lista os devices de mouse encontrados
  help                    Mostra esta ajuda
  version                 Mostra a versão

Opções:
  -i, --interval SEGS       Tempo sem uso antes do jiggle (padrão: ${DEFAULT_INTERVAL})
  -d, --distance PIXELS     Distância do jiggle em pixels (padrão: ${DEFAULT_DISTANCE})
  -H, --hold SEGS           Tempo entre ida e volta (padrão: ${DEFAULT_HOLD})
  -D, --device CAMINHO      Device específico em /dev/input/by-id/
  -p, --pidfile CAMINHO     Caminho do arquivo PID
  -v, --verbose             Logs mais detalhados

Exemplos:
  $(basename "$0") run -i 5 -d 100 -v
  $(basename "$0") start -i 60 -d 1
  $(basename "$0") toggle -i 60
  $(basename "$0") list-devices
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    err "Comando obrigatório não encontrado: $1"
    exit 1
  }
}

is_positive_number() {
  [[ "${1:-}" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

is_positive_int() {
  [[ "${1:-}" =~ ^[0-9]+$ ]]
}

now_epoch() {
  date +%s
}

cleanup() {
  local ec=$?

  if [[ -n "${MONITOR_PID:-}" ]] && kill -0 "$MONITOR_PID" 2>/dev/null; then
    kill "$MONITOR_PID" 2>/dev/null || true
  fi

  if [[ -f "$PIDFILE" ]] && [[ "$(cat "$PIDFILE" 2>/dev/null || true)" == "$$" ]]; then
    rm -f "$PIDFILE"
  fi

  (( VERBOSE )) && log "Encerrando."
  exit "$ec"
}

trap cleanup INT TERM EXIT

find_mouse_devices() {
  if compgen -G "/dev/input/by-id/*event-mouse" >/dev/null; then
    ls -1 /dev/input/by-id/*event-mouse 2>/dev/null | sort
  fi
}

find_best_mouse_device() {
  mapfile -t devices < <(find_mouse_devices)

  if [[ ${#devices[@]} -eq 0 ]]; then
    return 1
  fi

  if [[ ${#devices[@]} -eq 1 ]]; then
    printf '%s\n' "${devices[0]}"
    return 0
  fi

  local preferred=""
  for dev in "${devices[@]}"; do
    case "$dev" in
      *usb*event-mouse*|*receiver*event-mouse*|*logitech*event-mouse*|*mouse*event-mouse*)
        preferred="$dev"
        break
        ;;
    esac
  done

  if [[ -n "$preferred" ]]; then
    printf '%s\n' "$preferred"
  else
    printf '%s\n' "${devices[0]}"
  fi
}

check_device() {
  [[ -n "$DEVICE" ]] || {
    err "Nenhum device selecionado."
    exit 1
  }

  [[ -e "$DEVICE" ]] || {
    err "Device não existe: $DEVICE"
    exit 1
  }
}

check_dependencies() {
  require_cmd evemu-event
  require_cmd libinput
  require_cmd sudo
  require_cmd grep
}

write_pid() {
  if [[ -f "$PIDFILE" ]]; then
    local oldpid
    oldpid="$(cat "$PIDFILE" 2>/dev/null || true)"
    if [[ -n "$oldpid" ]] && kill -0 "$oldpid" 2>/dev/null; then
      err "Já existe uma instância em execução (PID $oldpid)."
      exit 1
    fi
  fi

  mkdir -p "$(dirname "$PIDFILE")"
  echo "$$" > "$PIDFILE"
}

status_cmd() {
  if [[ -f "$PIDFILE" ]]; then
    local pid
    pid="$(cat "$PIDFILE" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      echo "mouse-jiggler em execução. PID: $pid"
      return 0
    fi
  fi

  echo "mouse-jiggler parado."
  return 1
}

stop_cmd() {
  if [[ -f "$PIDFILE" ]]; then
    local pid
    pid="$(cat "$PIDFILE" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid"
      rm -f "$PIDFILE"
      echo "mouse-jiggler parado."
      return 0
    fi
  fi

  echo "mouse-jiggler não estava em execução."
  return 0
}

toggle_cmd() {
  if status_cmd >/dev/null 2>&1; then
    stop_cmd
  else
    start_cmd
  fi
}

list_devices_cmd() {
  mapfile -t devices < <(find_mouse_devices)

  if [[ ${#devices[@]} -eq 0 ]]; then
    err "Nenhum device de mouse encontrado em /dev/input/by-id/*event-mouse"
    exit 1
  fi

  printf 'Devices encontrados:\n'
  printf ' - %s\n' "${devices[@]}"
}

device_to_kernel_event() {
  local resolved
  resolved="$(readlink -f "$DEVICE")"
  [[ -n "$resolved" ]] || return 1
  printf '%s\n' "$resolved"
}

jiggle_once() {
  local dist="$1"
  local hold="$2"

  sudo evemu-event "$DEVICE" --type EV_REL --code REL_X --value "$dist" --sync
  sleep "$hold"
  sudo evemu-event "$DEVICE" --type EV_REL --code REL_X --value "-$dist" --sync
}

mark_activity_now() {
  LAST_ACTIVITY="$(now_epoch)"
}

monitor_mouse_activity() {
  local kernel_device="$1"

  mark_activity_now

  # -o0 -e0 evita buffering extra; filtra apenas eventos que indicam uso real do mouse
  sudo stdbuf -o0 -e0 libinput debug-events --device "$kernel_device" 2>/dev/null | \
  while IFS= read -r line; do
    case "$line" in
      *POINTER_MOTION*|*POINTER_MOTION_ABSOLUTE*|*POINTER_BUTTON*|*POINTER_SCROLL_WHEEL*|*POINTER_SCROLL_FINGER*|*POINTER_SCROLL_CONTINUOUS*)
        printf '%s\n' "$(now_epoch)"
        ;;
      *)
        ;;
    esac
  done
}

run_loop() {
  check_dependencies

  if [[ -z "$DEVICE" ]]; then
    DEVICE="$(find_best_mouse_device || true)"
  fi

  if [[ -z "$DEVICE" ]]; then
    err "Nenhum device de mouse encontrado automaticamente."
    err "Use: $(basename "$0") list-devices"
    err "Ou informe manualmente com: --device CAMINHO"
    exit 1
  fi

  check_device
  write_pid

  local kernel_device
  kernel_device="$(device_to_kernel_event)" || {
    err "Não foi possível resolver o event node do device."
    exit 1
  }

  log "Iniciando."
  log "Device by-id: $DEVICE"
  log "Kernel event: $kernel_device"
  log "Intervalo sem uso: ${INTERVAL}s | Distância: ${DISTANCE}px | Hold: ${HOLD}s"

  local activity_fifo
  activity_fifo="$(mktemp -u "${XDG_RUNTIME_DIR:-/tmp}/mouse-jiggler-activity.XXXXXX")"
  mkfifo "$activity_fifo"

  monitor_mouse_activity "$kernel_device" > "$activity_fifo" &
  MONITOR_PID=$!

  mark_activity_now

  exec 9<>"$activity_fifo"
  rm -f "$activity_fifo"

  while true; do
    # Consome timestamps de atividade sem bloquear demais o loop
    if read -r -t 1 -u 9 activity_ts; then
      LAST_ACTIVITY="$activity_ts"
      (( VERBOSE )) && log "Atividade detectada no mouse. last_activity=$LAST_ACTIVITY"
    fi

    local now idle_for
    now="$(now_epoch)"
    idle_for=$(( now - LAST_ACTIVITY ))

    (( VERBOSE )) && log "Inatividade atual: ${idle_for}s | Limite: ${INTERVAL}s"

    if (( idle_for >= INTERVAL )); then
      (( VERBOSE )) && log "Mouse sem uso pelo intervalo configurado. Jiggle executado."
      jiggle_once "$DISTANCE" "$HOLD"
      mark_activity_now
    fi

    if [[ -n "${MONITOR_PID:-}" ]] && ! kill -0 "$MONITOR_PID" 2>/dev/null; then
      err "O monitor de atividade do libinput encerrou inesperadamente."
      exit 1
    fi
  done
}

start_cmd() {
  local self
  self="$(readlink -f "$0")"

  if [[ -f "$PIDFILE" ]]; then
    local pid
    pid="$(cat "$PIDFILE" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      err "Já existe uma instância em execução (PID $pid)."
      exit 1
    fi
  fi

  nohup "$self" run \
    --interval "$INTERVAL" \
    --distance "$DISTANCE" \
    --hold "$HOLD" \
    ${DEVICE:+--device "$DEVICE"} \
    --pidfile "$PIDFILE" \
    $([[ "$VERBOSE" -eq 1 ]] && echo "--verbose") \
    >/dev/null 2>&1 &

  local bgpid=$!
  sleep 0.3

  if kill -0 "$bgpid" 2>/dev/null; then
    echo "mouse-jiggler iniciado em background. PID: $bgpid"
    echo "Observação: execute 'sudo -v' antes, para evitar prompt de senha em background."
  else
    err "Falha ao iniciar em background."
    exit 1
  fi
}

parse_options() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -i|--interval)
        INTERVAL="${2:-}"; shift 2 ;;
      -d|--distance)
        DISTANCE="${2:-}"; shift 2 ;;
      -H|--hold)
        HOLD="${2:-}"; shift 2 ;;
      -D|--device)
        DEVICE="${2:-}"; shift 2 ;;
      -p|--pidfile)
        PIDFILE="${2:-}"; shift 2 ;;
      -v|--verbose)
        VERBOSE=1; shift ;;
      -h|--help)
        usage; exit 0 ;;
      -V|--version)
        echo "$VERSION"; exit 0 ;;
      *)
        err "Opção inválida: $1"
        usage
        exit 1
        ;;
    esac
  done

  is_positive_int "$INTERVAL" || { err "Intervalo inválido: $INTERVAL"; exit 1; }
  is_positive_int "$DISTANCE" || { err "Distância inválida: $DISTANCE"; exit 1; }
  is_positive_number "$HOLD" || { err "Hold inválido: $HOLD"; exit 1; }
}

main() {
  local cmd="${1:-help}"
  shift || true

  case "$cmd" in
    run)
      parse_options "$@"
      run_loop
      ;;
    start)
      parse_options "$@"
      start_cmd
      ;;
    stop)
      stop_cmd
      ;;
    status)
      status_cmd
      ;;
    restart)
      parse_options "$@"
      stop_cmd >/dev/null 2>&1 || true
      start_cmd
      ;;
    toggle)
      parse_options "$@"
      toggle_cmd
      ;;
    list-devices)
      list_devices_cmd
      ;;
    help)
      usage
      ;;
    version)
      echo "$VERSION"
      ;;
    *)
      err "Comando inválido: $cmd"
      usage
      exit 1
      ;;
  esac
}

main "$@"
