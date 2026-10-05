#!/usr/bin/env bash
###############################################################################
# Creates the Kubernetes Secrets this repo deliberately keeps OUT of git, from
# the one-value-per-file folder secrets/ (the same files Compose used).
#
#   namespace   secret                key                     <- file in secrets/
#   tasks-db    mysql-secrets         mysql_root_password     <- mysql_root_password
#                                     db_password             <- db_password
#   tasks-app   backend-secrets       db_password             <- db_password
#   tasks-app   cloudflared-telegram  telegram_token          <- telegram_token
#   monitoring  grafana-secrets       grafana_admin_password  <- grafana_admin_password
#   monitoring  alertmanager-secrets  telegram_token          <- telegram_token
#
# (replication_password and traefik_dashboard_users are Compose-only: nothing
#  in k8s/production reads them any more. cloudflared-telegram is read only by
#  the test tunnel k8s/trycloudflared-test/02-cloudflared-tasks.yaml.)
#
# Usage — on a machine whose kubectl reaches the cluster (rke2-cp1):
#   bash k8s/scripts/create-secrets.sh                    # every namespace
#   bash k8s/scripts/create-secrets.sh monitoring         # only these namespaces
#   bash k8s/scripts/create-secrets.sh --check            # report only, change nothing
#   bash k8s/scripts/create-secrets.sh --force tasks-app  # overwrite a different value
#   SECRETS_DIR=/root/secrets bash k8s/scripts/create-secrets.sh
#
# secrets/* is gitignored, so a fresh clone on the node only has the .example
# files. Copy the real ones over SSH first:
#   scp -r secrets root@rke2-cp1:/root/devops-mosalam-lab-2/
#
# Checked BEFORE anything is created:
#   * the file exists and is not empty ............ ✘  that Secret is skipped
#   * the file differs from its .example .......... !  .example is in git = public
#   * the namespace exists ........................ ✘  Argo CD creates them
#   * db_password ends up identical in tasks-db and tasks-app
#
# Never overwrites an existing Secret with a DIFFERENT value unless --force.
# MySQL reads its passwords only on the FIRST boot of an empty volume, and
# Grafana sets the admin password only on its first start; changing the Secret
# afterwards changes nothing in either, and for MySQL it breaks the backend
# ("Access denied"). Change the password inside the app first, then --force.
#
# Values are passed to kubectl as files in a private temp dir, never as command
# line arguments (those are visible to every user in `ps`). A trailing newline
# or Windows \r is stripped, because it would become part of the password.
#
# Exit code: 0 everything is in place, 1 something missing/differs, 2 usage.
###############################################################################
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SECRETS_DIR="${SECRETS_DIR:-${REPO_ROOT}/secrets}"

# namespace|secret|key=file key=file ...
SPECS=(
  "tasks-db|mysql-secrets|mysql_root_password=mysql_root_password db_password=db_password"
  "tasks-app|backend-secrets|db_password=db_password"
  "tasks-app|cloudflared-telegram|telegram_token=telegram_token"
  "monitoring|grafana-secrets|grafana_admin_password=grafana_admin_password"
  "monitoring|alertmanager-secrets|telegram_token=telegram_token"
)

# Changing a Secret's value (--force) is not the whole job: pods do not re-read
# it, and two of these apps only read it once, ever.
declare -A BEFORE_CHANGE=(
  [mysql-secrets]="BEFORE --force: change the password inside MySQL (ALTER USER) — it reads this Secret only on first boot"
)
declare -A AFTER_CHANGE=(
  [mysql-secrets]="kubectl -n tasks-db rollout restart sts/mysql-simple"
  [backend-secrets]="kubectl -n tasks-app rollout restart deploy/backend"
  [cloudflared-telegram]="kubectl -n tasks-app rollout restart deploy/cloudflared-tasks   (new link, sent with the new token)"
  [grafana-secrets]="kubectl -n monitoring exec deploy/grafana -- grafana cli admin reset-admin-password '<new>'   (Grafana reads it only on first start)"
  [alertmanager-secrets]="kubectl -n monitoring rollout restart sts/alertmanager"
)

