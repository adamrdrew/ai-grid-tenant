# Internal model deployments

This app owns the internal `LLMInferenceService` deployment and its
model-facing MaaS resources. Supporting namespaces, NetworkPolicies, and the
Grid `ExternalProvider` are owned by the RHOAI apps.

## Scheduler metrics

Without them a provider reports `Ready=Unknown`, reason
`MetricsNotConfigured`, and its candidate publishes no load. The RHOAI
prerequisites policy admits `redhat-ai-grid` to the scheduler's metrics port:

```yaml
spec:
  metricsConfig:
    endpoint: http://<model>-epp-service.ai-grid-internal-models.svc.cluster.local:9090
    path: /metrics
    timeout: 2s
    auth:
      type: serviceAccountToken
      allowPlaintext: true
```

Set by hand: provider names carry the source UID and change on every recreate.
[odh-model-controller#986](https://github.com/opendatahub-io/odh-model-controller/pull/986)
generates it once it ships, enabled by `publishMetrics: true` in the Gateway's
serving configuration. Do not set that key before the controller supports it;
the annotation is strict-unmarshalled, so an unknown key publishes no provider
at all.

`allowPlaintext` is lab-only. The metrics port declares no `appProtocol`, so the
token crosses in the clear; declaring `appProtocol: https` is the fix.

Scraping looks like `Ready=True` with a ready-endpoint count and
`MetricsAvailable=True`, reason `ScrapeSucceeded`.

## The provider console's catalog

The provider console
([ai-grid-cloud/ai-grid-provider-console](https://github.com/ai-grid-cloud/ai-grid-provider-console))
saves models and subscriptions as commits to a catalog repository,
[ai-grid-cloud/ai-grid-1-catalog](https://github.com/ai-grid-cloud/ai-grid-1-catalog). That URL is the only
value another environment changes: it appears in the two AppProjects and the three ApplicationSets in
`hub/catalog-*`, and in the console's `apps/console/application.yaml`.

The `catalog-*` files in `hub/` deliver it to the clusters Placement `acm-models-catalog` selects (ClusterSet
`global`; narrow it with predicates):

| Catalog path | ApplicationSet | Namespace | Clusters |
|---|---|---|---|
| `catalog/clusters/<cluster>/` | `acm-models-catalog-models` | `ai-grid-internal-models` | Each selected cluster that has a folder: the folder names are where models run |
| `catalog/ingress/` | `acm-models-catalog-ingress` | `models-as-a-service` | Each selected cluster, once the folder exists |
| `catalog/subscriptions/` | `acm-models-catalog-subscriptions` | `models-as-a-service` | Each selected cluster, once the folder exists |

An empty catalog repository generates no Applications, so it shows no errors before the console's first write.

The console's token can push to the catalog, so the catalog's Applications run in two AppProjects that admit only
that repository, no cluster-scoped kinds, and only the kinds the console writes:

- `acm-models-catalog-models`: LLMInferenceService and NetworkPolicy.
- `acm-models-catalog-maas`: ExternalModel, MaaSModelRef, MaaSSubscription and MaaSAuthPolicy.

A catalog file that collides with an object another Application manages, such as a sample model, stops that
cluster's catalog sync until it's fixed (`FailOnSharedResource`).

Deletion differs by design. Deleting the models ApplicationSet, or a cluster's folder, leaves its models running
(`preserveResourcesOnDeletion`). Deleting an ingress or subscriptions Application deletes its MaaS objects with
it (the resources finalizer), so no access outlives its Application. A teardown can therefore leave a model running
with no MaaS entry: delete its LLMInferenceService by hand.

`apps/ai-grid-policies` reports the catalog's state back to the hub, where the console reads it:

- `ai-grid-models-status`: each LLMInferenceService is Ready.
- `ai-grid-catalog-status`: each MaaSModelRef and ExternalModel is Ready, and each MaaSSubscription and
  MaaSAuthPolicy is Active.

**Not routed by the grid yet.** A catalog model is deployed and registered in MaaS, but MaaS reaches it through
the grid's gateways, and those list their backends by hand (`deployment/clusters/*`, plus a declared
InferenceProvider for a model on another site) until odh-model-controller#986 publishes them. So the console can
show a model Ready while a request to it finds no route, until its backend is added.

Keep anything privileged out of the catalog repository: whoever holds the console's token can write it.
