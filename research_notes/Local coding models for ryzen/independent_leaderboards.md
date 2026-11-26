# Independent leaderboards and evaluations of open-weight models for agentic (Rust) coding — snapshot 2026-11-21

Scope: numbers from parties other than the model vendors (SWE-rebench, Artificial Analysis, Vals.ai, tbench.ai, Aider, academic papers). Vendor figures are marked **[VENDOR]**. Pages were fetched on 2026-11-21 through a summarizing fetch tool. Spot-check any number that drives a decision against the live page.

Hardware filter used below: 32 GB GPU + ~85 GiB RAM, about 110 GB of quantized weights at most. Rule of thumb: about 180B total params at ~4.5–5 bits, or about 250B at ~3 bits. Anything with 500B+ total params is out, even at 2-bit.

## Cross-model comparison table (open-weight only, independent sources)

| Model | Total / active params (source) | Fits ~110 GB? | AA Intelligence Index (no version shown, Nov 2026) | Vals Index (2026-11-19) | Vals Terminal-Bench 4.0 (mini-swe-agent, 2026-11-19) | tbench.ai Terminal-Bench 4.1 (agent shown) | Vals Vibe Code Bench v1.1 (OpenHands, 2026-11-19) | Vals SWE-bench Verified (archived, 2026-09-01) | SWE-rebench (window 2026-05-15→07-01) |
|---|---|---|---|---|---|---|---|---|---|
| **Qwen3.8-Flash-Next (baseline)** | 180B / 6B per AA; 125B per HF/press (conflict, see below) | Yes (UD-Q4_K_XL ≈111 GB) | 29 | not listed | not listed | not listed | not listed | not listed | not listed |
| Qwen3.8 27B | 27B dense | Yes, easily | 20 | not listed | not listed | not listed | 64.85% | 86.0% | not listed |
| DeepSeek V4.1 Flash 1017 | 552B / 16B | No | 33 | 61.26% | 31.82% (non-1017 "V4.1 Flash": 19.70%) | 38.5% (Claude Code) | 87.73% (non-1017: 84.74%) | n/a | not listed |
| DeepSeek V4 Flash 0731 | not found | probably No | not shown | — | 18.69% | — | 74.74% | 88.8% | listed, no score |
| GLM-5.3-Flash | not found | unknown | 28 | 50.86% | 37.37% | 37.0% (Claude Code) | 30.76% (outlier) | 92.0% | not listed |
| GLM-5.3 (full) | 753B / 40B | No | 32 | 59.85% | 38.89% | 41.2% | 78.13% | 95.4% | GLM-5.2: 62.9% (#4 overall) |
| MiMo V2.6 Flash | not found | unknown | 27 | 54.83% | 24.24% | 16.1% (mini-swe-agent) | 78.96% | n/a | V2.5 Pro: 46.5% |
| MiMo V2.6 Pro | 1T / 42B | No | 30 | 57.81% | 31.31% | 27.0% | 85.22% | V2.5 Pro: 74.0% | — |
| MiniMax-M3.1-Flash | not found | unknown | 29 | 53.78% | 25.25% | not listed (M3: 7.6%) | 73.94% | M3: 75.0% | M3: 47.2% |
| Kimi K3 | not found | probably No | not shown | 52.95% | 17.17% | 23.0% | 84.97% | 93.4% | not listed |
| Kimi K3.1 Pro (top open model) | 2.8T / 104B | No | 46 | 62.52% | 63.64% | 59.7% | 84.89% | — | — |
| Tencent Hy4 | 774B / 50.2B | No | 35 | 59.35% | 39.39% | 37.9% | 81.01% | — | — |
| Tencent Hy4 Flash | not found | unknown | not shown | 50.78% | 15.15% | 11.8% (mini-swe-agent) | 74.84% | — | — |
| Inkling 2 Small | 594B / 17B | No | 31 | 56.08% | 12.63% | 13.0% | 81.55% | (Inkling Small v1: 82.2%) | — |
| Inkling 2 Mini | not found | unknown | 20 | 46.46% | 6.57% | — | 77.92% | — | — |
| Muse Spark Open | not found | unknown | 25 | 48.57% | 6.57% | — | 76.19% | — | — |
| Mistral Large 4 | 1.1T / 52B | No | 26 | 56.53% | 26.26% (oss) | 27.6% | 81.56% | Devstral 2: 62.8% | Devstral listed, no score |
| Qwen 3.8 Max 0902 (open per tbench) | not found | probably No | — | 59.05% | 38.89% | 27.0% | 77.14% | 3.8 Max: 85.6% | — |
| Ling 3.1 Flash 1019 | 560B / 25B | No | 30 | — | — | — | Ling 3.0 Flash: 2.91% | Ling 3.0 Flash: 65.2% | — |
| Nemotron 3.5 Super VL | 120B / 12B | Yes | 14 | 29.78% | 0.00% | 0.3% | 3.71% | Nemotron 3.5 Lightning: 52.8% | not listed |
| Gemma 4 31B | 31B dense | Yes | 4 (Reasoning) | — | — | — | — | — | listed, no score |
| gpt-oss-120b | 117B / ~5B | Yes | 4 (High) | — | — | — | — | 33.6% | — |

"—" means the model isn't on that board. Proprietary reference points: AA top is Claude Fable 5.2 (Max) at 65. Vals Index top is Fable 5.2 at 71.31%. TB 4.0 top is 65.15%. Vibe Code top is 93.77%.

## SWE-rebench (nebius): latest monthly results, and is Qwen3.8-Flash-Next on it?

### Takeaway
The newest window on swe-rebench.com runs 2026-05-15 to 2026-07-01. It predates Qwen3.8-Flash-Next (released Aug 26, 2026), DeepSeek V4.1 Flash, GLM-5.3, Kimi K3 and MiniMax M3.1, so none of them appear. It is useful only for older family members. GLM-5.2 is the best open model there, at #4 overall.

### Cited Findings
- The latest window is 15/05/2026–01/07/2026, and the newest news entry is dated 2026-07-01. The slider shows nothing later. — [SWE-rebench leaderboard](https://swe-rebench.com/leaderboard)
- Pass@1 resolved rates in that window: Fable 5 64.5%, Grok 4.5 63.8%, Opus 5 63.4%, **GLM-5.2 62.9% (pass@5 81.1%, $1.40/problem)**, GPT-5.6 Sol 62.3%, **MiniMax M3 47.2%**, **MiMo V2.5 Pro 46.5% ($0.10/problem)**, **DeepSeek-V4 Pro 40.2%**, **Qwen3.6-27B 31.2%**, **Qwen3.6-35B-A3B 24.7%**, **Qwen3.5-35B-A3B 17.1%**. — [SWE-rebench](https://swe-rebench.com/)
- Not listed: Qwen3.8-Flash-Next, DeepSeek-V4.1-Flash, GLM-5.3, Kimi K3, Qwen3.8-27B, Nemotron. Gemma 4 31B, DeepSeek-V4 Flash, Devstral-2-123B, Devstral-Small-2 and Kimi K2.6 are listed but show N/A in this window. — [SWE-rebench](https://swe-rebench.com/)
- Third-party aggregator BenchLM ("Oct 29, 2026 update") shows older SWE-rebench numbers (GLM-5 62.8%, Gemma 4 31B 41.6%, MiniMax M2.7 51.9%). These are from older windows and should not be mixed with the window above. — [BenchLM](https://benchlm.ai/benchmarks/sweRebench)

### Inferences
- SWE-rebench has seemingly not published a window since July 2026. It gives no independent decontaminated reading on any of the current candidates, including the baseline.
- The open family to watch is GLM: GLM-5.2 is within noise of frontier closed models on fresh tasks.

### Gaps
- No Aug–Nov 2026 SWE-rebench window was found. A new window might load client-side and be invisible to the fetch tool, so check the site manually.

## Artificial Analysis indices

### Takeaway
On the AA Intelligence Index, Qwen3.8-Flash-Next (29) is level with MiniMax-M3.1-Flash (29) and just above GLM-5.3-Flash (28) and MiMo-V2.6-Flash (27). It is behind only much larger models: DeepSeek V4.1 Flash 1017 at 33 (552B), Hy4 at 35 (774B), Kimi K3.1 Pro at 46. AA flags the baseline as very slow and verbose. I could not get Coding Index or Agentic Index values.

### Cited Findings
- Qwen3.8-Flash-Next: Intelligence Index 29 (#10 of 33 open models in its class, median 23). AA lists it at **180B total / 6B active**, 256k context, released 2026-08-26, Qwen Community License 1.0. It takes 34.9 min per index task (peer median 14.7), 94 s to first answer token, and 156M output tokens per index run (median 104M). — [AA model page](https://artificialanalysis.ai/models/qwen3-8-flash-next)
- Other open-weight Intelligence Index scores: Kimi K3.1 Pro 46 (2.8T/104B); Tencent Hy4 35 (774B/50.2B); DeepSeek V4.1 Flash 1017 (Max) 33 (552B/16B); GLM-5.3 (Max) 32 (753B/40B); Inkling 2 Small 31 (594B/17B); MiMo-V2.6-Pro 30 (1T/42B); Ling 3.1 Flash 1019 30 (560B/25B); Mistral Large 4 (High) 26 (1.1T/52B); Qwen3.8 27B (Xhigh) 20; Nemotron 3.5 Super VL 14 (120B/12B). — [AA open-source models](https://artificialanalysis.ai/models/open-source)
- From the full leaderboard: Qwen3.8-Flash-Next 29, MiniMax-M3.1-Flash 29, GLM-5.3-Flash 28, MiMo-V2.6-Flash 27, Muse Spark Open (Xhigh) 25, Inkling 2 Mini 20, Gemma 4 31B Reasoning 4, gpt-oss-120b High 4. Top proprietary: Claude Fable 5.2 (Max) 65. — [AA leaderboard](https://artificialanalysis.ai/leaderboards/models)
- AA's coding-index URL returned 404, and the model page shows no Coding or Agentic Index for the baseline. — [AA model page](https://artificialanalysis.ai/models/qwen3-8-flash-next)

### Inferences
- Gemma 4 31B and gpt-oss-120b score 4. The index has evidently been rescaled with harder evals, so these older models are no longer competitive.
- On "intelligence per local byte", Qwen3.8-Flash-Next is the best on AA among models that fit the box. Qwen3.8 27B (20) and Nemotron 3.5 Super (14) trail it.

### Gaps
- No AA Coding Index, Agentic Index or AA-LCR numbers were obtained. The pages may render client-side.
- Params for GLM-5.3-Flash, MiMo-V2.6-Flash, MiniMax-M3.1-Flash, Hy4 Flash, Inkling 2 Mini and Muse Spark Open were not found on AA. They need to come from model cards.
- **Param conflict for the baseline:** AA says 180B/6B, the brief and the HF/press description say 125B ([eesel](https://www.eesel.ai/blog/qwen38-flash-next)). An Unsloth UD-Q4_K_XL of ~111 GB ([summary via search](https://www.mindstudio.ai/blog/run-qwen3-8-flash-next-locally/)) is about 4.9 bits/param at 180B but about 7.1 at 125B, which fits 180B better. The extra may be vision/MTP weights. Unresolved.

## Vals.ai (Vals Index, Terminal-Bench 4.0, Vibe Code Bench, SWE-bench)

### Takeaway
Vals has not evaluated Qwen3.8-Flash-Next on any board. Among the "Flash" class, DeepSeek V4.1 Flash 1017 leads every Vals metric but has 552B params. GLM-5.3-Flash is strong on terminal and SWE tasks but collapses on Vibe Code. MiMo V2.6 Flash and MiniMax-M3.1-Flash are mid-pack. Qwen3.8 27B is the only small local model with solid Vals numbers: SWE-bench Verified 86.0% and Vibe Code 64.85%.

### Cited Findings
- **Vals Index** (2026-11-19), open models: Kimi K3.1 Pro 62.52%, DeepSeek V4.1 Flash 1017 61.26%, GLM 5.3 59.85%, Hy4 59.35%, Qwen 3.8 Max 0902 59.05%, MiMo V2.6 Pro 57.81%, Mistral Large 4 56.53%, Inkling 2 Small 56.08%, MiMo V2.6 Flash 54.83%, MiniMax-M3.1-Flash 53.78%, DeepSeek V4 Pro 0813 52.97%, Kimi K3 52.95%, GLM 5.3 Flash 50.86%, Hy4 Flash 50.78%, Muse Spark Open 48.57%, Inkling 2 Mini 46.46%, Nemotron 3.5 Super VL 29.78%. Top: Claude Fable 5.2 71.31%. — [Vals Index](https://www.vals.ai/benchmarks/vals_index)
- **Terminal-Bench 4.0 on Vals** (2026-11-19): mini-swe-agent (single bash tool), avg@3 pass@1, 8 h limit per task. Hy4 39.39%, GLM 5.3 38.89%, GLM 5.3 Flash 37.37%, DeepSeek V4.1 Flash 1017 31.82%, MiMo V2.6 Pro 31.31%, Mistral Large 4 (oss) 26.26%, MiniMax-M3.1-Flash 25.25%, MiMo V2.6 Flash 24.24%, DeepSeek V4.1 Flash (non-1017) 19.70%, DeepSeek V4 Flash 0731 18.69%, Kimi K3 17.17%, Hy4 Flash 15.15%, Inkling 2 Small 12.63%, Inkling 2 Mini 6.57%, Muse Spark Open 6.57%, Nemotron 3.5 Super VL 0.00%. Kimi K3.1 Pro 63.64% (#4 overall). — [Vals TB4](https://www.vals.ai/benchmarks/terminal-bench-4)
- **Vibe Code Bench v1.1** (2026-11-19, OpenHands): DeepSeek V4.1 Flash 1017 87.73%, MiMo V2.6 Pro 85.22%, Kimi K3 84.97%, Mistral Large 4 81.56%, Inkling 2 Small 81.55%, Hy4 81.01%, MiMo V2.6 Flash 78.96%, GLM 5.3 78.13%, Inkling 2 Mini 77.92%, Muse Spark Open 76.19%, Hy4 Flash 74.84%, MiniMax-M3.1-Flash 73.94%, Qwen 3.8 27B 64.85%, GLM 5.3 Flash 30.76%, Nemotron 3.5 Super VL 3.71%. — [Vals Vibe Code](https://www.vals.ai/benchmarks/vibe-code)
- **SWE-bench Verified** (archived as saturated, last update 2026-09-01, mostly mini-SWE-agent): GLM 5.3 95.4%, Kimi K3 93.4%, GLM 5.3 Flash 92.0%, DeepSeek V4 Flash 0731 88.8%, **Qwen 3.8 27B 86.0%**, Qwen 3.8 Max 85.6%, Inkling Small 82.2%, MiniMax-M3 75.0%, MiMo V2.5 Pro 74.0%, Devstral 2 62.8%, Nemotron 3.5 Lightning 52.8%, GPT OSS 120B 33.6%. — [Vals SWE-bench](https://www.vals.ai/benchmarks/swebench)
- Active Vals coding boards as of 2026-11-19: Vals Index, Vibe Code Bench v1.1, Code Migration v1.1, ProgramBench, Terminal-Bench 4.0, SkillsBench, IOI v2, SWE-bench Multimodal. SWE-bench Verified and Terminal-Bench 2.0/2.1 are archived. DeepSeek V4.1 Flash is listed #1 on SkillsBench. — [Vals benchmarks](https://www.vals.ai/benchmarks)
- Terminal-Bench 2.0 on Vals is archived as of 2026-06-04 and only includes older models (DeepSeek V4 56.18%, GLM 5.1 53.93%, MiniMax-M3 46.07%, Qwen 3.6 27B 44.94%, Gemma 4 31B IT 39.33%). — [Vals TB2](https://www.vals.ai/benchmarks/terminal-bench-2)

### Inferences
- GLM-5.3-Flash scores 37.4% on TB4 (near full GLM-5.3) and 92% on SWE-V, but 30.8% on Vibe Code. That looks like a weakness in long greenfield builds under OpenHands, or a harness and tool-format failure, rather than a lack of coding ability. Worth testing directly.
- Qwen3.8-Flash-Next's absence from every Vals board is the biggest gap. Its vendor SWE-bench Pro and Multilingual numbers cannot be checked here.

### Gaps
- Vals Code Migration, ProgramBench and SkillsBench values for open models were not fetched.

## Terminal-Bench official (tbench.ai), Aider, LMArena, SWE-bench official, Multi-SWE-bench, DeepSWE, long context

### Takeaway
The official Terminal-Bench is now version 4.1. Kimi K3.1 Pro is the only open model in the top 15. Among locally plausible "Flash" models, GLM-5.3-Flash (37.0%) is far ahead of MiMo V2.6 Flash (16.1%) and Hy4 Flash (11.8%), and Qwen3.8-Flash-Next is not on the board. The Aider polyglot board is stale (last update Nov 2025). I did not reach LMArena, swebench.com, Multi-SWE-bench, the DeepSWE leaderboard or the long-context leaderboards.

### Cited Findings
- tbench.ai shows only **Terminal-Bench 4.1**, with no update date. The newest model on it was released 2026-11-18. Agents differ per row (Claude Code vs mini-swe-agent). Open entries: Kimi K3.1 Pro + Claude Code 59.7% (#11), GLM-5.3 41.2%, DeepSeek V4.1 Flash 1017 38.5%, Hy4 37.9%, GLM-5.3-Flash 37.0%, Mistral Large 4 27.6%, Qwen3.8-Max-0902 27.0%, MiMo V2.6 Pro (mini-swe-agent) 27.0%, Kimi K3 23.0%, MiMo V2.6 Flash 16.1%, Inkling Small 2 13.0%, Hy4 Flash 11.8%, MiniMax M3 7.6%, DeepSeek V4 Pro 0813 6.7%, Nemotron 3.5 Super VL 0.3%. Top: Copilot Fusion 71.2%. — [tbench.ai](https://www.tbench.ai/leaderboard)
- Aider polyglot was last updated 2025-11-20. Its newest open entries are DeepSeek-V3.2-Exp Reasoner 74.2%, Kimi K2 59.1% and gpt-oss-120b 41.8%. There is no per-language (Rust) breakdown, although Rust is one of the six languages across 225 Exercism tasks. — [Aider leaderboard](https://aider.chat/docs/leaderboards/)
- Snorkel's Senior SWE-Bench (2026-07-30 refresh) added Kimi K3 and MiniMax M3. No open model is in its top 8. — [Snorkel](https://senior-swe-bench.snorkel.ai/blog/2026-07-30-refresh) (search snippet only, not fetched)

### Inferences
- Scaffold matters a lot. On tbench, MiniMax M3 scores 7.6% with mini-swe-agent and 1.01% on Vals TB4, while Vals SWE-V gives it 75%. DeepSeek V4 Pro 0813 scores 6.7% on TB4.1 with Claude Code but 96.4% on Vals SWE-V. Some models' terminal-task scores look like tool-protocol failures rather than capability. Test the actual local harness before trusting any board.
- The same model and benchmark family gives different numbers on tbench and Vals (DeepSeek V4.1 Flash 1017: 38.5% vs 31.82%; GLM-5.3-Flash: 37.0% vs 37.37%). The cause is different versions (4.1 vs 4.0) and agents (Claude Code vs mini-swe-agent).

### Gaps
- Not fetched, because of the tool-call budget: LMArena WebDev, swebench.com bash-only, the Multi-SWE-bench leaderboard, SWE-PolyBench, the DeepSWE leaderboard, MRCR, LongBench v2, RULER and Fiction.LiveBench. No independent long-context numbers were collected for any candidate.

## Rust-specific evidence

### Takeaway
I found no independent Rust-specific scores for any current candidate, including the baseline. The best Rust evidence is older academic work (Rust-SWE-bench, ICSE '26). It shows Rust repo-level resolution is much harder than Python. It also shows that failures are dominated by path/import resolution, trait/type errors and Cargo reproduction problems.

### Cited Findings
- Rust-SWE-bench has 500 tasks from 34 Rust repositories. The best baseline, OpenHands + Claude Sonnet 3.7, resolved 21.2%. The RustForger method reached 28.6%. Qwen3, GPT-4o and o4-mini configurations ranged from about 1.8% to 8.2%. In those runs, 43.7% of compile errors were naming, scoping or path-resolution failures and 32.6% were type/trait violations. The best agent failed to reproduce 44.5% of issues (52.5% of those from dependency/Cargo configuration), and disabling reproduction cut resolution by 42%. — [arXiv 2602.22764](https://arxiv.org/html/2602.22764v1)
- Multi-SWE-bench has 239 Rust instances from 10 repos. No current open-model Rust-subset scores were found. DeepSWE's 113 tasks include Rust. — [search summary](https://arxiv.org/html/2602.22764v1)
- Modal's July 2026 guide to open models for Rust agents says no consistent Rust-only benchmark exists across models. Every score it cites is vendor or unattributed Python SWE-bench, and it declines to rank models for Rust. — [Modal](https://modal.com/resources/best-open-source-models-rust-coding-agents)
- A search for community reports of Qwen3.8-Flash-Next in Rust agents found only local-run guides (llama.cpp and Unsloth GGUFs; harnesses such as OpenCode, Hermes Agent, Pi) and a large r/LocalLLaMA release megathread. None reports Rust-specific results. — [MindStudio](https://www.mindstudio.ai/blog/qwen-3-8-27b-vs-flash-next-local-agents), [DataCamp](https://www.datacamp.com/tutorial/run-qwen3-8-flash-next-locally)

### Inferences
- The vendor's SWE-bench Multilingual 81.0 for Qwen3.8-Flash-Next **[VENDOR]** is the only Rust-touching number for the baseline. Since independent Rust data doesn't exist, the user should run a small private Rust eval: a few dozen of their own issues in their own harness, with a cargo build/test loop. That is the only way to get a decisive comparison.
- The failure modes above suggest an agent loop that feeds `cargo check` and `cargo test` output back to the model matters as much as model choice.

### Gaps
- No Multi-SWE-bench Rust-subset, SWE-bench Multilingual Rust-task, Aider-Rust or RustEvo numbers for 2026 open models.
- No r/LocalLLaMA Rust threads were found.

## Caveats: contamination, harness sensitivity, version mismatches

### Takeaway
Treat board numbers as rough ordinal signals. Scaffold and version differences move scores by tens of points. Several boards are archived or stale. And the "Flash" names hide very different sizes: DeepSeek V4.1 Flash has 552B total params.

### Cited Findings
- SWE-Bench Pro V2 (arXiv 2610.24206, v1 2026-10-16, v2 2026-11-11, by Dan, Da, Bhutani et al.) repaired or retired 480 of 731 original Pro tasks, leaving 642. It locks network access to the model endpoint only and re-grades patches in clean containers, to stop agents fetching upstream fixes. Frontier agents reach up to 99.4%. A 51-task Hard split spans 52.9–98.0%. The abstract page gives no per-scaffold spread, open-model scores or Rust breakdown. — [arXiv 2610.24206](https://arxiv.org/abs/2610.24206)
- Vals has archived SWE-bench Verified (Sep 2026) and Terminal-Bench 2.0/2.1 as saturated. — [Vals benchmarks](https://www.vals.ai/benchmarks)
- Modal notes OpenAI no longer treats SWE-bench Verified as a definitive frontier measure because of contamination and test issues. — [Modal](https://modal.com/resources/best-open-source-models-rust-coding-agents)
- The same model has different variants per board: DeepSeek "V4.1 Flash" vs "V4.1 Flash 1017" (19.70% vs 31.82% on Vals TB4), and Mistral Large 4 Preview vs oss. — [Vals TB4](https://www.vals.ai/benchmarks/terminal-bench-4)

### Inferences
- The vendor SWE-bench Pro 62.5 for the baseline **[VENDOR]** may be on original Pro, not V2. It can't be compared with any independent number collected here.
- Ranking for a box with ~110 GB of weights, from independent evidence only:
  1. **Qwen3.8-Flash-Next** (AA 29; no agentic boards at all).
  2. **GLM-5.3-Flash**, if its params fit (AA 28; TB4 37%; SWE-V 92%; weak Vibe Code). This is the most promising alternative on terminal and agentic boards. Its size must be confirmed.
  3. **MiniMax-M3.1-Flash** and **MiMo V2.6 Flash** (AA 29/27; Vals Index 53.8/54.8; TB4 about 24–25%). Their sizes must also be confirmed.
  4. **Qwen3.8 27B** (AA 20; SWE-V 86%; Vibe Code 64.9%). It fits easily and leaves room for long context.

  DeepSeek V4.1 Flash 1017 (552B), Hy4, Inkling 2 Small, Mistral Large 4, Kimi K3.x and Ling 3.1 Flash are too large. Nemotron 3.5 Super, Gemma 4 31B and gpt-oss-120b fit but score poorly on agentic boards.

### Gaps
- Full text of the SWE-Bench Pro V2 paper not read (scaffold spread, contamination numbers, open-model results).
- Total/active params for GLM-5.3-Flash, MiMo V2.6 Flash, MiniMax-M3.1-Flash, Hy4 Flash, Inkling 2 Mini, Muse Spark Open and Kimi K3 are still needed to decide what fits.
