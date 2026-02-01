#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSTANCES_DIR="$ROOT_DIR/instances"

usage() {
  cat <<EOF
Usage: ./scripts/manager.sh <command> [instance]

Commands:
  list                              List instances
  setup                             Create a new instance
  start <instance>                  docker compose up -d
  stop <instance>                   docker compose stop
  restart <instance>                docker compose restart
  down <instance>                   docker compose down
  remove <instance>                 Stop, down, and delete instance directory
  logs <instance>                   docker compose logs -f
  backup <instance>                 Create a backup tar.gz
  update <instance> [--no-backup]   Update instance (download + restart)
  status                            List instances and container status/auth
EOF
}

resolve_instance() {
  local input=${1:-}
  if [[ -z "$input" ]]; then
    echo "Instance required." >&2
    usage
    exit 1
  fi
  if [[ -d "$input" ]]; then
    echo "$(cd "$input" && pwd)"
    return
  fi
  if [[ -d "$INSTANCES_DIR/$input" ]]; then
    echo "$INSTANCES_DIR/$input"
    return
  fi
  echo "Instance not found: $input" >&2
  exit 1
}

need_compose() {
  local instance_dir=$1
  if [[ ! -f "$instance_dir/docker-compose.yml" ]]; then
    echo "Missing docker-compose.yml in $instance_dir" >&2
    exit 1
  fi
}

service_name() {
  local instance_dir=$1
  local env_file="$instance_dir/.env"
  local name="hytale"
  if [[ -f "$env_file" ]]; then
    name=$(grep -E '^HT_SERVICE_NAME=' "$env_file" | cut -d= -f2- | tr -d '\r')
  fi
  if [[ -z "$name" ]]; then
    name="hytale"
  fi
  echo "$name"
}

container_id() {
  local instance_dir=$1
  local env_file="$instance_dir/.env"
  local compose_file="$instance_dir/docker-compose.yml"
  local override=""
  if [[ -f "$env_file" ]]; then
    override=$(grep -E '^HT_CONTAINER_NAME=' "$env_file" | cut -d= -f2- | tr -d '\r')
  fi
  if [[ -n "$override" ]]; then
    echo "$override"
    return
  fi
  local svc
  svc=$(service_name "$instance_dir")
  docker compose -f "$compose_file" ps -q "$svc" 2>/dev/null | head -n 1
}

print_server_ready() {
  local instance_dir=$1
  local env_file="$instance_dir/.env"
  local host_port="5520"
  if [[ -f "$env_file" ]]; then
    host_port=$(grep -E '^HOST_PORT=' "$env_file" | cut -d= -f2- | tr -d '\r')
  fi
  echo "Server is up. Connect to: 0.0.0.0:${host_port}"
}

run_compose_quiet() {
  local compose_file=$1
  shift
  if output=$(docker compose -f "$compose_file" "$@" 2>&1); then
    return 0
  fi
  echo "$output" >&2
  return 1
}

wait_for_container_state() {
  local container_name=$1
  local target=$2
  local max_tries=${3:-30}
  for _ in $(seq 1 "$max_tries"); do
    state=$(docker inspect -f '{{.State.Status}}' "$container_name" 2>/dev/null || echo "unknown")
    if [[ "$state" == "$target" ]]; then
      return 0
    fi
    sleep 1
  done
  return 1
}

set_env_kv() {
  local env_file=$1
  local key=$2
  local value=$3
  if grep -qE "^${key}=" "$env_file"; then
    sed -i -E "s|^${key}=.*|${key}=${value}|" "$env_file"
  else
    printf "%s=%s\n" "$key" "$value" >> "$env_file"
  fi
}

apply_export_tokens() {
  local instance_dir=$1
  local env_file="$instance_dir/.env"
  local export_file="$instance_dir/.auth/export.env"
  if [[ ! -f "$export_file" ]]; then
    return 0
  fi
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    case "$line" in
      HYTALE_SERVER_SESSION_TOKEN=*|HYTALE_SERVER_IDENTITY_TOKEN=*|HYTALE_SERVER_OWNER_UUID=*)
        key=${line%%=*}
        value=${line#*=}
        set_env_kv "$env_file" "$key" "$value"
        ;;
    esac
  done < "$export_file"
}

