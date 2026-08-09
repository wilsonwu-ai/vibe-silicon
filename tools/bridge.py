#!/usr/bin/env python3
"""bridge.py -- carry tokens from the DE10-Lite to the public page.

    board --JTAG--> nios2-terminal --stdout--> bridge.py --HTTPS POST--> Worker

Runs on Justin's PC, next to the board. Standard library only: no pip, no venv,
nothing to install on a machine that is already busy fighting Quartus.

Deliberately outbound-only. It opens no port and needs no tunnel, so venue wifi
has nothing to block and nothing to misconfigure.

    python bridge.py --token vs_xxxxx
    python bridge.py --token vs_xxxxx --replay expected_output.txt   # no board
    python bridge.py --token vs_xxxxx --cmd "nios2-terminal -i 0"

Ctrl-C to stop.
"""

import argparse
import json
import queue
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request

DEFAULT_URL = "https://vibe-silicon.wilson-af8.workers.dev"
FLUSH_EVERY = 0.25          # seconds; batches chars so we are not POSTing per byte
CONNECT_TIMEOUT = 15


def post(url: str, token: str, text: str, path: str = "/ingest", src: str = "board") -> bool:
    sep = "&" if "?" in path else "?"
    req = urllib.request.Request(
        url.rstrip("/") + path + (sep + "src=" + src if path == "/ingest" else ""),
        data=text.encode("utf-8"),
        headers={
            "Authorization": "Bearer " + token,
            "Content-Type": "text/plain; charset=utf-8",
            # Cloudflare's bot protection rejects urllib's default UA with a
            # 403 / error 1010. Any ordinary UA passes. Found the hard way.
            "User-Agent": "vibe-silicon-bridge/1.0",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=CONNECT_TIMEOUT) as r:
            return r.status == 200
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")[:120]
        print(f"\n[bridge] HTTP {e.code}: {body}", file=sys.stderr)
        if e.code == 401:
            print("[bridge] the token is wrong -- ask Wilson for the current one", file=sys.stderr)
        return False
    except Exception as e:
        print(f"\n[bridge] {type(e).__name__}: {e}", file=sys.stderr)
        return False


def reader_thread(proc, q: "queue.Queue[str]") -> None:
    """Read the child's stdout one byte at a time.

    Byte-at-a-time matters: nios2-terminal emits tokens as the model produces
    them, and any line buffering here would hold a whole sentence back and make
    the page look frozen while the board is actually working.
    """
    while True:
        b = proc.stdout.read(1)
        if not b:
            break
        q.put(b.decode("utf-8", "replace"))
    q.put(None)  # sentinel


def replay_thread(path: str, q: "queue.Queue[str]", cps: float) -> None:
    text = open(path, encoding="utf-8").read()
    delay = 1.0 / max(cps, 1.0)
    for ch in text:
        q.put(ch)
        time.sleep(delay)
    q.put(None)


def main() -> int:
    ap = argparse.ArgumentParser(description="Forward board output to the public page.")
    ap.add_argument("--url", default=DEFAULT_URL)
    ap.add_argument("--token", required=True, help="ingest token (ask Wilson)")
    ap.add_argument("--cmd", default="nios2-terminal", help="command that prints the board's output")
    ap.add_argument("--replay", help="read from this file instead of the board (for testing)")
    ap.add_argument("--cps", type=float, default=12.0, help="chars/sec when replaying")
    ap.add_argument("--reset", action="store_true", help="clear the page's buffer before starting")
    args = ap.parse_args()

    if args.reset:
        print("[bridge] clearing the page buffer ...")
        post(args.url, args.token, "", "/reset")

    # Declared to the page so it can label itself honestly.
    src_mode = "replay" if args.replay else "board"

    q: "queue.Queue[str]" = queue.Queue()
    proc = None

    if args.replay:
        print(f"[bridge] REPLAY mode from {args.replay} at {args.cps:.0f} chars/sec")
        threading.Thread(target=replay_thread, args=(args.replay, q, args.cps), daemon=True).start()
    else:
        print(f"[bridge] launching: {args.cmd}")
        try:
            proc = subprocess.Popen(
                args.cmd, shell=True, stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT, bufsize=0,
            )
        except Exception as e:
            print(f"[bridge] could not start {args.cmd!r}: {e}", file=sys.stderr)
            return 1
        threading.Thread(target=reader_thread, args=(proc, q), daemon=True).start()

    print(f"[bridge] posting to {args.url}/ingest")
    print("[bridge] Ctrl-C to stop\n")

    buf: list[str] = []
    last = time.time()
    total = 0
    failures = 0
    done = False

    try:
        while not done:
            try:
                item = q.get(timeout=FLUSH_EVERY)
                if item is None:
                    done = True
                else:
                    buf.append(item)
                    sys.stdout.write(item)     # mirror locally so Justin sees it too
                    sys.stdout.flush()
            except queue.Empty:
                pass

            now = time.time()
            if buf and (now - last >= FLUSH_EVERY or done):
                chunk = "".join(buf)
                buf.clear()
                last = now
                if post(args.url, args.token, chunk, src=src_mode):
                    total += len(chunk)
                    failures = 0
                else:
                    failures += 1
                    # Never lose the demo to a flaky network: put it back and
                    # let the next flush try again.
                    buf.insert(0, chunk)
                    if failures >= 5:
                        print(f"\n[bridge] {failures} consecutive failures, still retrying ...",
                              file=sys.stderr)
                        time.sleep(2)
    except KeyboardInterrupt:
        print("\n[bridge] stopping")
    finally:
        if buf:
            post(args.url, args.token, "".join(buf), src=src_mode)
        if proc and proc.poll() is None:
            proc.terminate()

    print(f"\n[bridge] forwarded {total} characters")
    return 0


if __name__ == "__main__":
    sys.exit(main())
