#!/usr/bin/env python3
"""
vibe-silicon Verilog benchmark harness.

Asks each model to write a Verilog module from a spec, then grades it against a
HAND-WRITTEN testbench the model never sees. Four gates, in order:

    1. generated  - did we get anything that looks like Verilog
    2. lints      - iverilog parses it standalone
    3. elaborates - iverilog links it against our testbench
    4. passes     - vvp runs it and the testbench prints ALL TESTS PASSED

Gate 4 is the interesting one. Verilog that compiles and computes the wrong
answer is the characteristic LLM failure, and only a testbench catches it.

Everything is appended to results/results.jsonl. Re-runs never overwrite.

    pip install anthropic
    brew install icarus-verilog
    python3 harness.py --trials 3
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

import anthropic

ROOT = Path(__file__).resolve().parent
TASKS_DIR = ROOT / "tasks"
BUILD_DIR = ROOT / "build"
RESULTS = ROOT / "results" / "results.jsonl"

# Per-model request shaping. Opus 5 and Sonnet 5 take adaptive thinking plus an
# effort level; Haiku 4.5 predates both and rejects them.
MODELS = {
    "claude-opus-5": {"thinking": True, "effort": "high"},
    "claude-sonnet-5": {"thinking": True, "effort": "high"},
    "claude-haiku-4-5": {"thinking": False, "effort": None},
}

SYSTEM = """You write synthesizable Verilog-2001 for FPGA targets.

Output requirements:
- Emit exactly one Verilog module and nothing else. No prose, no explanation.
- The module name, port names, port directions, and bit widths must match the
  spec exactly. A testbench you cannot see instantiates it by name and by port.
- Synthesizable constructs only. No delays, no initial blocks, no $display,
  no system tasks.
- Target: Intel Cyclone V. Signed arithmetic must be explicitly signed."""


def extract_verilog(text: str) -> str:
    """Pull the module out of the response, fenced or bare."""
    fenced = re.findall(r"```(?:verilog|systemverilog|v)?\s*\n(.*?)```", text, re.S)
    body = fenced[0] if fenced else text
    # Trim anything before the first `module` and after the last `endmodule`.
    start = body.find("module")
    end = body.rfind("endmodule")
    if start == -1 or end == -1:
        return body.strip()
    return body[start : end + len("endmodule")].strip()


def generate(client, model: str, spec: str) -> tuple[str, dict]:
    cfg = MODELS[model]
    kwargs = {
        "model": model,
        "max_tokens": 16000,
        "system": SYSTEM,
        "messages": [{"role": "user", "content": spec}],
    }
    if cfg["thinking"]:
        kwargs["thinking"] = {"type": "adaptive"}
    if cfg["effort"]:
        kwargs["output_config"] = {"effort": cfg["effort"]}

    t0 = time.time()
    resp = client.messages.create(**kwargs)
    elapsed = time.time() - t0

    if resp.stop_reason == "refusal":
        return "", {"refused": True, "seconds": elapsed}

    text = "".join(b.text for b in resp.content if b.type == "text")
    meta = {
        "seconds": round(elapsed, 2),
        "stop_reason": resp.stop_reason,
        "output_tokens": resp.usage.output_tokens,
        "input_tokens": resp.usage.input_tokens,
    }
    return extract_verilog(text), meta


def run(cmd, cwd, timeout=60):
    try:
        p = subprocess.run(
            cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout
        )
        return p.returncode, (p.stdout + p.stderr).strip()
    except subprocess.TimeoutExpired:
        return 124, "timeout"
    except FileNotFoundError:
        return 127, f"{cmd[0]} not installed"


def grade(workdir: Path, tb: Path) -> dict:
    """Run the three tool gates. Each stage only runs if the prior one passed."""
    out = {"lints": False, "elaborates": False, "passes": False, "log": ""}

    rc, log = run(["iverilog", "-g2001", "-t", "null", "dut.v"], workdir)
    out["lints"] = rc == 0
    if not out["lints"]:
        out["log"] = f"[lint] {log}"[:2000]
        return out

    rc, log = run(["iverilog", "-g2001", "-o", "sim", "dut.v", str(tb)], workdir)
    out["elaborates"] = rc == 0
    if not out["elaborates"]:
        out["log"] = f"[elab] {log}"[:2000]
        return out

    rc, log = run(["vvp", "sim"], workdir)
    out["passes"] = "ALL TESTS PASSED" in log
    out["log"] = f"[sim] {log}"[:2000]
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--trials", type=int, default=3, help="attempts per task/model")
    ap.add_argument("--models", nargs="*", default=list(MODELS))
    ap.add_argument("--tasks", nargs="*", default=None, help="task names, default all")
    args = ap.parse_args()

    for m in args.models:
        if m not in MODELS:
            sys.exit(f"unknown model {m!r}; known: {', '.join(MODELS)}")

    tasks = sorted(d for d in TASKS_DIR.iterdir() if (d / "spec.md").exists())
    if args.tasks:
        tasks = [t for t in tasks if t.name in args.tasks]
    if not tasks:
        sys.exit("no tasks found")

    RESULTS.parent.mkdir(parents=True, exist_ok=True)
    client = anthropic.Anthropic()
    tally = {}

    for task in tasks:
        spec = (task / "spec.md").read_text()
        tb = task / "tb.v"
        for model in args.models:
            for trial in range(args.trials):
                tag = f"{task.name}/{model}/t{trial}"
                print(f"  {tag} ... ", end="", flush=True)

                workdir = BUILD_DIR / task.name / model / f"t{trial}"
                workdir.mkdir(parents=True, exist_ok=True)

                try:
                    code, meta = generate(client, model, spec)
                except anthropic.APIError as e:
                    print(f"API error: {e}")
                    continue

                (workdir / "dut.v").write_text(code)
                res = grade(workdir, tb) if code else {
                    "lints": False, "elaborates": False, "passes": False,
                    "log": "no code returned",
                }

                row = {
                    "task": task.name, "model": model, "trial": trial,
                    "generated": bool(code), **res, **meta,
                }
                with RESULTS.open("a") as f:
                    f.write(json.dumps(row) + "\n")

                key = (task.name, model)
                tally.setdefault(key, [0, 0])
                tally[key][1] += 1
                if res["passes"]:
                    tally[key][0] += 1

                verdict = ("PASS" if res["passes"] else
                           "wrong-answer" if res["elaborates"] else
                           "no-elab" if res["lints"] else "no-lint")
                print(f"{verdict}  ({meta.get('seconds', '?')}s)")

    print(f"\n{'task':<16} {'model':<20} {'pass rate':>10}")
    print("-" * 48)
    for (t, m), (ok, n) in sorted(tally.items()):
        print(f"{t:<16} {m:<20} {ok}/{n:>8}")
    print(f"\nappended to {RESULTS}")


if __name__ == "__main__":
    if not os.environ.get("ANTHROPIC_API_KEY"):
        print("note: ANTHROPIC_API_KEY unset; relying on `ant auth login` profile\n")
    main()
