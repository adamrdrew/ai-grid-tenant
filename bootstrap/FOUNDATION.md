# GitOps and ACM foundation only

This procedure prepares one OpenShift cluster as the Argo CD and ACM hub. It
does not register managed clusters or deploy the AI Grid workloads. Review the
change and use an explicit hub kubeconfig throughout.

Do not run `bootstrap.sh` for this scope. That script applies the root `apps`
ApplicationSet, which discovers every `apps/*/application.yaml` and starts the
rest of the stack.

## Review before cluster changes

1. Set `HUB_KUBECONFIG` to the hub's kubeconfig. Verify `oc --kubeconfig
   "$HUB_KUBECONFIG" whoami` and the API server in its current context.
2. Confirm the `redhat-operators` CatalogSource is Ready and offers the
   `openshift-gitops-operator` `latest` and
   `advanced-cluster-management` `release-2.17` channels.
3. Review `foundation-acm-application.yaml`. Its directory include selects
   only the ACM OperatorGroup, Subscription, and MultiClusterHub from Git.
   It uses the Application name `acm`, so the full root ApplicationSet can
   later take over that same Application deliberately.
4. Review the cluster-wide `cluster-admin` grant in
   `openshift-gitops-admin.yaml`. It gives the Argo CD application controller
   the permissions the existing repository expects. This grant should be
   approved separately from access to the Argo CD UI.

## Installation sequence after approval

1. Apply `namespace.yaml`, `gitops-operator-group.yaml`, and
   `openshift-gitops-sub.yaml` from this directory to the hub. These install
   the GitOps Operator and its default Argo CD instance.
2. Wait for the Application and ApplicationSet CRDs to become Established;
   confirm the GitOps Subscription and Argo CD controller are healthy.
3. Apply `openshift-gitops-admin.yaml` and
   `foundation-acm-application.yaml` to the hub. Argo CD then installs ACM
   `release-2.17` and creates the MultiClusterHub.
4. Confirm the `acm` Application, ACM Subscription, and MultiClusterHub are
   healthy. Confirm no root `apps` ApplicationSet or workload Applications
   exist. Stop here; managed-cluster import is a separate task.

Do not store kubeconfigs, passwords, or tokens in this repository. The
onboarding operator needs separate kubeconfigs for the other clusters; keep
them outside Git with restrictive file permissions.