ensure_server_cmd() {
  local instance_dir=$1
  local env_file="$instance_dir/.env"
  local current
  current=$(grep -E '^HT_SERVER_CMD=' "$env_file" | cut -d= -f2- | tr -d '\r')
  if [[ -n "$current" ]]; then
    return 0
  fi
  if [[ -x "$instance_dir/server/start.sh" || -f "$instance_dir/server/start.sh" ]]; then
    set_env_kv "$env_file" "HT_SERVER_CMD" "./server/start.sh"
    return 0
  fi
  if [[ -x "$instance_dir/server/HytaleServer" || -f "$instance_dir/server/HytaleServer" ]]; then
    set_env_kv "$env_file" "HT_SERVER_CMD" "./server/HytaleServer"
    return 0
  fi
  if [[ -x "$instance_dir/server/HytaleServer.sh" || -f "$instance_dir/server/HytaleServer.sh" ]]; then
    set_env_kv "$env_file" "HT_SERVER_CMD" "./server/HytaleServer.sh"
  fi
}

auth_missing() {
  local instance_dir=$1
  local env_file="$instance_dir/.env"
  if [[ ! -f "$env_file" ]]; then
    return 0
  fi
  local token
  token=$(grep -E '^HYTALE_SERVER_SESSION_TOKEN=' "$env_file" | cut -d= -f2- | tr -d '\r')
  [[ -z "$token" ]]
}

send_console_cmd() {
  local instance_dir=$1
  local command=$2
  local env_file="$instance_dir/.env"
  # shellcheck disable=SC1090
  set -a
  . "$env_file"
  set +a
  local cid
  cid=$(container_id "$instance_dir")
  if [[ -z "$cid" ]]; then
    echo "Container not found for $instance_dir" >&2
    return 1
  fi
  # Try direct exec into PID 1 stdin; fall back to docker compose exec.
  if docker exec -i "$cid" bash -lc "printf '%s\r\n' \"$command\" > /proc/1/fd/0" >/dev/null 2>&1; then
    return 0
  fi
  if [[ -f "$instance_dir/docker-compose.yml" ]]; then
    docker compose -f "$instance_dir/docker-compose.yml" exec -T "$(service_name "$instance_dir")" \
      sh -lc "printf '%s\r\n' \"$command\" > /proc/1/fd/0" >/dev/null 2>&1 && return 0
  fi
  echo "Failed to send command to container console." >&2
  return 1
}

graceful_stop() {
  local instance_dir=$1
  local env_file="$instance_dir/.env"
  if [[ ! -f "$env_file" ]]; then
    return 0
  fi
  local stop_cmd
  stop_cmd=$(grep -E '^HT_STOP_CMD=' "$env_file" | cut -d= -f2- | tr -d '\r')
  if [[ -z "$stop_cmd" ]]; then
    stop_cmd="/stop"
  fi
  if [[ -n "$stop_cmd" ]]; then
    send_console_cmd "$instance_dir" "$stop_cmd" || true
    sleep 2
  fi
}

