#!/usr/bin/env python3
"""
vibe-silicon dual-language RTL benchmark harness.

Asks each model to write a module from a spec, then grades it against a
HAND-WRITTEN testbench the model never sees. Four gates, in order:

    1. generated  - did we get anything that looks like RTL
    2. lints      - the toolchain parses it standalone
    3. elaborates - the toolchain links it against our testbench
    4. passes     - the simulation prints ALL TESTS PASSED

Gate 4 is the interesting one. RTL that compiles and computes the wrong answer
is the characteristic LLM failure, and only a testbench catches it.

Two languages are graded through the same four gates so the columns are
comparable (see CONTRACT.md):

    stage        verilog                          vhdl
    lint         iverilog -g2001 -t null dut.v    ghdl -a --std=08 dut.vhdl
    elaborate    iverilog -g2001 -o sim dut.v tb  ghdl -a tb.vhdl; ghdl -e tb
    simulate     vvp sim                          ghdl -r --std=08 tb

Everything is appended to results/results.jsonl. Re-runs never overwrite.

    pip install anthropic
    brew install icarus-verilog ghdl
    python3 harness.py --trials 3 --lang both
    python3 harness.py --report
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

import anthropic

ROOT = Path(__file__).resolve().parent
TASKS_DIR = ROOT / "tasks"
BUILD_DIR = ROOT / "build"
RESULTS = ROOT / "results" / "results.jsonl"

# NOTE ON THE SYSTEM PROMPTS BELOW -- do not "improve" the opening sentence.
# "You write synthesizable Verilog-2001 for FPGA targets." trips claude-opus-5's
# refusal classifier: empty content, 3 output tokens, stop_reason="refusal",
# reproducibly, on a benign MAC-unit spec. Dropping the trailing period or
# rewording to "Respond with ... suitable for an FPGA target." clears it. This
# was measured, not guessed -- see docs/LOG.md. Both prompts must stay the same
# length and structure or the benchmark measures the prompt, not the models.
#
# Per-model request shaping. Opus 5 and Sonnet 5 take adaptive thinking plus an
# effort level; Haiku 4.5 predates both and rejects them.
MODELS = {
    "claude-opus-5": {"thinking": True, "effort": "high"},
    "claude-sonnet-5": {"thinking": True, "effort": "high"},
    "claude-haiku-4-5": {"thinking": False, "effort": None},
}

# ---------------------------------------------------------------------------
# System prompts.
#
# These two are the load-bearing fairness artifact. They are structurally
# identical: same opening line, same "Output requirements:" header, same four
# bullets in the same order making the same four demands, same FPGA target,
# same closing sentence. The only differences are the ones the language forces
# (module/entity, the names of the non-synthesizable constructs being banned).
# If one prompt were more helpful than the other, this benchmark would be
# measuring our prompt writing rather than the models. Do not edit one without
# making the mirrored edit to the other.
# ---------------------------------------------------------------------------

SYSTEM = """Respond with synthesizable Verilog-2001 suitable for an FPGA target.

Output requirements:
- Emit exactly one Verilog module and nothing else. No prose, no explanation.
- The module name, port names, port directions, and bit widths must match the
  spec exactly. A testbench you cannot see instantiates it by name and by port.
- Synthesizable constructs only. No delays, no initial blocks, no $display,
  no system tasks.
- Signed arithmetic must be explicitly signed."""

SYSTEM_VHDL = """Respond with synthesizable VHDL-2008 suitable for an FPGA target.

Output requirements:
- Emit exactly one VHDL entity and architecture and nothing else. No prose,
  no explanation.
- The entity name, port names, port directions, and bit widths must match the
  spec exactly. A testbench you cannot see instantiates it by name and by port.
- Synthesizable constructs only. No delays, no initial values, no report
  statements, no textio.
