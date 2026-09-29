# LLM Phenotyping — Reproducibility Materials

Reproducibility materials for **"Richer database context improves LLM-generated EHR phenotyping algorithms,"**
a study evaluating whether large language models (LLMs) can generate
SQL-based phenotyping algorithms for type 2 diabetes mellitus (T2DM), and how
the amount of database implementation context provided in the prompt affects
performance.

## Study purpose

Developing executable EHR phenotyping scripts normally requires a rare
combination of clinical knowledge, familiarity with the local data model
(here, the OMOP Common Data Model), and SQL skill. This project evaluates
whether LLMs can close that gap — and, specifically, how much database
schema/implementation context an LLM needs to generate an accurate,
executable phenotyping query. Model outputs are benchmarked against the
published eMERGE T2DM reference phenotype using F1, positive predictive
value (PPV), recall, and SQL executability, across both a synthetic OMOP
database and real University of North Carolina (UNC) Health EHR data.

## Evaluated LLMs

Eight publicly accessible LLM-based systems, evaluated without fine-tuning:

| Model | Type |
|---|---|
| ChatGPT 5.5 | General-purpose (OpenAI) |
| Claude Sonnet 4.5 | General-purpose (Anthropic) |
| Gemini 3 | General-purpose (Google DeepMind) |
| Microsoft Copilot | Coding assistant |
| Llama-3.3-70B-Instruct | Open, instruction-tuned |
| Gemma-4-31B | Open, smaller/efficient |
| OMOP-SQL-Assistant | Domain-specific Custom GPT |
| QueryGPT | Domain-specific Custom GPT |

Model selection rationale and prompt templates are in the paper's Methods
and Supplementary Material.

## Alpha vs. Beta prompting

For each model and context level:
- **Alpha** — five independent generations (`p1`–`p5`) of the phenotyping
  SQL from the same prompt.
- **Beta** — a single consolidated generation, produced by giving the model
  its own five Alpha outputs and asking it to identify correct/missing/
  incorrect criteria and return one refined query.

## Synthetic vs. UNC EHR evaluation

- **Synthetic OMOP**: derived from the Synthea COVID-19 dataset, adapted to
  OMOP by the NC TraCS Institute. 124,150 patients; 6,215 eMERGE-positive.
  Contains no real patients, so full sample-row context (Level 4, below)
  could be shown to models.
- **UNC EHR (SHIRE)**: real, de-identified-in-place UNC Health OMOP data,
  analyzed only inside the UNC Secure Health Informatics Research
  Environment (SHIRE); patient data never left the secure enclave and was
  never sent to external LLMs. 23,820 patients across three ICD-10-derived
  cohorts; 5,732 eMERGE-positive. IRB-exempt under UNC #25-0534.

## Prompt / context conditions

| Level | Context | Synthetic | UNC EHR |
|---|---|---|---|
| 0 | None (zero-shot) | Yes | No |
| 1 | OMOP table names | Yes | Yes |
| 2 | OMOP table names + relations | Yes | Yes |
| 3 | Detailed schema codebook, fields, implementation details | No | Yes (full context) |
| 4 | Codebook + representative sample rows | Yes (full context) | No — patient privacy |

Full prompt text is in the paper's Supplementary Material.

## Repository contents

```
llm-phenotyping/
├── generated_sql/
│   ├── <model>/                      LLM-generated SQL, one folder per model
│   └── eMERGE_reference_algorithm/   eMERGE T2DM reference algorithm — latest
│                                      corrected version for each environment
│                                      (v4 synthetic, v5 SHIRE) + correction notes
├── analysis/
│   ├── synthetic/                    Code to reproduce the synthetic-OMOP aggregate analysis
│   └── unc_ehr/                      Code that produced the UNC EHR aggregate analysis
│                                      (requires SHIRE access; see note in script)
├── results/
│   └── aggregate/
│       ├── synthetic/                Aggregate, model-level metrics (F1/PPV/recall/etc.) —
│       │                              no patient-level data
│       └── unc_ehr/                  Aggregate, model-level metrics from the SHIRE analysis —
│                                      no patient-level data; TP/FP/FN/TN and raw prediction
│                                      counts are omitted (real patient counts), unlike synthetic
├── LICENSE                           MIT (code)
├── LICENSE-DATA                      CC BY 4.0 (generated SQL, results)
└── .gitignore
```

Every generated-SQL filename preserves the original model name and
experiment label (context level, Alpha replicate number, or Beta) used
internally, so results remain traceable back to a specific prompt condition:

- `a<level>p<variant>.sql` — Alpha (context level 0–4, replicate p1–p5)
- `b<level>.sql` — Beta (context level 0–4)
- `_shire` suffix — same prompt/level, run against UNC EHR (SHIRE) instead of synthetic OMOP
- `_fixed` suffix — corrected re-run after a bug fix
- `beta_flowchart.sql` (where present) — a one-off Beta variant prompted with an added flowchart-style instruction, kept separate from the canonical `b<level>`

## Data availability

This repository contains no patient-level or row-level EHR data — no MRNs,
patient IDs, dates of birth/service, clinical notes, or other identifiers,
and no raw SHIRE exports. `results/aggregate/` holds only aggregate,
model-level metrics (F1, PPV, Recall, Jaccard, FPR, executability);
per-patient cohort files and prediction-ID lists are not included.
`analysis/unc_ehr/analyze_t2dm_unc_ehr.py` is included for transparency but
contains no data itself and cannot be run outside SHIRE, since its inputs
are UNC EHR patient data that never leaves that environment.

## Reproducing the aggregate analyses

**Synthetic OMOP:**
```
cd analysis/synthetic
pip install pandas numpy scipy matplotlib seaborn
python analyze_t2dm_synthetic.py
```
This reads the per-model/per-condition SQL outputs (regenerated by running
the queries in `generated_sql/<model>/` against the synthetic OMOP database)
and reproduces the tables in `results/aggregate/synthetic/`.

**UNC EHR (SHIRE):** `analysis/unc_ehr/analyze_t2dm_unc_ehr.py` reproduces
the UNC EHR aggregate metrics, but can only be run from inside SHIRE by
someone with approved SHIRE access, against the (non-public) per-model
prediction files and cohort labels described in the script's docstring.
Its aggregate output tables are in `results/aggregate/unc_ehr/`.

## License

Source code (`analysis/**/*.py`) is MIT-licensed (`LICENSE`). Generated SQL
and aggregate results are CC BY 4.0 (`LICENSE-DATA`) — reuse is permitted
with attribution.

## Citation

If you use these materials, please cite the associated paper (citation to
be added upon publication).
