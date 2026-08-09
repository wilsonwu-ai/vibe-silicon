# The talk, as questions

Ask the question out loud. Pause half a beat. Answer it.

This format was chosen deliberately over exposition: most of the room does not
know what an FPGA is, and a question gives them permission not to know. It also
survives interruption — if someone asks a question you already have queued, say
"that's my next one" and jump to it. A lecture does not survive that.

Runs about three minutes. Every number is measured.

---

## 1. "What is this thing I'm holding?"

> A DE10-Lite. It's an FPGA board — and it costs **eighty-two dollars** with a
> student ID.
>
> Here's the important part: **it has no processor.** No ARM, no Linux, no
> filesystem. It arrives as a blank sheet of circuitry.

## 2. "Okay — what's an FPGA? How's it different from a CPU or a GPU?"

> A **CPU** is one very fast worker doing one thing at a time.
>
> A **GPU** is thousands of simple workers all doing the same thing at once.
>
> An **FPGA** is a box of parts. You don't get a worker — **you build the worker.**

## 3. "So what did you actually do?"

> We built a processor inside it.
>
> You can describe a CPU in code, load that description onto the chip, and now the
> chip *is* a CPU. It's called a soft core.
>
> Then we compiled a language model to run on the processor we'd just made. And it
> wrote a story.

## 4. "How does a model even fit? You said there's no filesystem."

> There isn't. No SD card, nothing to open a file from.
>
> So the model isn't *loaded* — **it's compiled into the program itself.** A
> million bytes of weights, baked in as a constant.
>
> It uses **2.6%** of the board's memory.

## 5. "Is this a real LLM?"

> **No, and I want to be precise about that.** It's 292,000 parameters, trained on
> children's stories. A real transformer — same attention, same architecture —
> just tiny.
>
> We also didn't design the CPU. That core is Intel's, prebuilt. What we wrote is
> the bare-metal port.
>
> What *is* true: **every line of the math is byte-for-byte unmodified**, and the
> board's output is **byte-identical** to the reference. All 256 tokens. We checked.

## 6. "How fast is it?"

> **One second per word.** We expected a tenth of that. So we went and found out
> why — and this is the interesting bit.
>
> It's **not the math.** The floating-point unit is running fine.
>
> The processor has **no data cache.** So all 259,000 memory reads per word go out
> individually to a slow 16-bit memory.
>
> **It spends its life waiting, not calculating. It's a memory problem wearing a
> compute problem's clothes.**

## 7. "What would you do with more time?"

> Eugene told us this afternoon — *"the bytes go through the I/O"* — before we'd
> measured it. Then we measured it and he was right.
>
> His fix is ternary weights: make every weight **minus-one, zero, or plus-one**,
> and multiplication stops existing. Plus-one is a wire. Minus-one is a sign flip.
> Zero is a switch left open.
>
> That's a **20× cut in exactly the traffic we proved is the bottleneck.**
>
> We didn't do it — you can't convert a model to ternary in an afternoon. It's in
> the repo, credited to Eugene.

---

## The closer

> **"Everyone's AI demo runs on somebody else's silicon. This one runs on an
> eighty-two dollar board that showed up with no computer on it at all."**

---

## Staging

- **Start the run before question 1.** By Q4 there is text appearing behind you.
- **Q5 is the one that wins the room.** Volunteering the limits before anyone asks
  is what makes everything else believable. Do not skip it to save time.
- **If the JTAG UART throws** (it is single-owner; a stray `nios2-terminal` or an
  open Monitor Program will grab it), do not debug on stage. One sentence — *"the
  JTAG UART is single-owner and something else grabbed it, here's the run from
  earlier"* — and play `demo-8x.mp4`. The output is byte-identical either way, so
  nothing you have said becomes untrue.

## Never say

| ❌ | ✅ |
|---|---|
| "we ran an LLM on an FPGA" | a **292K-parameter transformer** |
| "we built a CPU" | we **programmed a prebuilt soft core** into the fabric |
| "VHDL is worse than Verilog" | our benchmark **cannot support that yet** |
| any other tok/s figure | **1.02 s/token, measured** |
