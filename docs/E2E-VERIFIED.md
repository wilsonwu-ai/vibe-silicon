# End-to-end, verified on real hardware

**Board → JTAG → bridge → public internet → byte-identical story.**

Verified 2026-08-09 at ~16:45 by reading the live public endpoint, not by
being told.

## The evidence

What https://vibe-silicon.wilson-af8.workers.dev received, in order:

```
nios2-terminal: connected to hardware target using JTAG UART on cable
nios2-terminal: "USB-Blaster [USB-0]", device 1, instance 0
nios2-terminal: (Use the IDE stop button or Ctrl-C to terminate)

Once upon a time, there was a little girl named Lily. She loved to play outside
in the sun. One day, her mom asked her to teach him a nice way to play in the
sun. Lily was so excited to go outside and jump in the sky.
As she walked, she saw a tall toy car that was much carrots. The toys asked her
to buy some cars and Lily all nicely. The car was curious and said, "What's
wrong?" Lily said, "I am sorry, I want to help you."
They both ate the cards and toys and had a brilliant, bunnys. They put the car
and ate the ball together. Lily was happy that the ball could read
```

**That first line is the load-bearing one.** `nios2-terminal` prints
`connected to hardware target ... USB-Blaster [USB-0]` only when it is talking
to a physical cable. A simulator cannot emit it.

And the story itself:

```
page   md5   8e6e99ed83fc476e1a33bc0940ecffa1   575 bytes
golden md5   8e6e99ed83fc476e1a33bc0940ecffa1   575 bytes
```

Byte-identical to `dist/llama-nios/expected_output.txt`, which is itself
byte-identical to upstream `llama2.c` on macOS. **The same 575 bytes on three
different machines: a Mac, a Nios II core on a MAX 10, and a public web page.**

## Why this was checked rather than assumed

At 16:24 the team reported tokens flowing end to end. At 16:38 came:

> *"jk it was on the simulator the whole time. claude is programming the hardware
> now."*

That is a good catch and the right instinct — but it left the project in an
ambiguous state, and "we think it's on hardware" is not something to say on a
stage. So the public endpoint was read directly and the output hashed against
the golden reference.

The `nios2-terminal` hardware banner and the matching md5 settle it. Whatever
was simulated earlier, **what is on the public URL now came off real silicon.**

## What this completes

Sundai's rule is *get off the localhost — deploy a webapp demo that works on the
internet.* That is now satisfied by a real result rather than a placeholder:

| | |
|---|---|
| Model on real hardware | ✅ Nios II/f soft core on MAX 10 |
| Output correctness | ✅ byte-identical, all 256 tokens |
| Speed | 1.020 s/token measured |
| Reaches the public internet | ✅ live, verified from outside |
| Honest labelling | ✅ page distinguishes live from replay |

## The one gap this does not close

The bridge declares `src=board` or `src=replay`, which distinguishes a **live
stream** from a **recorded file** — but it cannot distinguish a **board** from a
**simulator**, because both look like a process printing to stdout.

That is exactly the ambiguity that produced the 16:38 scare. The reliable tell is
the `nios2-terminal` banner in the stream itself: if it names a USB-Blaster
cable, it is hardware.

Worth fixing properly if this is ever run again: have the bridge require the
banner before labelling anything `board`.
