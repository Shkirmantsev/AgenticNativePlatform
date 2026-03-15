# ADR-0003: Routing and gateways

## Status
Accepted

## Context
We need north-south ingress, east-west policy, agent-native routing, and provider abstraction.

## Decision
Use:

- **kgateway** for public ingress based on Gateway API and Envoy
- **agentgateway** for agent-native policy and protocol-aware routing
- **LiteLLM** for provider normalization

## Why not just one gateway?
One gateway would mix public ingress concerns with model-provider abstraction and internal agent traffic governance.
The chosen split keeps each layer smaller and easier to evolve.
