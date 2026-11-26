# Models that fit entirely in 32GB VRAM (Nanbeige4.3-33B and others) vs Qwen3.8-Flash-Next, plus Strata DeepSeek engine check

Research date: 2026-11-21. "Vendor" = self-reported by model maker; "Independent" = Artificial Analysis (AA) or another third party.

## Nanbeige4.3-33B: identity, specs, scores, and does the GPUwerk claim hold?

### Takeaway
The GPUwerk numbers check out against primary sources: AA's own comparison page shows Terminal-Bench 4.0 at 29.8% for Nanbeige4.3-33B and 25.3% for Qwen3.8-Flash-Next. But on AA's overall Intelligence Index v5.0.1, Nanbeige scores 20 and Flash-Next scores 29. DeepSWE 65.5 is a vendor number from mini-swe-agent, so it can't be compared with Qwen's 58.7. The one hands-on review was a failure: the model looped and ran out of tokens. On this box it would decode roughly 3–4x slower than Flash-Next, and at 256K context it does not fit.

### Cited Findings
**Identity / release / license**
- Maker: Nanbeige LLM Lab, the foundation-model team at BOSS Zhipin (Kanzhun). The HF card's contact email is on kanzhun.com. License: Apache-2.0. — [HF model card](https://huggingface.co/Nanbeige/Nanbeige4.3-33B); [AA article](https://artificialanalysis.ai/articles/nanbeige-has-released-nanbeige4-3-33b-scoring-20-on-the-intelligence-index)
- Released about 24–25 Oct 2026 (sources disagree by a day). Community GGUFs appeared on release day, 25 Oct. — [MarkTechPost](https://www.marktechpost.com/2026/10/25/nanbeige-releases-nanbeige4-3-33b-open-agentic-coding-model/); [AtomicChat GGUF](https://huggingface.co/AtomicChat/Nanbeige4.3-33B-GGUF)
- The card positions it as the "flagship teacher model" for the 4.3 series, with a planned 3B distillation. Coverage says the card gives no training token count, data mix, or tech report. — [alphasignal summary of card](https://alphasignal.ai/news/nanbeige-llm-lab-s-nanbeige4-3-33b-beats-qwen-on-coding-agents-with-65-5)

**Architecture / context**
- Dense model, `LlamaForCausalLM`: hidden 7168, 52 layers, 56 attention heads, 8 KV heads (GQA), head_dim 128, FFN 22016, vocab 166,912. rope_theta 1.2e8 with no rope_scaling. Config has no sliding window and no MTP layers. max_position_embeddings is 524,288, so 512K is the native context. — [config.json](https://huggingface.co/Nanbeige/Nanbeige4.3-33B/raw/main/config.json)
- Text in and out only. Reasoning is on by default (`enable_thinking`). `preserve_thinking=True` is recommended for multi-turn tool use and code agents. — [HF card](https://huggingface.co/Nanbeige/Nanbeige4.3-33B)

**Vendor benchmarks (HF card; comparators run at max thinking effort; Qwen3.8-Flash-Next is NOT among the comparators)**
- Terminal-Bench 2.1 (Terminus 2 harness): 80.9 vs Qwen3.8-27B 73.0. Terminal-Bench 4 (mini-swe-agent v2.4.6): 23.8 vs 6.3. — [HF card](https://huggingface.co/Nanbeige/Nanbeige4.3-33B)
- DeepSWE (mini-swe-agent v2.4.6; the card doesn't state a version, GPUwerk calls it v1.1): 65.5 vs Qwen3.8-27B 42.5. — [HF card](https://huggingface.co/Nanbeige/Nanbeige4.3-33B); [GPUwerk](https://gpuwerk.com/blog/best-open-weight-coding-models/)
- SWE-Bench Pro: 60.3 vs Qwen3.8-27B 61.7 (Qwen wins). SWE-Atlas-QnA 50.8, NL2Repo (Claude Code harness) 53.0, Toolathlon-Verified 70.4, Tau3-Bench 48.8, AA-LCR 84.0. — [HF card](https://huggingface.co/Nanbeige/Nanbeige4.3-33B)

**Independent (Artificial Analysis)**
- AA Intelligence Index v5.0.1: Nanbeige4.3-33B 20 vs Qwen3.8-Flash-Next 29. Terminal-Bench 4.0: 29.8% vs 25.3%. AutomationBench-AA: 53.1% vs 55.9%. GDP.pdf: 11.2% vs 15.6%. — [AA comparison page](https://artificialanalysis.ai/models/comparisons/nanbeige4-3-33b-vs-qwen3-8-flash-next)
- Flash-Next's AA page confirms Intelligence Index 29, with 180B total / 6B active parameters (MoE) and a 256K context. — [AA Qwen3.8-Flash-Next](https://artificialanalysis.ai/models/qwen3-8-flash-next)
- AA launch article for Nanbeige (5 Nov 2026): Index 20, the same as Qwen3.8 27B (xhigh). Terminal-Bench 4.0 30% vs Qwen3.8 27B 6%. FrontierCode 2.0 11% vs 15%. HLE-Diamond 7% vs 15%. It declines 71% of AA-Omniscience questions. The article itself gives the size as both 33B and 30B. — [AA article](https://artificialanalysis.ai/articles/nanbeige-has-released-nanbeige4-3-33b-scoring-20-on-the-intelligence-index)
- Verbosity: 158K output tokens per Intelligence Index task vs 110K for Qwen3.8 27B, about 44% more tokens for the same score. — [AA article](https://artificialanalysis.ai/articles/nanbeige-has-released-nanbeige4-3-33b-scoring-20-on-the-intelligence-index)
- AA's "small open-source" page ranks Nanbeige4.3-33B first on Progress Index v1 (312), ahead of Qwen3.8 27B Xhigh (303). — [AA small open models](https://artificialanalysis.ai/models/open-source/small)
- Index-version caution: a search snippet showed Flash-Next at 56 under AA Index v4.1.1 and 40 under v4.3. Only compare numbers from the same index version; Nanbeige 20 vs Flash-Next 29 are both v5.0.1. — [AA Flash-Next vs Opus 4.8](https://artificialanalysis.ai/models/comparisons/qwen3-8-flash-next-vs-claude-opus-4-8)

**Secondary source being verified**
- GPUwerk table: Nanbeige Q4_K_M 20.8 GB, TB4.0 (AA run) 29.8%, vendor TB4.0 23.8%, DeepSWE v1.1 65.5% (vendor only). Qwen3.8-Flash-Next TB4.0 25.3%. These match AA and the HF card. — [GPUwerk](https://gpuwerk.com/blog/best-open-weight-coding-models/)

**GGUF / llama.cpp / tool calling**
- Uses the stock llama architecture, so mainline llama.cpp needs no special support. The card links ~99–105 community quants for llama.cpp, Ollama and LM Studio. — [HF card](https://huggingface.co/Nanbeige/Nanbeige4.3-33B)
- AtomicChat GGUF sizes, with KL / top-1 vs BF16: AD-IQ4_XS 20.3 GB (0.046 / 92.0%), AD-Q4_K_M 21.2 GB (0.038 / 92.6%), AD-Q5_K_M 24.7 GB (0.021 / 94.7%), AD-Q6_K 30.1 GB, Q8_0 35.2 GB. The plain Q4_K_M (20.1 GB, 89.9% top-1) was removed. The author calls the model "unusually sensitive to quantization": plain Q6_K reaches only 95.5% top-1. Quality was measured on text, not agentic tasks. — [AtomicChat GGUF](https://huggingface.co/AtomicChat/Nanbeige4.3-33B-GGUF)
- Tool calls: XML is recommended and JSON is supported. vLLM/SGLang use `--tool-call-parser qwen3_coder --reasoning-parser qwen3`. The chat template is ChatML-like; use llama-server with `--jinja`. Sampling for agentic work: temp 1.0, top_p 0.95, max_new_tokens 65,536. — [HF card](https://huggingface.co/Nanbeige/Nanbeige4.3-33B); [AtomicChat GGUF](https://huggingface.co/AtomicChat/Nanbeige4.3-33B-GGUF)
- Related caveat: on the sibling Nanbeige4.2-3B, a user reported tool calls being dropped by the parser in Nanbeige's llama.cpp fork. That was a different model and an earlier fork. — [HF discussion](https://huggingface.co/Nanbeige/Nanbeige4.2-3B/discussions/17)

**Real-world agentic reports**
- MindStudio hands-on (vLLM, quant and harness not stated). After more than an hour on a debugging task, the model never found the real bug and reported 14–15 spurious ones. An HTML task ran 45 minutes and hit the output and context limits with no file produced. The reviewer saw looping reasoning and repeated compaction, and no tool-call errors. — [MindStudio test](https://www.mindstudio.ai/blog/nanbeige-4-3-33b-benchmark-test)
- I found no r/LocalLLaMA threads with first-hand llama.cpp agentic use. — [search summary of launch coverage, e.g. ai-tldr](https://ai-tldr.dev/models/nanbeige-4-3-33b/)

### Inferences
- **KV cache math** (from config: 2 × 52 layers × 8 KV heads × 128 dim): about 208 KiB per token at fp16.
  - At 128K context: about 27.9 GB at fp16, 14.8 GB at q8_0, 7.9 GB at q4_0.
  - At 256K context: about 55.8 GB at fp16, 29.6 GB at q8_0, 15.7 GB at q4_0.
- **What fits on the 32 GiB R9700** (about 34.4 GB): IQ4_XS or AD-Q4_K_M weights (20.3–21.2 GB) plus about 1–2 GB of compute buffers leave about 11–13 GB for KV.
  - q8_0 KV: tops out around 100K tokens, so 128K does not fit.
  - q4_0 KV: tops out around 180–200K.
  - fp16 KV: about 50K.
  - Conclusion: 256K is not possible fully on GPU, and 128K needs 4-bit KV on top of a model its quantizer calls quant-sensitive.
- Decode speed should be about 22–26 tok/s at short context. This scales the measured 27B Q4 figure (29–33 tok/s) by the weight-size ratio, about 21 vs 17 GB. It will drop at 100K+ context. There is no MTP, so the 47–50 tok/s MTP speedup seen on Qwen 27B doesn't apply.
  - Effective speed is 3–4x slower than Flash-Next on Strata (80–95 tok/s), before counting the 44% higher token use.
  - Prompt processing will probably be around or below the 27B's 800–990 tok/s, vs 1.2–2.2K for Flash-Next.
- Only Terminal-Bench 4.0 favors Nanbeige over Flash-Next (+4.5 points, within the range of one benchmark's noise). Flash-Next leads on the overall AA index (+9) and on AutomationBench.
- DeepSWE 65.5 vs 58.7 is not apples-to-apples: Nanbeige used mini-swe-agent v2.4.6 and the DeepSWE version isn't stated on the card. Treat that comparison as unproven.
- Overall: Nanbeige4.3-33B is the strongest open model that fits fully in 32GB according to AA, but the evidence that it beats Qwen3.8-Flash-Next for multi-hour 100–250K-context Rust agent work is weak. The best case is a tie on agentic quality, with much lower throughput and a context ceiling of about 128K or less.

### Gaps
- No Rust-specific evidence of any kind.
- No independent SWE-bench or DeepSWE run. AA's comparison lists no Coding or Agentic Index for either model.
- No contamination analysis found. The card gives no data-mix disclosure.
- No measured llama.cpp ROCm or R9700 throughput numbers. Speeds above are extrapolated.
- No first-hand llama.cpp tool-calling reports for the 33B with the `qwen3_coder`-style XML format.

## Other ≤40B open-weight models (mid–late 2026) at or above Qwen3.8-Flash-Next

### Takeaway
I found none with independent agentic-coding scores at or above Flash-Next apart from Nanbeige's Terminal-Bench 4.0 result. Qwen3.8-27B ties Nanbeige on AA Index v5 (20) but scores only about 6% on AA Terminal-Bench 4.0. The other small models listed by AA rank lower.

### Cited Findings
- AA small open-weights ranking (Progress Index v1): Nanbeige4.3-33B 312; Qwen3.8 27B Xhigh 303; K2 Horizon 32B 285; K2 Horizon MoVA 36B-A4B 281; Muse Glimmer 30B 267; Qwen3.6 35B-A3B 261; G9v3-39A5B 257; Gemma 4 31B 254. — [AA small open models](https://artificialanalysis.ai/models/open-source/small)
- Qwen3.8-27B: AA TB4.0 5.6%, FrontierCode 2.0 14.9%, UD-Q4_K_XL 17.6 GB. — [GPUwerk](https://gpuwerk.com/blog/best-open-weight-coding-models/); AA Index v5 20 — [AA article](https://artificialanalysis.ai/articles/nanbeige-has-released-nanbeige4-3-33b-scoring-20-on-the-intelligence-index)
- Muse Glimmer 30B: AA Index 6. Vendor TB4 1.6 and DeepSWE 4.4. Gemma4-31B: vendor-table TB4 0.0, DeepSWE 2.7. — [AA article](https://artificialanalysis.ai/articles/nanbeige-has-released-nanbeige4-3-33b-scoring-20-on-the-intelligence-index); [HF card](https://huggingface.co/Nanbeige/Nanbeige4.3-33B)
- Qwen3.6-27B SWE-rebench 31.2%. Qwen3.6-35B-A3B SWE-rebench 24.7%. Mellum2.1-12B-A2.5B has vendor claims only (SWE-bench Verified 47.0). — [GPUwerk](https://gpuwerk.com/blog/best-open-weight-coding-models/)
- One aggregator reported finding no independent Terminal-Bench 4.0 score for any sub-40B model other than those AA ran. — [search across morphllm, gpuwerk et al.](https://www.morphllm.com/best-open-source-llm)

### Inferences
- Under a strict "fits entirely in 32GB" rule, Nanbeige4.3-33B and Qwen3.8-27B are the only candidates in Flash-Next's class, and both trail it on AA's overall index (20 vs 29).
- Flash-Next (180B-A6B) does not fit in 32GB. It works on this box only because Strata offloads MoE experts to system RAM, which keeps it fast.

### Gaps
- K2 Horizon 32B and MoVA 36B-A4B: no Terminal-Bench, SWE, or AA Index details checked (tool-call budget). Worth a follow-up.
- Did not check vals.ai or tbench.ai leaderboards directly.

## System check: does the Strata image bundle a DeepSeek engine (strata-dsv41)?

### Takeaway
No. The running strata-ryzen pod has exactly one component: the generic engine build `0.1.59-linux-x86_64-hip-rx9070`. There is no `strata-dsv41` or any other DeepSeek-specific engine.

### Cited Findings
- Command `kubectl -n ai exec deploy/strata-ryzen -c strata -- sh -c 'ls /opt/strata/components/ /opt/strata/components/*'` output:
  - `/opt/strata/components/:` → `engine`
  - `/opt/strata/components/engine:` → `0.1.59-linux-x86_64-hip-rx9070`

  (Run read-only on 2026-11-21; nothing changed.) — [local kubectl exec, no URL]

### Inferences
- The engine directory is versioned 0.1.59 and targets the HIP rx9070 (RDNA4) build. Whether a DeepSeek engine would be fetched at runtime on model selection was not checked.

### Gaps
- I did not confirm that the running image tag is 0.2.13; only the components directory was listed.
