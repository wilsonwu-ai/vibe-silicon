# The public page

**Live: https://vibe-silicon.wilson-af8.workers.dev**

Sundai's rule is that a demo has to be on the internet, not on localhost. This is
that. It is also the fallback: it plays verified output when the board is quiet,
so a judge who opens the link at any point sees something real.

## Shape

```
board ──JTAG──► nios2-terminal ──stdout──► bridge.py ──HTTPS POST──► Worker ──SSE──► browsers
                        (Justin's PC)                              (Cloudflare)
```

**Outbound only.** Nothing listens on the venue network — no inbound port, no
tunnel, nothing for conference wifi to block or for a sleeping laptop to break.
The page keeps working if either of our machines walks out of the building.

## For Justin

Get the ingest token from Wilson (Discord DM, not in this repo).

**Test it now, with no board:**

```bash
python bridge.py --token <TOKEN> --replay expected_output.txt --cps 12
```

Open the URL and you should see words appear. The page will label this
**"streaming · recorded run"**, because it is.

**When the board is printing tokens:**

```bash
python bridge.py --token <TOKEN> --reset
```

That spawns `nios2-terminal`, forwards everything it prints, and mirrors it in
your own console so you can watch it too. `--reset` clears whatever was on the
page first. The label switches to **"live from the board"**.

If `nios2-terminal` needs arguments on your machine:

```bash
python bridge.py --token <TOKEN> --cmd "nios2-terminal -i 0"
```

Requires only the Python standard library. Nothing to install.

## Honesty, enforced in code

The page cannot tell where ingested bytes came from, so `bridge.py` declares it:
`--replay` sends `src=replay`, otherwise `src=board`. The page labels itself from
that flag.

This matters because the alternative — a page that says "live from the board"
while playing a recording — is exactly the kind of thing that unravels in Q&A.
The whole project argues for saying precisely what is true, and the demo page
should not be the one place that stops doing it.

## Routes

| route | |
|---|---|
| `GET /` | the page |
| `POST /ingest?src=board\|replay` | bearer auth; raw body or `{"text":...}` |
| `GET /stream` | SSE — seeds with everything so far, then live |
| `GET /tail?after=N` | polling fallback if SSE is blocked |
| `POST /reset` | clear the buffer (bearer auth) |
| `GET /healthz` | `{ok, chars, live, src, elapsedMs}` |

`?room=<name>` on any route gives an isolated stream, if we want a scratch one
for testing without disturbing the demo.

## Deploying

```bash
cd web/worker
npx wrangler deploy
npx wrangler secret put INGEST_TOKEN      # never a [vars] entry -- see below
```

Two things that cost time once already:

- `INGEST_TOKEN` must be a **secret**, not a `[vars]` entry. A plaintext var of
  the same name collides with the secret binding (Cloudflare error 10053).
- Secrets take a few seconds to propagate. A 401 immediately after
  `secret put` is usually just that — retry before debugging.

## Known gotcha

Cloudflare's bot protection rejects urllib's default `User-Agent` with a **403,
error 1010**. `bridge.py` sets its own. If you write another client, do the same.
