#!/usr/bin/env bash
# Renders the MaaS Gateway hostname policy and checks its ApplicationSet wiring.
# Needs helm, PyYAML and kubectl.
set -Eeuo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

helm template rhoai-gateway-hostname "$HERE/../gateway-hostname" \
  -f "$HERE/../values.yaml" \
  --set clusterNamespace=target-cluster > "$TMP_DIR/rendered.yaml"

python3 - "$TMP_DIR/rendered.yaml" "$HERE/../hub/01-applicationset.yaml" <<'PY'
import sys
import yaml

rendered_documents = list(yaml.safe_load_all(open(sys.argv[1])))
policy = next(document for document in rendered_documents
               if document and document.get("kind") == "ConfigurationPolicy")
assert policy["metadata"]["namespace"] == "target-cluster"
gateway = policy["spec"]["object-templates"][0]["objectDefinition"]
assert gateway["metadata"]["name"] == "maas-default-gateway"
assert gateway["metadata"]["namespace"] == "openshift-ingress"
hostnames = [listener["hostname"] for listener in gateway["spec"]["listeners"]]
assert hostnames == [
    "maas.{{ (lookup \"config.openshift.io/v1\" \"Ingress\" \"\" \"cluster\").spec.domain }}",
    "maas.{{ (lookup \"config.openshift.io/v1\" \"Ingress\" \"\" \"cluster\").spec.domain }}",
], hostnames

appset = yaml.safe_load(open(sys.argv[2]))
sources = appset["spec"]["template"]["spec"]["sources"]
source = next(item for item in sources if item.get("path") == "apps/rhoai/gateway-hostname")
assert source["helm"]["valueFiles"] == [
    "$values/apps/rhoai/values.yaml",
    '$values/apps/rhoai/roles/{{ index .metadata.labels "ai-grid/role" }}.yaml',
    "$values/apps/rhoai/values-{{ .name }}.yaml",
], source["helm"]["valueFiles"]
assert source["helm"]["ignoreMissingValueFiles"] is True
parameters = {parameter["name"]: parameter["value"]
              for parameter in source["helm"]["parameters"]}
assert parameters == {"clusterNamespace": "{{ .name }}",
                      "role": '{{ index .metadata.labels "ai-grid/role" }}'}
differences = next(item for item in appset["spec"]["template"]["spec"]["ignoreDifferences"]
                   if item.get("kind") == "Gateway")
assert differences["jqPathExpressions"] == [
    '.spec.listeners[] | select(.name == "http" and "{{ index .metadata.labels "ai-grid/role" }}" != "combined") | .hostname',
    '.spec.listeners[] | select(.name == "https" and "{{ index .metadata.labels "ai-grid/role" }}" != "combined") | .hostname',
]
PY

# An inference-only site has no MaaS Gateway: nothing renders there.
inference_objects=$(helm template rhoai-gateway-hostname "$HERE/../gateway-hostname" \
  -f "$HERE/../values.yaml" --set clusterNamespace=target-cluster --set role=inference |
  grep -c '^kind:' || true)
[ "$inference_objects" = 0 ] || { echo "gateway-hostname renders $inference_objects objects for role inference" >&2; exit 1; }

# Route mode: the policy discovers the external name from the cluster ingress domain.
helm template rhoai-gateway-hostname "$HERE/../gateway-hostname" \
  -f "$HERE/../values.yaml" --set clusterNamespace=target-cluster --set role=ingress \
  --set components.aigateway.modelsAsAService.gateway.openshiftRoute.enabled=true > "$TMP_DIR/route.yaml"
python3 - "$TMP_DIR/route.yaml" <<'PY'
import sys
import yaml

documents = [doc for doc in yaml.safe_load_all(open(sys.argv[1])) if doc]
assert len(documents) == 1
policy = documents[0]
assert policy["kind"] == "ConfigurationPolicy"
route = policy["spec"]["object-templates"][0]["objectDefinition"]
assert route["kind"] == "Route"
assert route["metadata"] == {"name": "maas-gateway-route", "namespace": "openshift-ingress"}
assert route["spec"]["host"] == 'maas.{{ (lookup "config.openshift.io/v1" "Ingress" "" "cluster").spec.domain }}'
gateway = policy["spec"]["object-templates"][1]["objectDefinition"]
assert gateway["kind"] == "Gateway"
assert gateway["spec"]["listeners"] == [
    {"name": "http", "hostname": None},
    {"name": "https", "hostname": None},
]
PY

echo "gateway-hostname tests: 3 ok, 0 failed"
