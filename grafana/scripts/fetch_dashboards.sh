#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="grafana/dashboards"
mkdir -p "$OUT_DIR"

download() {
  id="$1"
  name="$2"
  url="https://grafana.com/api/dashboards/${id}/revisions/latest/download"
  out="${OUT_DIR}/${name}-${id}.json"
  echo "Downloading ${name} (${id}) -> ${out}"
  curl -sSL "$url" -o "$out"
}

download 1860 "node-exporter-full"
download 19792 "docker-cadvisor"
download 14282 "docker-monitoring"
download 3662 "prometheus-stats"

echo "Dashboards downloaded to ${OUT_DIR}. Start Grafana with 'docker compose up -d grafana'"
