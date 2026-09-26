#!/usr/bin/env bash
###############################################################################
# Regenerates the Grafana dashboard ConfigMap from the JSON files in
# grafana/dashboards/.
#
# WHY A GENERATOR AND NOT A HAND-WRITTEN ConfigMap:
# a Grafana dashboard is a 13-500 KB JSON blob. Pasting one into YAML by hand is
# how you get a subtly corrupted dashboard six months later. Run this instead,
# and commit the output — the committed file is what Argo CD syncs.
#
# ONLY the repo-specific dashboards go in here. The four community dashboards
# (node-exporter-full 1860, docker-cadvisor 19792, docker-monitoring 14282,
# prometheus-stats 3662) are fetched at pod start by the initContainer in
# grafana/deployment.yaml — node-exporter-full alone is 468 KB, and a ConfigMap
# has a hard 1 MiB limit that kubectl apply eats into with its
# last-applied-configuration annotation.
#
# Usage:  ./k8s/scripts/render-dashboards.sh
###############################################################################
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="${REPO_ROOT}/grafana/dashboards"
OUT="${REPO_ROOT}/k8s/production/monitoring/grafana/configmap-dashboards.yaml"

# Repo-specific dashboards only. Add a filename here when you build a new one.
DASHBOARDS=(
  backend-red.json
  tracing-tempo.json
)

ARGS=()
for d in "${DASHBOARDS[@]}"; do
  if [[ ! -f "${SRC}/${d}" ]]; then
    echo "ERROR: ${SRC}/${d} not found" >&2
    exit 1
  fi
  ARGS+=("--from-file=${d}=${SRC}/${d}")
done

{
  cat <<'HEADER'
# ============================================================================
#  GENERATED FILE — DO NOT EDIT BY HAND.
#  Regenerate with:  ./k8s/scripts/render-dashboards.sh
#
#  Repo-specific Grafana dashboards, mounted read-only at
#  /var/lib/grafana/dashboards/custom and picked up by the file provisioner
#  (see configmap-dashboard-provider.yaml).
# ============================================================================
HEADER
  kubectl create configmap grafana-dashboards \
    --namespace monitoring \
    --dry-run=client -o yaml \
    "${ARGS[@]}" \
  | sed -e '/^  creationTimestamp: null$/d' \
        -e 's|^  name: grafana-dashboards$|  name: grafana-dashboards\n  labels:\n    app.kubernetes.io/name: grafana\n    app.kubernetes.io/component: dashboards\n    app.kubernetes.io/part-of: task-manager|'
} > "${OUT}"

echo "Wrote ${OUT} ($(wc -c < "${OUT}") bytes)"