- Signed arithmetic must be explicitly signed."""


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


# A design unit starts at a line-initial `library`, `use`, `entity` or
# `architecture`. Anchoring to line start matters: prose like "here is the
# entity" contains the keyword mid-line and must not be treated as the start.
_VHDL_START = re.compile(
    r"(?im)^[ \t]*(?:library|use|entity|architecture|context|package)\b"
)

# VHDL has no `endmodule`. The architecture closes with some flavour of
# `end ...;` -- `end;`, `end rtl;`, `end architecture;`, `end architecture rtl;`
# -- but so do `end process;`, `end if;` and `end loop;`. The LAST line-initial
# `end ...;` in a well-formed design unit is always the architecture's, so take
# that one. Kept on a single line ([^;\n]) so a stray `end` with no semicolon
# cannot swallow the rest of the file.
_VHDL_END = re.compile(r"(?im)^[ \t]*end\b[^;\n]*;")


def extract_vhdl(text: str) -> str:
    """Pull the entity + architecture out of the response, fenced or bare."""
    fenced = re.findall(r"```(?:vhdl|vhd|VHDL)?\s*\n(.*?)```", text, re.S)
    body = fenced[0] if fenced else text
    # Trim anything before the first library/entity and after the last `end ...;`.
    head = _VHDL_START.search(body)
    tails = list(_VHDL_END.finditer(body))
    if not head or not tails or tails[-1].end() <= head.start():
        return body.strip()
    return body[head.start() : tails[-1].end()].strip()


def generate(client, model: str, spec: str, system: str) -> tuple[str, dict]:
    cfg = MODELS[model]
    kwargs = {
        "model": model,
        "max_tokens": 16000,
        "system": system,
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
    return text, meta


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
    """Verilog: run the three tool gates. Each stage only runs if the prior one
    passed."""
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


def grade_vhdl(workdir: Path, tb: Path) -> dict:
    """VHDL: the same three gates through ghdl.

    Runs in a private temp directory, which is not optional. `ghdl -a` writes
    its work library (work-obj08.cf) plus per-unit object files into the CWD,
    and a library left behind by an earlier attempt will happily satisfy a
    later one -- a dut.vhdl that fails to analyse would still elaborate against
    the previous trial's design unit and could score a pass it did not earn.
    A fresh directory per attempt makes that impossible.
    """
    out = {"lints": False, "elaborates": False, "passes": False, "log": ""}

    with tempfile.TemporaryDirectory(prefix="vibe-ghdl-") as td:
        wd = Path(td)
        shutil.copyfile(workdir / "dut.vhdl", wd / "dut.vhdl")
        shutil.copyfile(tb, wd / "tb.vhdl")

        rc, log = run(["ghdl", "-a", "--std=08", "dut.vhdl"], wd)
        out["lints"] = rc == 0
        if not out["lints"]:
            out["log"] = f"[lint] {log}"[:2000]
            return out

        # Elaborate = analyse the testbench, then bind it to the DUT. Wrong
        # entity name, wrong port names, wrong port types all surface here,
        # the same place iverilog surfaces them.
        rc, log = run(["ghdl", "-a", "--std=08", "tb.vhdl"], wd)
        if rc == 0:
            rc, elab_log = run(["ghdl", "-e", "--std=08", "tb"], wd)
            log = "\n".join(x for x in (log, elab_log) if x)
        out["elaborates"] = rc == 0
        if not out["elaborates"]:
            out["log"] = f"[elab] {log}"[:2000]
            return out

        rc, log = run(["ghdl", "-r", "--std=08", "tb"], wd)
        out["passes"] = "ALL TESTS PASSED" in log
        out["log"] = f"[sim] {log}"[:2000]
        return out


# Everything language-specific lives here so the driver loop stays symmetric.
LANGS = {
    "verilog": {
        "spec": "spec.md",
        "tb": "tb.v",
        "dut": "dut.v",
        "system": SYSTEM,
        "extract": extract_verilog,
        "grade": grade,
    },
    "vhdl": {
        "spec": "spec_vhdl.md",
        "tb": "tb.vhdl",
        "dut": "dut.vhdl",
        "system": SYSTEM_VHDL,
        "extract": extract_vhdl,
        "grade": grade_vhdl,
    },
}


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------

# Ordered earliest-to-latest. A row lands in exactly one bucket: the stage the
# attempt died at, or "pass".
STAGES = ("no-code", "lint", "elaborate", "simulate", "pass")
STAGE_ABBR = {"no-code": "nocode", "lint": "lint", "elaborate": "elab",
              "simulate": "sim", "pass": "pass"}


def stage_of(row: dict) -> str:
    """Where in the pipeline this attempt stopped."""
    if row.get("passes"):
        return "pass"
    if row.get("elaborates"):
        return "simulate"  # built and ran, produced the wrong answer
    if row.get("lints"):
        return "elaborate"  # parsed standalone, would not bind to the testbench
    if row.get("generated", True):
        return "lint"  # code came back, the tool would not parse it
    return "no-code"


def lang_of(row: dict) -> str:
    """Rows written before --lang existed were all Verilog."""
    return row.get("lang", "verilog")


def load_rows(path: Path) -> tuple[list, int]:
    """Read results.jsonl. Missing, empty and partially-corrupt files are all
    normal -- a sweep killed mid-write leaves a truncated last line."""
    rows, bad = [], 0
    if not path.exists():
        return rows, bad
    with path.open() as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                bad += 1
                continue
            if isinstance(obj, dict):
                rows.append(obj)
            else:
                bad += 1
    return rows, bad


def _rate(ok: int, n: int) -> str:
    return f"{100.0 * ok / n:5.1f}%" if n else "    --"


def report(path: Path) -> None:
    rows, bad = load_rows(path)

    if not rows:
        where = path if path.exists() else f"{path} (does not exist)"
        print(f"no results yet: {where}")
        if bad:
            print(f"({bad} unparseable line(s) skipped)")
        print("\nrun a sweep first, e.g.:")
        print("    python3 harness.py --trials 3 --lang both")
        return

    langs = sorted({lang_of(r) for r in rows})
    models = sorted({r.get("model", "?") for r in rows})
    tasks = sorted({r.get("task", "?") for r in rows})
    mw = max([len(m) for m in models] + [5])
    tw = max([len(t) for t in tasks] + [4])

    def sel(**kw):
        out = rows
        if "lang" in kw:
            out = [r for r in out if lang_of(r) == kw["lang"]]
        if "model" in kw:
            out = [r for r in out if r.get("model") == kw["model"]]
        if "task" in kw:
            out = [r for r in out if r.get("task") == kw["task"]]
        return out

    def passes(rs):
        return sum(1 for r in rs if r.get("passes"))

    print(f"\n{len(rows)} attempts from {path}")
    if bad:
        print(f"({bad} unparseable line(s) skipped)")

    # -- 1. pass rate by language x model ----------------------------------
    print("\n== pass rate by language x model ==")
    print(f"{'lang':<8} {'model':<{mw}} {'n':>4} {'pass':>5} {'rate':>7}")
    print("-" * (8 + mw + 19))
    for lang in langs:
        for model in models:
            rs = sel(lang=lang, model=model)
            if not rs:
                continue
            ok = passes(rs)
            print(f"{lang:<8} {model:<{mw}} {len(rs):>4} {ok:>5} {_rate(ok, len(rs)):>7}")

    # -- 2. where in the pipeline it stopped -------------------------------
    print("\n== where it stopped (count of attempts) ==")
    hdr = f"{'lang':<8} {'model':<{mw}} {'n':>4}   " + " ".join(
        f"{STAGE_ABBR[s]:>6}" for s in STAGES
    )
    print(hdr)
    print("-" * len(hdr))
    for lang in langs:
        for model in models:
            rs = sel(lang=lang, model=model)
            if not rs:
                continue
            counts = {s: 0 for s in STAGES}
            for r in rs:
                counts[stage_of(r)] += 1
            cells = " ".join(f"{counts[s]:>6}" for s in STAGES)
            print(f"{lang:<8} {model:<{mw}} {len(rs):>4}   {cells}")

    print("\n  nocode = model returned nothing extractable")
    print("  lint   = the compiler would not parse it standalone")
    print("  elab   = parsed, but would not bind to the testbench")
    print("  sim    = built and ran, computed the wrong answer")

    # API refusals are not evidence about a language. They land in `nocode`
    # and enter the pass-rate denominator, so if they fall unevenly across
    # languages they bias the headline. Surface them rather than bury them.
    refused = [r for r in rows if r.get("refused")]
    if refused:
        print(f"\n  !! {len(refused)} of {len(rows)} attempts were API refusals, "
              "counted above as nocode:")
        for lang in langs:
            for model in models:
                n = len([r for r in refused
                         if lang_of(r) == lang and r.get("model") == model])
                if n:
                    tot = len(sel(lang=lang, model=model))
                    print(f"       {lang:<8} {model:<{mw}} {n}/{tot}")
        print("     A refusal measures the API, not the language. If these are")
        print("     lopsided across languages, exclude them before quoting a delta.")

    # -- 3. per-task comparison --------------------------------------------
    print("\n== pass rate by task x language ==")
    hdr = f"{'task':<{tw}}  " + "  ".join(f"{lang:^14}" for lang in langs)
    if len(langs) == 2:
        hdr += f"  {'delta':>9}"
    print(hdr)
    print("-" * len(hdr))
    for task in tasks:
        cells, rates = [], []
        for lang in langs:
            rs = sel(lang=lang, task=task)
            ok, n = passes(rs), len(rs)
            cells.append(f"{f'{ok}/{n}':>6}{_rate(ok, n):>8}")
            rates.append(100.0 * ok / n if n else None)
        line = f"{task:<{tw}}  " + "  ".join(cells)
        if len(langs) == 2:
            if rates[0] is not None and rates[1] is not None:
                line += f"  {rates[1] - rates[0]:>+7.1f}pt"
            else:
                line += f"  {'--':>9}"
        print(line)

    # -- 4. headline --------------------------------------------------------
    print("\n== headline ==")
    totals = {}
    for lang in langs:
        rs = sel(lang=lang)
        ok, n = passes(rs), len(rs)
        totals[lang] = (ok, n)
        print(f"{lang:<8} {f'{ok}/{n}':>8} {_rate(ok, n):>8}")

    if len(langs) == 2 and all(totals[l][1] for l in langs):
        a, b = langs  # alphabetical: verilog then vhdl
        ra = 100.0 * totals[a][0] / totals[a][1]
        rb = 100.0 * totals[b][0] / totals[b][1]
        print(f"\n{b} minus {a}: {rb - ra:+.1f} percentage points")
        if ra > 0:
            print(f"{b} passes {rb / ra:.2f}x as often as {a}")
        # Failing earlier in the pipeline is itself a finding.
        for lang in langs:
            rs = sel(lang=lang)
            early = sum(1 for r in rs if stage_of(r) in ("no-code", "lint", "elaborate"))
            late = sum(1 for r in rs if stage_of(r) == "simulate")
            print(
                f"{lang:<8} failures: {early} before simulation, "
                f"{late} wrong-answer at simulation"
            )
    elif len(langs) == 1:
        print(f"\nonly {langs[0]} rows present; run --lang both for the comparison")


# ---------------------------------------------------------------------------
# Sweep
# ---------------------------------------------------------------------------


def main():
    ap = argparse.ArgumentParser(
        description="Grade LLM-written Verilog and VHDL against hidden testbenches."
    )
    ap.add_argument("--trials", type=int, default=3, help="attempts per task/model/lang")
    ap.add_argument("--models", nargs="*", default=list(MODELS))
    ap.add_argument("--tasks", nargs="*", default=None, help="task names, default all")
    ap.add_argument(
        "--lang",
        choices=["verilog", "vhdl", "both"],
        default="both",
        help="language(s) to grade (default: both)",
    )
    ap.add_argument(
        "--results", type=Path, default=RESULTS, help="results.jsonl path"
    )
    ap.add_argument(
        "--report",
        action="store_true",
        help="read results.jsonl and print the comparison tables; no model calls",
    )
    args = ap.parse_args()

    if args.report:
        report(args.results)
        return

    for m in args.models:
        if m not in MODELS:
            sys.exit(f"unknown model {m!r}; known: {', '.join(MODELS)}")

    langs = ["verilog", "vhdl"] if args.lang == "both" else [args.lang]

    if not os.environ.get("ANTHROPIC_API_KEY"):
        print("note: ANTHROPIC_API_KEY unset; relying on `ant auth login` profile\n")

    # A task counts for a language only if that language's spec and testbench
    # both exist, so a half-authored task cannot quietly skew one column.
    tasks = sorted(d for d in TASKS_DIR.iterdir() if (d / "spec.md").exists())
    if args.tasks:
        tasks = [t for t in tasks if t.name in args.tasks]
    if not tasks:
        sys.exit("no tasks found")

    args.results.parent.mkdir(parents=True, exist_ok=True)
    client = anthropic.Anthropic()
    tally = {}

    for task in tasks:
        for lang in langs:
            cfg = LANGS[lang]
            spec_path = task / cfg["spec"]
            tb = task / cfg["tb"]
            if not spec_path.exists() or not tb.exists():
                print(f"  {task.name}/{lang} ... skipped (no {cfg['spec']} or {cfg['tb']})")
                continue
            spec = spec_path.read_text()

            for model in args.models:
                for trial in range(args.trials):
                    tag = f"{task.name}/{lang}/{model}/t{trial}"
                    print(f"  {tag} ... ", end="", flush=True)

                    workdir = BUILD_DIR / task.name / model / f"t{trial}"
                    workdir.mkdir(parents=True, exist_ok=True)

                    try:
                        text, meta = generate(client, model, spec, cfg["system"])
                    except anthropic.APIError as e:
                        print(f"API error: {e}")
                        continue

                    code = cfg["extract"](text) if text else ""
                    (workdir / cfg["dut"]).write_text(code)
                    res = (
                        cfg["grade"](workdir, tb)
                        if code
                        else {
                            "lints": False,
                            "elaborates": False,
                            "passes": False,
                            "log": "no code returned",
                        }
                    )

                    row = {
                        "ts": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                        "lang": lang,
                        "task": task.name,
                        "model": model,
                        "trial": trial,
                        "generated": bool(code),
                        **res,
                        **meta,
                        "code": code,
                    }
                    with args.results.open("a") as f:
                        f.write(json.dumps(row) + "\n")

                    key = (task.name, lang, model)
                    tally.setdefault(key, [0, 0])
                    tally[key][1] += 1
                    if res["passes"]:
                        tally[key][0] += 1

                    verdict = (
                        "PASS" if res["passes"]
                        else "wrong-answer" if res["elaborates"]
                        else "no-elab" if res["lints"]
                        else "no-lint"
                    )
                    print(f"{verdict}  ({meta.get('seconds', '?')}s)")

    print(f"\n{'task':<16} {'lang':<8} {'model':<20} {'pass rate':>10}")
    print("-" * 58)
    for (t, lg, m), (ok, n) in sorted(tally.items()):
        print(f"{t:<16} {lg:<8} {m:<20} {ok}/{n:>8}")
    print(f"\nappended to {args.results}")
    print(f"compare with: python3 {Path(__file__).name} --report")


if __name__ == "__main__":
    main()
