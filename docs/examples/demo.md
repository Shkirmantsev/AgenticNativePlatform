# Demo notes

The default platform path is now driven from:

- `clusters/<topology>-<env>/`
- `infrastructure/`
- `apps/`

The example `echo-mcp` sample is no longer part of the default active root. Keep it opt-in only.

For lightweight KServe validation, use:

- `infrastructure/controllers/kserve/samples/hf-tiny-inferenceservice.yaml`
