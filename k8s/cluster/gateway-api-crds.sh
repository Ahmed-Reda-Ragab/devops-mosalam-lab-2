#!/usr/bin/env bash
###############################################################################
# Installs the Gateway API CRDs.
#
# Cilium does NOT ship them: its Gateway controller watches for the CRDs and
# stays idle (no GatewayClass, no error that points at the cause) if they are
# absent. This is the single most common reason a Cilium Gateway "does nothing".
#
# --server-side is required: the HTTPRoute CRD schema is larger than the 262144
# byte annotation limit that client-side apply uses to store
# last-applied-configuration, so a plain `kubectl apply` fails outright.
#
# CHANNEL: "standard" carries GA resources (GatewayClass, Gateway, HTTPRoute,
# ReferenceGrant, GRPCRoute). "experimental" adds TCPRoute/TLSRoute/UDPRoute and
# alpha fields. Standard is enough for this platform.
#
# VERSION: must match what your Cilium version supports. Check
#   https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/
# and bump GATEWAY_API_VERSION to the version that page names. Installing a
# NEWER Gateway API than Cilium supports makes Cilium reject the CRDs it does
# not recognise, which again looks like "the Gateway does nothing".
###############################################################################
set -euo pipefail

GATEWAY_API_VERSION="${GATEWAY_API_VERSION:-v1.2.1}"
CHANNEL="${CHANNEL:-standard}"

BASE="https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}"

echo "Installing Gateway API ${GATEWAY_API_VERSION} (${CHANNEL} channel)..."
kubectl apply --server-side -f "${BASE}/${CHANNEL}-install.yaml"

echo
echo "CRDs present:"
kubectl get crd | grep gateway.networking.k8s.io || true

echo
echo "Next: kubectl apply -f cilium-helmchartconfig.yaml"