auth_flow() {
  local instance_dir=$1
  local compose_file="$instance_dir/docker-compose.yml"
  run_compose_quiet "$compose_file" up -d

  echo "Auth required for $(basename "$instance_dir")."
  local env_file="$instance_dir/.env"
  # shellcheck disable=SC1090
  set -a
  . "$env_file"
  set +a
  local cid
  cid=$(container_id "$instance_dir")

  if [[ -z "$cid" ]]; then
    echo "Container not found for $instance_dir" >&2
    exit 1
  fi

  if ! wait_for_container_state "$cid" "running" 20; then
    state=$(docker inspect -f '{{.State.Status}}' "$cid" 2>/dev/null || echo "unknown")
    echo "Container not running yet (state=$state). Try again after it stabilizes." >&2
    exit 1
  fi

  if command -v expect >/dev/null 2>&1; then
    EXPECT_CMD="docker compose -f \"$compose_file\" attach $(service_name "$instance_dir")"
    EXPECT_CMD="$EXPECT_CMD" expect <<'EXP'
      set timeout -1
      log_user 0
      set cmd $env(EXPECT_CMD)
      set sent_persist 0
      spawn sh -lc $cmd
      expect {
        -re {Use /auth login to authenticate\.} { send "/auth login device\r"; exp_continue }
        -re {Or visit: (.*)} {
          puts "Click the link below to approve the server instance creation:"
          puts $expect_out(1,string)
          exp_continue
        }
        -re {Authentication successful!} {
          if {$sent_persist == 0} {
            send "/auth persistence Encrypted\r"
            set sent_persist 1
          }
          exp_continue
        }
        -re {Credential storage changed to: Encrypted} {
          send "\003"
          exit 0
        }
      }
EXP
    print_server_ready "$instance_dir"
    return
  fi

  echo "Waiting for server boot before starting device login..."
  for _ in {1..90}; do
    if docker compose -f "$compose_file" logs --tail 200 | grep -q "Hytale Server Booted"; then
      break
    fi
    sleep 1
  done

  # Wait until the console module is ready before issuing auth commands.
  for _ in {1..30}; do
    if docker compose -f "$compose_file" logs --tail 200 | grep -q "Setup console with type"; then
      break
    fi
    sleep 1
  done

  echo "Starting device login..."

  if ! send_console_cmd "$instance_dir" "/auth login device"; then
    echo "Could not inject /auth command; attaching for manual auth." >&2
    echo "Run: /auth login device" >&2
    "$ROOT_DIR/scripts/auth.sh" "$instance_dir"
    return
  fi

  echo "Waiting for the one-click verification link..."
  docker compose -f "$compose_file" logs -f --tail 200 | \
    awk '
      /Or visit:/ {
        sub(/.*Or visit: /, "", $0);
        print $0;
        fflush();
      }
      /Authentication successful! Use \/auth status to view details\./ {
        exit 0
      }
    '

  send_console_cmd "$instance_dir" "/auth persistence Encrypted" || true
  echo "Sent /auth persistence Encrypted."
  print_server_ready "$instance_dir"
}

cmd=${1:-}
shift || true

