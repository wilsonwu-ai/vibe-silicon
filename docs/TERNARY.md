# Eugene's suggestion: make the multiplier disappear

Eugene (Sundai speaker, author of the RLX Rust inference runtime) suggested a
direction mid-afternoon. It arrived through voice transcription and came out
garbled — *"quantize them turner rate -1 1 and 0 and multiple it by x or gate,
reverse gate and let it through instead of storing, fuse them, cut part of the
model that you don't need."*

Decoded, it is a specific and well-known technique, and it is **the single best
idea anyone offered us today** for this hardware.

**"turner rate" is "ternary."** He is describing [BitNet b1.58](https://arxiv.org/pdf/2504.12285).

---

## ELI5: why multiplication is the enemy

A neural network is mostly one operation, done hundreds of thousands of times per
word:

```
total = total + (weight × input)
```

Multiplication is **expensive in hardware**. Adding two numbers is cheap — a
line of simple logic. Multiplying two numbers needs a dedicated circuit that is
physically much larger.

Our FPGA has exactly **144 dedicated multipliers**. That is a hard ceiling. No
matter how clever we are, we cannot do more than 144 multiplications at once,
because there are only 144 multiplier circuits on the chip.

## The trick

**What if every weight were only ever −1, 0, or +1?**

Then look at what "multiply" becomes:

| weight | `weight × input` | what the hardware does |
|---|---|---|
| **+1** | `input` | let it through — **a wire** |
| **−1** | `−input` | flip the sign — **a negator** |
| **0** | `0` | block it — **a switch that is off** |

**There is no multiplication left.** A wire, a sign flip, and an off-switch. That
is what Eugene meant by *"or gate, reverse gate, and let it through."*

And here is why it matters for *our specific board*:

```
             multipliers      logic elements
  we have:       144              50,000
  ternary needs:   0            ~a handful each
```

**Ternary converts our scarcest resource into our most abundant one.** Instead of
144 parallel operations, you could build *thousands*. On a chip that has no
business running a language model, that is the difference between a curiosity and
a real accelerator.

The literature backs the size of the win: ternary accelerators "forgo
floating-point multipliers entirely", with **DSP usage largely eliminated** and
end-to-end 1.58-bit inference demonstrated in a **5–7 W** power envelope.

## Why "1.58-bit"?

Three possible values (−1, 0, +1) is log₂(3) ≈ **1.58 bits** of information per
weight. Compare to the 32 bits per weight we use today. That is a **20×** shrink
in memory as well as removing the multipliers.

## The other two things he said

**"Fuse the model and the weights together."** Right now the model is data that a
program reads. Fusion means baking the weights *into the circuit itself* — a
weight of −1 does not need to be stored and fetched, it can just *be* a negation
wired into the fabric. You stop moving numbers around, which is the other half of
the cost. He also noted *"the bytes go through the I/O"* — that memory traffic is
frequently the real bottleneck, not the arithmetic.

**"Cut part of the model you don't need."** Pruning. Most weights in a trained
network contribute almost nothing; delete them and the network still works. In a
ternary scheme, a pruned weight is simply a 0 — and a 0 costs *nothing at all* in
hardware, because it is a switch left open.

---

## The board then went and proved him right

This section was written before the model ran. Once it did, the measurement
settled the argument.

`docs/HARDWARE-RESULTS.md`: **1.020 s/token**, against a prediction of 0.1–0.2 s
for a Nios II/f with hardware floating point. The FPU is present and active —
custom instructions 252–255, confirmed in `system.h`. So the arithmetic is *not*
the problem.

The cause, read out of the generated system rather than guessed:

```
ALT_CPU_DCACHE_SIZE   0        <- there is no data cache
```

Every one of the ~259,000 weight reads per token is an individual **uncached**
transaction to a **16-bit** SDRAM. The processor spends its life waiting for
memory, not multiplying.

Which is exactly what Eugene said: *"the bytes go through the I/O for this."*

That reframes his whole suggestion. Ternary is not primarily a way to avoid
multipliers on a chip that only has 144 of them — though it is that too. On
**this** machine its bigger win is that **1.58 bits per weight instead of 32 is a
20× reduction in the traffic that is actually the bottleneck.**

We measured the bottleneck. His suggestion targets it directly. That is a
stronger endorsement than agreeing with it in the abstract.

## Is this what we should have done today?

**No — and being honest about why is the point.**

| | |
|---|---|
| Would it be better on this board? | **Yes, dramatically.** It targets exactly our bottleneck. |
| Can we do it before 8pm? | **No.** |

Ternary models are not made by flipping a switch on an existing model. `stories260K`
was trained in fp32. Making it ternary means either quantization-aware training —
retraining the model with the constraint baked in — or a careful post-training
quantization that then has to be re-validated for output quality. BitNet models
are trained ternary *from scratch* for precisely this reason.

That is a research afternoon, not a hackathon hour, and we already have a
verified path that works. Swapping to it now would trade a working demo for a
maybe.

**So it goes here, honestly labelled as the thing we did not do**, rather than
being quietly claimed.

## If someone picks this up next

Roughly in order:

1. Start from a model **trained** ternary rather than converting ours — the
   BitNet b1.58 family exists and is open.
2. Build the MAC array with **no multipliers at all** — adders, negators and
   muxes out of ordinary logic. Our 144 DSP blocks become irrelevant, which is
   the whole point.
3. Look at **table-lookup matmul**: pack ternary weights into indices and
   precompute partial sums into LUT-resident tables, so runtime matmul becomes
   index → lookup → accumulate. This is what current FPGA work does.
4. **Then** prune, and let the zeros physically disappear.

## What we would say about it on stage

> *"The right answer for this chip is ternary weights — make every weight −1, 0
> or +1 and multiplication stops existing; it becomes a wire, a sign flip, and an
> off-switch. This board has 144 multipliers and 50,000 logic elements, so that
> trade turns our scarcest resource into our most abundant one. We didn't do it,
> because you can't convert a model to ternary in an afternoon — it has to be
> trained that way. But that's the direction, and it came from Eugene."*

Credit where it is due: this was Eugene's idea, not ours.

Sources: [BitNet b1.58 2B4T Technical Report](https://arxiv.org/pdf/2504.12285) ·
[Platinum: LUT-based accelerator for low-bit weight matmul](https://arxiv.org/pdf/2511.21910) ·
[Mix and Match: FPGA-centric DNN quantization](https://arxiv.org/pdf/2012.04240)
