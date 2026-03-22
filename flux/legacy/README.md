# Legacy Flux Layout

This directory keeps archived Flux roots and monolithic component paths from the pre-profile layout.

Do not use these paths for current bootstrap or new changes.
The authoritative GitOps entrypoint is `flux/generated/clusters/*`, rendered through:

- `flux/components/bundles/*`
- `flux/components/profiles/*`
- generated staged Flux roots such as `platform-bootstrap`, `platform-infrastructure`, and `platform-applications`
