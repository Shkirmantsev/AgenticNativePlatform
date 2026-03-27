#!/usr/bin/env python3
"""Run a deterministic A2A delegation smoke test against a kagent-exposed agent.

The script fetches the agent card, resolves the runnable A2A URL, sends a
JSON-RPC `message/send` request, and polls `tasks/get` when the initial response
returns a task that is still running.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import uuid
from pathlib import Path
from typing import Any, Iterable, List, Tuple
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


TERMINAL_STATES = {"completed", "failed", "canceled", "cancelled", "input-required", "rejected"}
DEFAULT_HEADERS = {"Accept": "application/json", "Content-Type": "application/json"}


def load_json_file(path: Path) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise SystemExit(f"Scenario file not found: {path}") from exc
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Scenario file is not valid JSON: {path}: {exc}") from exc


def http_get_json(url: str) -> dict[str, Any]:
    request = Request(url, headers={"Accept": "application/json"}, method="GET")
    try:
        with urlopen(request, timeout=30) as response:
            charset = response.headers.get_content_charset() or "utf-8"
            return json.loads(response.read().decode(charset))
    except HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(f"GET {url} failed with HTTP {exc.code}: {body}") from exc
    except URLError as exc:
        raise SystemExit(f"GET {url} failed: {exc}") from exc


def http_post_json(url: str, payload: dict[str, Any]) -> dict[str, Any]:
    body = json.dumps(payload).encode("utf-8")
    request = Request(url, data=body, headers=DEFAULT_HEADERS, method="POST")
    try:
        with urlopen(request, timeout=60) as response:
            charset = response.headers.get_content_charset() or "utf-8"
            return json.loads(response.read().decode(charset))
    except HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(f"POST {url} failed with HTTP {exc.code}: {body}") from exc
    except URLError as exc:
        raise SystemExit(f"POST {url} failed: {exc}") from exc


def iter_text_parts(node: Any) -> Iterable[str]:
    if isinstance(node, dict):
        kind = node.get("kind")
        if kind == "text" and isinstance(node.get("text"), str):
            yield node["text"]
        for value in node.values():
            yield from iter_text_parts(value)
    elif isinstance(node, list):
        for item in node:
            yield from iter_text_parts(item)


def extract_texts(node: Any) -> List[str]:
    texts: list[str] = []
    seen: set[str] = set()
    for text in iter_text_parts(node):
        normalized = text.strip()
        if normalized and normalized not in seen:
            texts.append(normalized)
            seen.add(normalized)
    return texts


def pick_status_state(result: dict[str, Any]) -> str | None:
    status = result.get("status")
    if isinstance(status, dict):
        state = status.get("state")
        if isinstance(state, str) and state.strip():
            return state.strip()
    return None


def pick_task_id(result: dict[str, Any]) -> str | None:
    for key in ("id", "taskId"):
        value = result.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return None


def require_strings(full_text: str, expected: list[str], expected_any: list[str], forbidden: list[str]) -> Tuple[bool, list[str]]:
    failures: list[str] = []
    haystack = full_text.lower()

    for item in expected:
        if item.lower() not in haystack:
            failures.append(f"Missing expected text fragment: {item}")

    if expected_any and not any(item.lower() in haystack for item in expected_any):
        failures.append(
            "None of the expected-any text fragments were found: " + ", ".join(expected_any)
        )

    for item in forbidden:
        if item.lower() in haystack:
            failures.append(f"Forbidden text fragment was found: {item}")

    return not failures, failures


def pretty_json(data: Any) -> str:
    return json.dumps(data, indent=2, ensure_ascii=False, sort_keys=True)


def resolve_agent_urls(args: argparse.Namespace) -> Tuple[str, str]:
    if args.card_url:
        card_url = args.card_url.rstrip("/")
        card = http_get_json(card_url)
        agent_url = card.get("url")
        if not isinstance(agent_url, str) or not agent_url.strip():
            raise SystemExit(f"Agent card {card_url} does not contain a usable 'url' field")
        return card_url, agent_url.rstrip("/")

    if args.agent_url:
        agent_url = args.agent_url.rstrip("/")
        return f"{agent_url}/.well-known/agent.json", agent_url

    raise SystemExit("Either --card-url or --agent-url must be provided")


def main() -> int:
    parser = argparse.ArgumentParser(description="Run an A2A task/delegation smoke test")
    parser.add_argument(
        "--scenario-file",
        default="scripts/a2a-scenarios/team-lead-finnhub-delegation.json",
        help="Path to the JSON scenario definition",
    )
    parser.add_argument("--card-url", help="Exact agent card URL to fetch first")
    parser.add_argument("--agent-url", help="Exact A2A agent base URL")
    parser.add_argument("--timeout-seconds", type=int, default=90, help="Overall polling timeout")
    parser.add_argument("--poll-interval-seconds", type=float, default=2.0, help="tasks/get polling interval")
    parser.add_argument("--print-raw", action="store_true", help="Print the final raw JSON response")
    args = parser.parse_args()

    scenario_path = Path(args.scenario_file)
    scenario = load_json_file(scenario_path)

    card_url, agent_url = resolve_agent_urls(args)
    if args.card_url:
        card = http_get_json(card_url)
    else:
        card = http_get_json(card_url)

    request_id = f"req-{uuid.uuid4()}"
    message_id = str(uuid.uuid4())
    payload = {
        "jsonrpc": "2.0",
        "id": request_id,
        "method": "message/send",
        "params": {
            "message": {
                "role": "user",
                "parts": [
                    {
                        "kind": "text",
                        "text": scenario["message"],
                    }
                ],
                "messageId": message_id,
            },
            "metadata": {
                "testScenario": scenario.get("name", scenario_path.stem),
                "expectedDelegation": scenario.get("expected_delegation_to"),
                "bypassSampling": bool(scenario.get("bypass_sampling", False)),
                "bypassElicitation": bool(scenario.get("bypass_elicitation", False)),
            },
        },
    }

    print(f"[a2a] card    : {card_url}")
    print(f"[a2a] agent   : {agent_url}")
    print(f"[a2a] name    : {card.get('name', '<unknown>')}")
    print(f"[a2a] scenario: {scenario.get('name', scenario_path.stem)}")
    print(f"[a2a] request : {request_id}")

    response = http_post_json(agent_url, payload)
    if "error" in response:
        print(pretty_json(response), file=sys.stderr)
        raise SystemExit("A2A server returned a JSON-RPC error on message/send")

    result = response.get("result")
    if not isinstance(result, dict):
        raise SystemExit(f"Unexpected A2A response shape: {pretty_json(response)}")

    task_id = pick_task_id(result)
    state = pick_status_state(result)
    deadline = time.time() + args.timeout_seconds

    while task_id and state and state not in TERMINAL_STATES:
        if time.time() > deadline:
            raise SystemExit(f"Timed out waiting for task {task_id} to reach a terminal state; last state={state}")
        time.sleep(args.poll_interval_seconds)
        poll_payload = {
            "jsonrpc": "2.0",
            "id": f"poll-{uuid.uuid4()}",
            "method": "tasks/get",
            "params": {"id": task_id},
        }
        poll_response = http_post_json(agent_url, poll_payload)
        if "error" in poll_response:
            print("[a2a] warning: tasks/get returned an error; falling back to the original response", file=sys.stderr)
            print(pretty_json(poll_response), file=sys.stderr)
            break
        polled = poll_response.get("result")
        if isinstance(polled, dict):
            result = polled
            state = pick_status_state(result)
            task_id = pick_task_id(result) or task_id
        else:
            break

    texts = extract_texts(result)
    full_text = "\n".join(texts)

    print(f"[a2a] final state : {pick_status_state(result) or result.get('kind', '<unknown>')}")
    if task_id:
        print(f"[a2a] task id     : {task_id}")
    print("[a2a] extracted text:")
    if full_text:
        print(full_text)
    else:
        print("<no text parts found>")

    ok, failures = require_strings(
        full_text=full_text,
        expected=list(scenario.get("expected_contains", [])),
        expected_any=list(scenario.get("expected_any_contains", [])),
        forbidden=list(scenario.get("forbidden_contains", [])),
    )

    terminal_state = pick_status_state(result)
    if terminal_state in {"failed", "rejected", "canceled", "cancelled"}:
        failures.append(f"Task reached terminal failure state: {terminal_state}")
    if terminal_state == "input-required":
        failures.append(
            "Task ended in input-required. The smoke test request should stay deterministic enough to avoid elicitation."
        )

    if args.print_raw:
        print("[a2a] raw final response:")
        print(pretty_json(result))

    if failures:
        print("[a2a] RESULT: FAILED", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1

    print("[a2a] RESULT: PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
