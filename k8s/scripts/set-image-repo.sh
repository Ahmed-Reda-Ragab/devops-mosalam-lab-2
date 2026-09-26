#!/usr/bin/env bash
###############################################################################
# Points the application manifests at a different container registry / account.
#
# The committed manifests carry a concrete repository (docker.io/<user>/...).
# Use this when you fork the repo, move to GHCR/ECR, or rotate the Docker Hub
# account — it rewrites both Deployments in one go and leaves the tag alone
# (CI owns the tag; see the bump-manifests job in .github/workflows/ci.yml).
#
# Usage:
#   ./k8s/scripts/set-image-repo.sh docker.io/myuser
#   ./k8s/scripts/set-image-repo.sh ghcr.io/myorg
#   ./k8s/scripts/set-image-repo.sh 123456789012.dkr.ecr.eu-west-1.amazonaws.com
#
# Commit the result — that commit is what Argo CD acts on.
###############################################################################
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <registry>/<namespace>    e.g. docker.io/myuser" >&2
  exit 2
fi

PREFIX="${1%/}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

for app in backend frontend; do
  manifest="${REPO_ROOT}/k8s/production/apps/${app}/deployment.yaml"
  [[ -f "$manifest" ]] || { echo "missing ${manifest}" >&2; exit 1; }

  # Keep the existing tag, replace everything before the image name.
  sed -i -E "s#^([[:space:]]*image:[[:space:]]*).*/(task-manager-${app}:.*)#\1${PREFIX}/\2#" "$manifest"

  line="$(grep -E '^[[:space:]]*image:' "$manifest")"
  echo "${app}: ${line#*image: }"
done

echo
echo "Done. Review with 'git diff' and commit — Argo CD deploys the commit."
