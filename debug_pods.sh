#!/bin/bash
export KUBECONFIG=$(pwd)/.kube/generated/current.yaml

echo "=== TEI Embeddings Pod Status ==="
kubectl get pods -n ai-models

echo -e "\n=== Kagent Controller Pod Status ==="
kubectl get pods -n kagent

echo -e "\n=== Kagent Controller Pod Events ==="
kubectl describe pod kagent-kagent-controller-85d596b9dd-nmmx9 -n kagent

echo -e "\n=== Kagent Controller Pod Logs ==="
kubectl logs kagent-kagent-controller-85d596b9dd-nmmx9 -n kagent

echo -e "\n=== New Kagent Controller Pod Events ==="
kubectl describe pod kagent-kagent-controller-74dc44cb94-9c8v8 -n kagent

echo -e "\n=== New Kagent Controller Pod Logs ==="
kubectl logs kagent-kagent-controller-74dc44cb94-9c8v8 -n kagent