# Grid bootstrap

Bootstrap is the first lifecycle phase of the existing `grid-enrollment` chart.
This hub Application follows `odh-gitops:feature-ai-grid` and selects its external
identity mode, with the optional cert-manager integration enabled.

It creates only the namespaced Issuer `redhat-ai-grid/grid-ca`, referencing the
existing `grid-ca-key` Secret. The current enrollment service remains running
in its original Application, and existing site identities keep their trust.
No site Certificates or ACM delivery policies are enabled by these values.

The Application name, Helm release name, destination, and Issuer name are kept
unchanged during migration from the temporary standalone bootstrap chart. Argo
updates the same Issuer in place; it does not transfer it to another Application.
Merge the ODH enrollment mode change first. Remove the obsolete standalone chart
only after this source change is Synced and Healthy.

## Verify

Use the explicit hub context:

```sh
kubectl --context "$HUB_CONTEXT" -n openshift-gitops get applications.argoproj.io grid-bootstrap
kubectl --context "$HUB_CONTEXT" -n redhat-ai-grid get issuers.cert-manager.io grid-ca
kubectl --context "$HUB_CONTEXT" -n redhat-ai-grid wait issuer/grid-ca \
  --for=condition=Ready --timeout=120s
```

The issuer must still reference `grid-ca-key`, and its UID should be unchanged.
An unready Issuer indicates an unavailable controller or an unsuitable CA Secret;
restore the existing CA rather than selecting Generate mode.

Enrollment will add site metadata and identity delivery. Decommission must
withdraw membership and stop renewal before cleanup and ACM detachment. These
later stages are not activated by this bootstrap migration.
