# vLLM runtime (disabled by default)

This component deploys a **CPU-only** vLLM runtime for small-model testing on Kubernetes.

Important notes:
- The default runtime for this repository is `RUNTIME=none`. Start with remote Gemini first.
- The official prebuilt CPU image is convenient, but it may fail on x86 hosts without the required AVX-512 instruction set. If that happens on your AMD Ryzen machine, build a custom CPU image from source and override the image field in `deployment.yaml`.
- The service is intentionally named `vllm-openai` instead of `vllm` to avoid Kubernetes-generated service environment variables colliding with vLLM's `VLLM_*` environment variables.
- Use only a small model first.

## Offline / pre-import option B for k3s

On a machine that has Docker or Podman and internet access:

```bash
docker pull public.ecr.aws/q9t5s3a7/vllm-cpu-release-repo:latest
docker save public.ecr.aws/q9t5s3a7/vllm-cpu-release-repo:latest -o /tmp/vllm-cpu-release-repo-latest.tar
```

Then copy that tarball into every k3s node image import directory:

```bash
make preimport-vllm-image-tarball TOPOLOGY=local VLLM_IMAGE_TARBALL=/tmp/vllm-cpu-release-repo-latest.tar
```

K3s will load tarballs placed under `/var/lib/rancher/k3s/agent/images/` into containerd.
