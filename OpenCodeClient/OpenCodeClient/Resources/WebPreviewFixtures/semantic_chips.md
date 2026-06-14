# Semantic Chips Regression Fixture

This fixture exercises the four semantic chip variants (ok / bad / warn / block)
using the shell's CSS variables with light/dark fallback. It is the regression
guard for two real bugs caught during dogfood:

1. **Dark mode chip washed out**: previously `--ok-bg` etc. were deep tinted
   colors that sat too close to the dark card background — chip didn't pop.
   Fixed by switching dark `*-bg` to the saturated hue itself (`--ok-bg=#10b981`).
2. **Bare `.ok` single-class selector overridden by card text color**: card
   `.vx-card{color:var(--fg)}` and `.ok{color:var(--ok-fg)}` had the same
   specificity; card won, chip text fell to `--fg`. Fixed by using `.vx-chip.ok`
   compound selector (specificity 0,0,2,0 > card's 0,0,1,0).

<style>
.vx-card{border:1px solid var(--border,#d7dee8);border-radius:12px;padding:12px;background:var(--card-bg,#fff);color:var(--fg,#1a1a1a);margin:10px 0}
.vx-chip{display:inline-block;border-radius:999px;padding:3px 10px;font-size:.85rem;font-weight:650;margin-right:6px}
.vx-chip.ok{background:var(--ok-bg,#d1fae5);color:var(--ok-fg,#065f46)}
.vx-chip.bad{background:var(--bad-bg,#fee2e2);color:var(--bad-fg,#991b1b)}
.vx-chip.warn{background:var(--warn-bg,#fef3c7);color:var(--warn-fg,#92400e)}
.vx-chip.block{background:var(--block-bg,#e5e7eb);color:var(--block-fg,#374151)}
</style>

<div class="vx-card">
<p><span class="vx-chip ok">CHIP_OK_SENTINEL</span> A confirmed signal that should look like a green pill in both themes.</p>
<p><span class="vx-chip bad">CHIP_BAD_SENTINEL</span> A negated hypothesis that should look like a red pill in both themes.</p>
<p><span class="vx-chip warn">CHIP_WARN_SENTINEL</span> A cautious candidate that should look like an amber pill in both themes.</p>
<p><span class="vx-chip block">CHIP_BLOCK_SENTINEL</span> A blocked path that should look like a grey pill in both themes.</p>
</div>

If any of those four sentinels is invisible (background blends into the card
background, or foreground blends into the background), the dark-mode contrast
or the selector-specificity regression has come back.
