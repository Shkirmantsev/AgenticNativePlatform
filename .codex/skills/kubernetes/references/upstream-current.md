# Upstream Current References

## Verified On 2026-03-20

- Kubernetes supported docs versions: https://kubernetes.io/docs/home/supported-doc-versions/
  - current docs tree advertises `v1.35`
  - still-linked recent versions include `v1.34`, `v1.33`, `v1.32`, and `v1.31`
- AgentGateway on Kubernetes docs: https://agentgateway.dev/docs/kubernetes/latest/

## Practical reminders

- When a Deployment is driven to `replicas: 0`, an attached HPA reports `ScalingDisabled` until another controller or operator raises replicas again. Do not assume the HPA will recover that target on its own.
- For Kubernetes-native gateway debugging, inspect the route status, referenced backends, backing Services and EndpointSlices, and the controller pod logs before changing manifests.
