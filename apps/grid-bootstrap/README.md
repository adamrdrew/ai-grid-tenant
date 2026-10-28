# Grid bootstrap

This Application runs once on the hub and follows the bootstrap chart in
`odh-gitops:feature-ai-grid`. Merge the chart there before merging this app.
The root ApplicationSet discovers this directory automatically.

Bootstrap adds the namespaced cert-manager Issuer `redhat-ai-grid/grid-ca`,
referencing the existing `grid-ca-key` Secret. The enrollment service keeps
ownership of that CA. This Application neither generates a replacement CA
nor changes the existing site identities or enrollment deployment.

The next lifecycle stage, enroll, can request a Certificate for each managed
cluster and use ACM to deliver its identity. Decommission must withdraw that
site's membership and stop renewal before removing its ACM registration. Both
stages are separate from this bootstrap Application.

## Verify

Use an explicit hub context:

```sh
kubectl --context "$HUB_CONTEXT" -n openshift-gitops get application grid-bootstrap
kubectl --context "$HUB_CONTEXT" -n redhat-ai-grid get issuer grid-ca
kubectl --context "$HUB_CONTEXT" -n redhat-ai-grid wait issuer/grid-ca \
  --for=condition=Ready --timeout=120s
```

An unready Issuer indicates a missing or unsuitable CA Secret or an unavailable
cert-manager controller. Restore the existing CA if needed. Do not change the
mode to Generate to repair this installation.

Removing this Application removes its Issuer. It leaves the existing CA and
site Secrets intact. Certificate issuance through this Issuer stops, while
previously issued certificates retain their validity.