# Where each value comes from, for the "missing file" hint.
declare -A HOW_TO_MAKE=(
  [mysql_root_password]="openssl rand -base64 18 | tr -d '\\n' > secrets/mysql_root_password"
  [db_password]="openssl rand -base64 18 | tr -d '\\n' > secrets/db_password"
  [grafana_admin_password]="openssl rand -base64 18 | tr -d '\\n' > secrets/grafana_admin_password"
  [telegram_token]="printf '%s' '<token from @BotFather>' > secrets/telegram_token"
)

CHECK_ONLY=0
FORCE=0
ONLY=()
for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=1 ;;
    --force) FORCE=1 ;;
    -h|--help) awk '/^#{10}/{n++; next} n==1{sub(/^# ?/, ""); print}' "$0"; exit 0 ;;
    -*) echo "unknown option: $arg (see --help)" >&2; exit 2 ;;
    *) ONLY+=("$arg") ;;
  esac
done

if [[ -t 1 ]]; then
  RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
else
  RED=''; GREEN=''; YELLOW=''; BOLD=''; RESET=''
fi
PROBLEMS=0
WARNINGS=0
ok()   { printf '  %s✔%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '  %s!%s %s\n' "$YELLOW" "$RESET" "$*"; WARNINGS=$((WARNINGS + 1)); }
bad()  { printf '  %s✘%s %s\n' "$RED" "$RESET" "$*"; PROBLEMS=$((PROBLEMS + 1)); }
hint() { printf '      %s\n' "$*"; }

# File content without trailing newlines ($(<) drops them) and without a
# trailing \r left by an editor on Windows.
read_value() {
  local v
  v="$(<"$1")"
  printf '%s' "${v%$'\r'}"
}

wanted() {
  local ns="$1" o
  if [[ ${#ONLY[@]} -eq 0 ]]; then return 0; fi
  for o in "${ONLY[@]}"; do
    if [[ "$o" == "$ns" ]]; then return 0; fi
  done
  return 1
}

# --- preflight ---------------------------------------------------------------
command -v kubectl >/dev/null || { echo "kubectl not found in PATH" >&2; exit 1; }
if ! kubectl get --raw /readyz --request-timeout=5s >/dev/null 2>&1; then
  echo "kubectl cannot reach the cluster (kubectl get --raw /readyz failed)" >&2
  exit 1
fi
if [[ ! -d "$SECRETS_DIR" ]]; then
  echo "${SECRETS_DIR} does not exist." >&2
  echo "secrets/ is gitignored; copy it from your machine:" >&2
  echo "  scp -r secrets root@rke2-cp1:${REPO_ROOT}/" >&2
  exit 1
fi
for o in ${ONLY[@]+"${ONLY[@]}"}; do
  found=0
  for spec in "${SPECS[@]}"; do
    if [[ "${spec%%|*}" == "$o" ]]; then found=1; fi
  done
  if [[ $found -eq 0 ]]; then
    echo "no secrets are defined for namespace '$o' (known: tasks-db tasks-app monitoring)" >&2
    exit 2
  fi
done

TMP="$(mktemp -d)"
chmod 700 "$TMP"
trap 'rm -rf "$TMP"' EXIT

mode=''
if [[ $CHECK_ONLY -eq 1 ]]; then mode='  (--check: nothing will be changed)'; fi
echo "${BOLD}Secrets from ${SECRETS_DIR}${RESET}${mode}"

loose="$(find "$SECRETS_DIR" -maxdepth 1 -type f ! -name '*.example' -perm -o+r 2>/dev/null || true)"
if [[ -n "$loose" ]]; then
  printf '\n'
  warn "readable by every user on this machine: $(echo "$loose" | xargs -n1 basename | tr '\n' ' ')"
  hint "chmod 600 ${SECRETS_DIR}/*"
fi

# --- one Secret at a time ----------------------------------------------------
for spec in "${SPECS[@]}"; do
  IFS='|' read -r ns name pairs <<<"$spec"
  wanted "$ns" || continue
  printf '\n%s%s/%s%s\n' "$BOLD" "$ns" "$name" "$RESET"

  dir="${TMP}/${ns}-${name}"
  mkdir "$dir"
  complete=1

  for pair in $pairs; do
    key="${pair%%=*}"
    fname="${pair#*=}"
    file="${SECRETS_DIR}/${fname}"

    if [[ ! -f "$file" ]]; then
      bad "${key}: secrets/${fname} is missing"
      hint "${HOW_TO_MAKE[$key]:-create secrets/${fname} with the value in it}"
      complete=0
      continue
    fi
    value="$(read_value "$file")"
    if [[ -z "$value" ]]; then
      bad "${key}: secrets/${fname} is empty"
      hint "${HOW_TO_MAKE[$key]:-put the value in secrets/${fname}}"
      complete=0
      continue
    fi
    if [[ "$value" == *$'\n'* ]]; then
      warn "${key}: secrets/${fname} has more than one line; the whole file becomes the value"
    fi
    if [[ -f "${file}.example" && "$value" == "$(read_value "${file}.example")" ]]; then
      warn "${key}: identical to secrets/${fname}.example, which is committed to git — this value is PUBLIC"
    elif [[ "$value" == CHANGE_ME* ]]; then
      warn "${key}: still a CHANGE_ME placeholder"
    fi

    printf '%s' "$value" >"${dir}/${key}"
    ok "${key} <- secrets/${fname} (${#value} chars)"
  done

  if ! kubectl get namespace "$ns" >/dev/null 2>&1; then
    bad "namespace ${ns} does not exist yet — Argo CD's task-manager-namespaces creates it"
    continue
  fi
  if [[ $complete -eq 0 ]]; then
    bad "${name} not created — fix the file(s) above and run again"
    continue
  fi

  if kubectl -n "$ns" get secret "$name" >/dev/null 2>&1; then
    differs=()
    for f in "$dir"/*; do
      key="$(basename "$f")"
      live="$(kubectl -n "$ns" get secret "$name" -o "jsonpath={.data.${key}}" | base64 -d 2>/dev/null || true)"
      if [[ "$live" != "$(<"$f")" ]]; then differs+=("$key"); fi
    done
    if [[ ${#differs[@]} -eq 0 ]]; then
      ok "${name} already in the cluster with the same values — unchanged"
      continue
    fi
    if [[ $FORCE -eq 0 ]]; then
      bad "${name} exists with a DIFFERENT value for: ${differs[*]} — left as is"
      hint "the cluster's value is what the running app uses. To replace it:"
      if [[ -n "${BEFORE_CHANGE[$name]:-}" ]]; then hint "1) ${BEFORE_CHANGE[$name]}"; fi
      hint "2) bash k8s/scripts/create-secrets.sh --force ${ns}"
      hint "3) ${AFTER_CHANGE[$name]}"
      continue
    fi
    action="updated"
  else
    action="created"
  fi

  if [[ $CHECK_ONLY -eq 1 ]]; then
    ok "${name} would be ${action}"
    continue
  fi
  kubectl -n "$ns" create secret generic "$name" --from-file="$dir" --dry-run=client -o yaml \
    | kubectl label --local -f - -o yaml \
        app.kubernetes.io/part-of=task-manager \
        app.kubernetes.io/managed-by=create-secrets.sh \
    | kubectl apply -f - >/dev/null
  ok "${name} ${action}"
  if [[ "$action" == "updated" ]]; then
    hint "pods do not pick this up by themselves — now run: ${AFTER_CHANGE[$name]}"
  fi
done

# --- db_password must match across the two namespaces ------------------------
if wanted tasks-db || wanted tasks-app; then
  a="$(kubectl -n tasks-db get secret mysql-secrets -o 'jsonpath={.data.db_password}' 2>/dev/null || true)"
  b="$(kubectl -n tasks-app get secret backend-secrets -o 'jsonpath={.data.db_password}' 2>/dev/null || true)"
  printf '\n%sdb_password across namespaces%s\n' "$BOLD" "$RESET"
  if [[ -z "$a" || -z "$b" ]]; then
    warn "cannot compare: one of mysql-secrets / backend-secrets does not exist yet"
  elif [[ "$(base64 -d <<<"$a")" == "$(base64 -d <<<"$b")" ]]; then
    ok "tasks-db/mysql-secrets and tasks-app/backend-secrets hold the same db_password"
  else
    bad "db_password differs between tasks-db and tasks-app — the backend gets 'Access denied for user appuser'"
  fi
fi

# --- summary -----------------------------------------------------------------
printf '\n'
if [[ $PROBLEMS -gt 0 ]]; then
  printf '%s%d problem(s)%s, %d warning(s). Nothing above marked ✘ was changed.\n' "$RED" "$PROBLEMS" "$RESET" "$WARNINGS"
  exit 1
fi
printf '%sAll secrets in place%s, %d warning(s).\n' "$GREEN" "$RESET" "$WARNINGS"