case "$cmd" in
  list)
    if [[ ! -d "$INSTANCES_DIR" ]]; then
      echo "No instances directory found."
      exit 0
    fi
    find "$INSTANCES_DIR" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | sort
    ;;
  setup)
    "$ROOT_DIR/scripts/setup.sh"
    ;;
  start)
    instance_dir=$(resolve_instance "${1:-}")
    need_compose "$instance_dir"
    ensure_server_cmd "$instance_dir"
    apply_export_tokens "$instance_dir"
    run_compose_quiet "$instance_dir/docker-compose.yml" up -d
    if auth_missing "$instance_dir"; then
      auth_flow "$instance_dir"
    else
      print_server_ready "$instance_dir"
    fi
    ;;
  stop)
    instance_dir=$(resolve_instance "${1:-}")
    need_compose "$instance_dir"
    graceful_stop "$instance_dir"
    run_compose_quiet "$instance_dir/docker-compose.yml" stop
    env_file="$instance_dir/.env"
    if [[ -f "$env_file" ]]; then
      # shellcheck disable=SC1090
      set -a
      . "$env_file"
      set +a
      container_name=$(container_id "$instance_dir")
    else
      container_name=$(container_id "$instance_dir")
    fi
    if wait_for_container_state "$container_name" "exited" 20; then
      echo "Container stopped."
    else
      echo "Container stop requested; still stopping." >&2
    fi
    ;;
  restart)
    instance_dir=$(resolve_instance "${1:-}")
    need_compose "$instance_dir"
    docker compose -f "$instance_dir/docker-compose.yml" restart
    ;;
  down)
    instance_dir=$(resolve_instance "${1:-}")
    need_compose "$instance_dir"
    docker compose -f "$instance_dir/docker-compose.yml" down
    ;;
  remove)
    instance_dir=$(resolve_instance "${1:-}")
    need_compose "$instance_dir"
    force=${2:-}
    if [[ "$force" != "--yes" ]]; then
      read -r -p "Remove instance $(basename "$instance_dir")? This deletes files. (y/N): " CONFIRM_REMOVE
      CONFIRM_REMOVE=${CONFIRM_REMOVE:-N}
      if [[ ! "${CONFIRM_REMOVE}" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
      fi
    fi
    run_compose_quiet "$instance_dir/docker-compose.yml" down
    rm -rf "$instance_dir"
    echo "Removed instance."
    ;;
  logs)
    instance_dir=$(resolve_instance "${1:-}")
    need_compose "$instance_dir"
    docker compose -f "$instance_dir/docker-compose.yml" logs -f
    ;;
  backup)
    instance_dir=$(resolve_instance "${1:-}")
    "$ROOT_DIR/scripts/backup.sh" "$instance_dir"
    ;;
  update)
    instance_dir=$(resolve_instance "${1:-}")
    "$ROOT_DIR/scripts/update.sh" "$instance_dir" "${2:-}"
    ;;
  status)
    if [[ ! -d "$INSTANCES_DIR" ]]; then
      echo "No instances directory found."
      exit 0
    fi
    printf "%-30s %-20s %-20s %-10s %-10s %-20s %-20s\n" "INSTANCE" "SERVICE" "CONTAINER" "STATUS" "PORT" "AUTH_AT" "AUTH_EXPIRES"
    for dir in "$INSTANCES_DIR"/*; do
      [[ -d "$dir" ]] || continue
      env_file="$dir/.env"
      tokens_file="$dir/.auth/tokens.json"
      instance_name=$(basename "$dir")
      service_name_value=$(service_name "$dir")
      container_name=$(container_id "$dir")
      host_port=""
      auth_at="-"
      auth_expires="-"
      if [[ -f "$env_file" ]]; then
        container_name=$(grep -E '^HT_CONTAINER_NAME=' "$env_file" | cut -d= -f2- | tr -d '\r')
        host_port=$(grep -E '^HOST_PORT=' "$env_file" | cut -d= -f2- | tr -d '\r')
      fi
      if [[ -f "$tokens_file" ]]; then
        auth_at=$(python3 - <<'PY' "$tokens_file" 2>/dev/null || echo "-"
import json, sys, datetime
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    data = json.load(handle)
token = data.get("access_token")
payload = data
created = data.get("created_at")
expires_in = data.get("expires_in")
if not created:
    try:
        import os
        ts = os.path.getmtime(path)
        created = datetime.datetime.utcfromtimestamp(ts).isoformat() + "Z"
    except Exception:
        created = "-"
if expires_in:
    try:
        dt = datetime.datetime.fromisoformat(created.replace("Z", "+00:00"))
        exp = dt + datetime.timedelta(seconds=int(expires_in))
        expires = exp.isoformat()
    except Exception:
        expires = "-"
else:
    expires = "-"
print(f"{created}|{expires}")
PY
)
        auth_expires=${auth_at#*|}
        auth_at=${auth_at%%|*}
      fi
      status="not found"
      if [[ -n "$container_name" ]]; then
        status=$(docker inspect -f '{{.State.Status}}' "$container_name" 2>/dev/null || echo "not found")
      fi
      printf "%-30s %-20s %-20s %-10s %-10s %-20s %-20s\n" "$instance_name" "$service_name_value" "${container_name:-"-"}" "$status" "$host_port" "$auth_at" "$auth_expires"
    done
    ;;
  ""|help|-h|--help)
    usage
    ;;
  *)
    echo "Unknown command: $cmd" >&2
    usage
    exit 1
    ;;
esac
