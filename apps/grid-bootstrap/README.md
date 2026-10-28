# Grid bootstrap

This hub Application deploys the existing `grid-enrollment` chart from
`odh-gitops:feature-ai-grid` in external mode. `managedClusters.enabled` selects
inventory-based enrollment through the common ACM/OCM APIs. The chart itself
has no Argo-specific switch.

The existing `redhat-ai-grid/grid-ca` Issuer continues to use `grid-ca-key`.
Bootstrap never regenerates the CA. Selected clusters have the `ai-grid/enabled`
label and use their ManagedCluster name as the site identity. The hub is enrolled
through the same flow as other members.

The chart requests a Certificate per selected member, delivers the identity and
public CA bundle, and installs a read-only GridSite observer per cluster. It
watches public endpoint metadata and distributes remote GridSites to peers,
with a site-only operator ConfigMap on each member. Model discovery uses the
Local operator's HTTPS provider catalog. The CA signing key remains on the hub.

This is the identity-preparation phase. The existing enrollment service stays
running and operator runtime membership is not changed by these values. Merge
the ODH chart update first. After identities and policies reconcile, use the
separate runtime cutover to select Local membership on every site, publish local
endpoints, and remove the service and SWIM delivery.

## Verify before runtime cutover

Use an explicit hub context and inspect metadata, not Secret data:

```sh
kubectl --context "$HUB_CONTEXT" -n openshift-gitops get applications.argoproj.io grid-bootstrap
kubectl --context "$HUB_CONTEXT" -n redhat-ai-grid get issuers.cert-manager.io grid-ca
kubectl --context "$HUB_CONTEXT" -n redhat-ai-grid get certificates.cert-manager.io
kubectl --context "$HUB_CONTEXT" -n redhat-ai-grid get policies.policy.open-cluster-management.io
kubectl --context "$HUB_CONTEXT" get manifestworks.work.open-cluster-management.io -A
kubectl --context "$HUB_CONTEXT" -n redhat-ai-grid get secret grid-ca-key \
  -o jsonpath='{.metadata.uid}{"\n"}'
```

The CA UID must be unchanged, both site Certificates Ready, and identity policies
Compliant. Check each cluster's `grid-site-identity` has the corresponding
`cert-manager.io/certificate-name` annotation and that its GridNetwork accepts the
identity. During preparation an observer can report missing endpoints; the runtime
cutover declares each member's source GridSite and signals Route.

Read-only observers must never overwrite source GridSites. After cutover, change
one source endpoint through Git and verify it appears on the other member without
copying status or changing the source. Restore the endpoint through Git. Removal
of a selection label withdraws peer records and stops certificate renewal; verify
withdrawal before removing identities or detaching a cluster. The CA is retained.

If preparation fails, fix or revert these policies through Git while retaining
the CA and identities. Removing a Certificate stops renewal but does not revoke
an issued certificate or guarantee deletion of its Secret. Do not switch the CA
to Generate as a recovery action.
