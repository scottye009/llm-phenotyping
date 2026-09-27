"""
T2DM Phenotype Prediction Analysis - Synthetic Dataset
Compares LLM-generated SQL outputs against corrected gold standard.
"""

import os
import re
import warnings
from pathlib import Path
from itertools import combinations

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.cm as cm
from matplotlib.patches import Rectangle
from matplotlib.colors import Normalize
from matplotlib.lines import Line2D
import seaborn as sns
from scipy import stats

warnings.filterwarnings("ignore", category=FutureWarning)

# =============================================================================
# Configuration
# =============================================================================

# Edit to point at your local per-model SQL execution outputs (not included
# in this repo - see README for what's shared vs. reproduced locally).
BASE_DIR = Path("synthetic_results_combined")
STANDARD_FILE = BASE_DIR / "T2DM_standard_corrected.csv"
OUTPUT_DIR = Path("outputs")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

TOTAL_POPULATION = 124150

MODEL_DISPLAY_NAMES = {
    "gpt": "ChatGPT 5.5",
    "claude": "Claude Sonnet 4.5",
    "llama": "Llama-3.3-70B",
    "gemini": "Gemini",
    "copilot": "Copilot",
    "querygpt": "QueryGPT",
    "omop-assistant": "OMOP-SQL-Assistant",
    "gemma": "Gemma-4-31B",
}

EXCLUDE_MODELS = {"medgemma"}

CONTEXT_LEVELS = ["0", "1", "2", "4"]

# =============================================================================
# Helper Functions
# =============================================================================

def normalize_person_id(series):
    s = series.dropna().astype(str).str.strip()
    s = s.str.replace(r"\.0$", "", regex=True)
    return set(s[s != ""])


def read_person_ids(csv_path):
    df = pd.read_csv(csv_path)
    if "person_id" not in df.columns:
        raise ValueError(f"{csv_path.name}: no 'person_id' column. Columns: {list(df.columns)}")
    return normalize_person_id(df["person_id"])


def parse_filename(path):
    stem = path.stem
    match = re.match(r"^(?P<model>.+?)_(?P<prompt>(?:a[0-4]p[1-5]|b[0-4]))$", stem)
    if not match:
        return None
    model = match.group("model")
    prompt = match.group("prompt")
    if prompt.startswith("a"):
        family = "alpha"
        context_level = prompt[1]
        prompt_variant = prompt[2:]
    else:
        family = "beta"
        context_level = prompt[1]
        prompt_variant = None
    return {
        "model": model,
        "prompt": prompt,
        "family": family,
        "context_level": context_level,
        "prompt_variant": prompt_variant,
    }


def compute_metrics(pred_ids, gold_ids, total_n):
    pred_set = set(pred_ids)
    gold_set = set(gold_ids)

    tp = len(pred_set & gold_set)
    fp = len(pred_set - gold_set)
    fn = len(gold_set - pred_set)
    tn = total_n - tp - fp - fn

    ppv = tp / (tp + fp) if (tp + fp) > 0 else np.nan
    recall = tp / (tp + fn) if (tp + fn) > 0 else np.nan
    fpr = fp / (fp + tn) if (fp + tn) > 0 else np.nan
    f1 = 2 * tp / (2 * tp + fp + fn) if (2 * tp + fp + fn) > 0 else np.nan
    specificity = tn / (tn + fp) if (tn + fp) > 0 else np.nan
    accuracy = (tp + tn) / total_n if total_n > 0 else np.nan

    return {
        "TP": tp, "FP": fp, "FN": fn, "TN": tn,
        "Predicted_Positive": tp + fp,
        "PPV": ppv, "Recall": recall, "F1": f1,
        "FPR": fpr, "Specificity": specificity, "Accuracy": accuracy,
    }


# =============================================================================
# Load Data
# =============================================================================

print("Loading gold standard and model predictions...")

gold_ids = read_person_ids(STANDARD_FILE)
print(f"  Gold standard positives: {len(gold_ids)}")
print(f"  Total population: {TOTAL_POPULATION}")

results = []
for path in sorted(BASE_DIR.glob("*.csv")):
    if path.name == STANDARD_FILE.name:
        continue
    parsed = parse_filename(path)
    if parsed is None:
        continue
    if parsed["model"] in EXCLUDE_MODELS:
        continue
    pred_ids = read_person_ids(path)
    metrics = compute_metrics(pred_ids, gold_ids, TOTAL_POPULATION)
    results.append({**parsed, **metrics})

df = pd.DataFrame(results)
df["model_display"] = df["model"].map(MODEL_DISPLAY_NAMES).fillna(df["model"])

print(f"  Loaded {len(df)} model-prompt combinations across {df['model'].nunique()} models")

# =============================================================================
# 1. Full Metrics Table
# =============================================================================

print("\nComputing per-file metrics...")

metrics_cols = ["model_display", "model", "prompt", "family", "context_level",
                "prompt_variant", "TP", "FP", "FN", "TN", "Predicted_Positive",
                "PPV", "Recall", "F1", "FPR", "Specificity", "Accuracy"]
metrics_table = df[metrics_cols].sort_values(["model", "context_level", "family", "prompt"]).reset_index(drop=True)
metrics_table.to_csv(OUTPUT_DIR / "all_metrics.csv", index=False)

# =============================================================================
# 2. Analysis 1: Version comparison (v1 vs v2)
#    a1/b1 and a2/b2 are two implementation versions at the same context level.
#    Test whether one version is consistently better than the other.
# =============================================================================

print("Analysis 1: Version comparison (v1 vs v2)...")

COMPARISON_METRICS = ["F1", "PPV", "Recall", "FPR"]

# --- 2a. Combined version comparison: v1 (a1+b1) vs v2 (a2+b2) ---
# Pool all outputs at context_level "1" (both alpha and beta) as v1,
# and all outputs at context_level "2" (both alpha and beta) as v2.

version_combined_results = []

for model in df["model"].unique():
    v1_rows = df[(df["model"] == model) & (df["context_level"] == "1")]
    v2_rows = df[(df["model"] == model) & (df["context_level"] == "2")]

    if v1_rows.empty and v2_rows.empty:
        continue

    row_result = {
        "model": model,
        "model_display": MODEL_DISPLAY_NAMES.get(model, model),
        "n_v1": len(v1_rows),
        "n_v2": len(v2_rows),
        "v1_prompts": ", ".join(sorted(v1_rows["prompt"].tolist())),
        "v2_prompts": ", ".join(sorted(v2_rows["prompt"].tolist())),
    }

    for metric in COMPARISON_METRICS:
        v1_vals = v1_rows[metric].dropna().values if not v1_rows.empty else np.array([])
        v2_vals = v2_rows[metric].dropna().values if not v2_rows.empty else np.array([])

        v1_mean = np.nanmean(v1_vals) if len(v1_vals) > 0 else np.nan
        v2_mean = np.nanmean(v2_vals) if len(v2_vals) > 0 else np.nan

        if len(v1_vals) >= 2 and len(v2_vals) >= 2:
            u_stat, p_val = stats.mannwhitneyu(v1_vals, v2_vals, alternative="two-sided")
        else:
            u_stat, p_val = np.nan, np.nan

        row_result[f"v1_mean_{metric}"] = v1_mean
        row_result[f"v2_mean_{metric}"] = v2_mean
        row_result[f"diff_v2_minus_v1_{metric}"] = v2_mean - v1_mean if not (np.isnan(v1_mean) or np.isnan(v2_mean)) else np.nan
        row_result[f"U_stat_{metric}"] = u_stat
        row_result[f"p_value_{metric}"] = p_val

    version_combined_results.append(row_result)

version_combined_df = pd.DataFrame(version_combined_results)
version_combined_df.to_csv(OUTPUT_DIR / "analysis1a_version_v1_vs_v2.csv", index=False)

# Aggregate: sign test across models for v1 vs v2 F1
v_diffs_f1_combined = version_combined_df["diff_v2_minus_v1_F1"].dropna().values
n_v2_better = (v_diffs_f1_combined > 0).sum()
n_v1_better = (v_diffs_f1_combined < 0).sum()
n_ties_combined = (v_diffs_f1_combined == 0).sum()
n_nontie_combined = n_v2_better + n_v1_better
if n_nontie_combined > 0:
    sign_test_p_combined = stats.binomtest(min(n_v2_better, n_v1_better), n_nontie_combined, 0.5).pvalue
else:
    sign_test_p_combined = np.nan

# Wilcoxon on paired v1 vs v2 means across models
paired_v1v2 = version_combined_df.dropna(subset=["v1_mean_F1", "v2_mean_F1"])
if len(paired_v1v2) >= 5:
    wilcoxon_stat_v, wilcoxon_p_v = stats.wilcoxon(paired_v1v2["v1_mean_F1"], paired_v1v2["v2_mean_F1"])
else:
    wilcoxon_stat_v, wilcoxon_p_v = np.nan, np.nan

print(f"  Version comparison: v1 (a1+b1) vs v2 (a2+b2) - pooled per model")
print(f"    Per-model results (Mann-Whitney on all prompts within each version):")
for _, row in version_combined_df.iterrows():
    sig_markers = [m for m in COMPARISON_METRICS if not np.isnan(row.get(f"p_value_{m}", np.nan)) and row[f"p_value_{m}"] < 0.05]
    sig_str = f" [sig: {', '.join(sig_markers)}]" if sig_markers else ""
    v1_f1 = row['v1_mean_F1']
    v2_f1 = row['v2_mean_F1']
    v1_str = f"{v1_f1:.4f}" if not np.isnan(v1_f1) else "N/A"
    v2_str = f"{v2_f1:.4f}" if not np.isnan(v2_f1) else "N/A"
    print(f"      {row['model_display']}: v1 F1={v1_str} (n={row['n_v1']}) vs v2 F1={v2_str} (n={row['n_v2']}){sig_str}")

print(f"    Across models: v2 better in {n_v2_better}/{n_nontie_combined + n_ties_combined} | sign test p={sign_test_p_combined:.4f}")
if not np.isnan(wilcoxon_p_v):
    print(f"    Wilcoxon signed-rank (paired model means): W={wilcoxon_stat_v:.1f}, p={wilcoxon_p_v:.4f}")

# =============================================================================
# 2c. Analysis 1c: Alpha vs Beta - Publication-quality comparison
#
#     Outcomes:
#       Primary: End-to-end success rate (proportion of expected attempts with
#                SQL that executed, returned a usable cohort, AND achieved F1>=0.80)
#       Secondary A: SQL execution rate + mean F1 among successful outputs
#       Secondary B (sensitivity): Penalized mean F1 across ALL expected attempts
#                   (F1=0 for missing/failed/zero-row outputs)
#
#     PPV and FPR reported only for successfully executed outputs.
#     Beta has 1 expected attempt; alpha has 5 (p1–p5).
#     Statistical test: Fisher's exact (success rates) or Mann-Whitney (F1 distributions).
#     When beta has only 1 output, report descriptive differences only.
# =============================================================================

print("\nAnalysis 1c: Alpha vs Beta - publication outcomes...")

EXPECTED_ALPHA_ATTEMPTS = 5
EXPECTED_BETA_ATTEMPTS = 1
F1_SUCCESS_THRESHOLD = 0.80

alpha_beta_results = []

for model in df["model"].unique():
    for cl in CONTEXT_LEVELS:
        alpha_rows = df[(df["model"] == model) & (df["family"] == "alpha") & (df["context_level"] == cl)]
        beta_rows = df[(df["model"] == model) & (df["family"] == "beta") & (df["context_level"] == cl)]

        if beta_rows.empty:
            continue

        # Alpha: observed vs expected
        n_alpha_observed = len(alpha_rows)
        n_alpha_expected = EXPECTED_ALPHA_ATTEMPTS
        n_alpha_failed = n_alpha_expected - n_alpha_observed

        # Beta: observed vs expected
        n_beta_observed = len(beta_rows)
        n_beta_expected = EXPECTED_BETA_ATTEMPTS
        n_beta_failed = n_beta_expected - n_beta_observed

        # --- Primary outcome: end-to-end success rate (F1 >= threshold) ---
        alpha_successes = (alpha_rows["F1"] >= F1_SUCCESS_THRESHOLD).sum() if n_alpha_observed > 0 else 0
        beta_successes = (beta_rows["F1"] >= F1_SUCCESS_THRESHOLD).sum() if n_beta_observed > 0 else 0

        alpha_success_rate = alpha_successes / n_alpha_expected
        beta_success_rate = beta_successes / n_beta_expected

        # Fisher's exact test on success counts (only meaningful when both have >1 expected)
        if n_alpha_expected > 1 and n_beta_expected > 1:
            table = [[alpha_successes, n_alpha_expected - alpha_successes],
                     [beta_successes, n_beta_expected - beta_successes]]
            _, fisher_p = stats.fisher_exact(table)
        else:
            fisher_p = np.nan

        # --- Secondary A: SQL execution rate + mean F1 among executed ---
        alpha_exec_rate = n_alpha_observed / n_alpha_expected
        beta_exec_rate = n_beta_observed / n_beta_expected

        alpha_f1_executed = alpha_rows["F1"].dropna().values if n_alpha_observed > 0 else np.array([])
        beta_f1_executed = beta_rows["F1"].dropna().values if n_beta_observed > 0 else np.array([])

        alpha_mean_f1_exec = np.nanmean(alpha_f1_executed) if len(alpha_f1_executed) > 0 else np.nan
        beta_mean_f1_exec = np.nanmean(beta_f1_executed) if len(beta_f1_executed) > 0 else np.nan

        # PPV and FPR only among executed outputs
        alpha_mean_ppv = alpha_rows["PPV"].mean() if n_alpha_observed > 0 else np.nan
        alpha_mean_fpr = alpha_rows["FPR"].mean() if n_alpha_observed > 0 else np.nan
        beta_mean_ppv = beta_rows["PPV"].mean() if n_beta_observed > 0 else np.nan
        beta_mean_fpr = beta_rows["FPR"].mean() if n_beta_observed > 0 else np.nan
        alpha_mean_recall = alpha_rows["Recall"].mean() if n_alpha_observed > 0 else np.nan
        beta_mean_recall = beta_rows["Recall"].mean() if n_beta_observed > 0 else np.nan

        # --- Secondary B: Penalized mean F1 (F1=0 for missing outputs) ---
        alpha_f1_penalized = np.concatenate([alpha_f1_executed, np.zeros(n_alpha_failed)])
        beta_f1_penalized = np.concatenate([beta_f1_executed, np.zeros(n_beta_failed)])

        alpha_penalized_mean_f1 = np.mean(alpha_f1_penalized)
        beta_penalized_mean_f1 = np.mean(beta_f1_penalized)

        # --- Statistical comparison ---
        # Mann-Whitney on penalized F1 (alpha has 5 values, beta has 1 - descriptive only)
        # Only run test if both have >= 2 observations with variance
        if len(alpha_f1_penalized) >= 3 and len(beta_f1_penalized) >= 2:
            mw_stat, mw_p = stats.mannwhitneyu(alpha_f1_penalized, beta_f1_penalized, alternative="two-sided")
        else:
            mw_stat, mw_p = np.nan, np.nan

        # For descriptive comparison when beta=1: report difference and CI of alpha mean
        alpha_f1_std = np.std(alpha_f1_penalized, ddof=1) if len(alpha_f1_penalized) > 1 else np.nan
        alpha_f1_se = alpha_f1_std / np.sqrt(len(alpha_f1_penalized)) if not np.isnan(alpha_f1_std) else np.nan

        alpha_beta_results.append({
            "model": model,
            "model_display": MODEL_DISPLAY_NAMES.get(model, model),
            "context_level": cl,
            # Counts
            "alpha_expected": n_alpha_expected,
            "alpha_executed": n_alpha_observed,
            "alpha_failed": n_alpha_failed,
            "beta_expected": n_beta_expected,
            "beta_executed": n_beta_observed,
            "beta_failed": n_beta_failed,
            # Primary: end-to-end success rate
            "alpha_successes_F1_ge_80": int(alpha_successes),
            "beta_successes_F1_ge_80": int(beta_successes),
            "alpha_success_rate": alpha_success_rate,
            "beta_success_rate": beta_success_rate,
            "diff_success_rate": alpha_success_rate - beta_success_rate,
            "fisher_p": fisher_p,
            # Secondary A: execution rate + mean F1 among executed
            "alpha_exec_rate": alpha_exec_rate,
            "beta_exec_rate": beta_exec_rate,
            "alpha_mean_F1_executed": alpha_mean_f1_exec,
            "beta_mean_F1_executed": beta_mean_f1_exec,
            "alpha_mean_PPV": alpha_mean_ppv,
            "beta_mean_PPV": beta_mean_ppv,
            "alpha_mean_Recall": alpha_mean_recall,
            "beta_mean_Recall": beta_mean_recall,
            "alpha_mean_FPR": alpha_mean_fpr,
            "beta_mean_FPR": beta_mean_fpr,
            # Secondary B: penalized mean F1
            "alpha_penalized_mean_F1": alpha_penalized_mean_f1,
            "beta_penalized_mean_F1": beta_penalized_mean_f1,
            "diff_penalized_F1": alpha_penalized_mean_f1 - beta_penalized_mean_f1,
            "alpha_penalized_std_F1": alpha_f1_std,
            "alpha_penalized_se_F1": alpha_f1_se,
            # Test (descriptive when beta n=1)
            "mann_whitney_U": mw_stat,
            "mann_whitney_p": mw_p,
            "test_note": "descriptive only (beta n=1)" if n_beta_expected == 1 else "Mann-Whitney U",
        })

alpha_beta_df = pd.DataFrame(alpha_beta_results)
alpha_beta_df.to_csv(OUTPUT_DIR / "analysis1c_alpha_vs_beta.csv", index=False)

# --- Aggregate summaries across all comparisons ---
ab_valid = alpha_beta_df[alpha_beta_df["beta_executed"] > 0]

# Primary: how often does alpha achieve >= 80% success rate vs beta?
total_alpha_successes = ab_valid["alpha_successes_F1_ge_80"].sum()
total_alpha_expected = ab_valid["alpha_expected"].sum()
total_beta_successes = ab_valid["beta_successes_F1_ge_80"].sum()
total_beta_expected = ab_valid["beta_expected"].sum()

overall_alpha_success_rate = total_alpha_successes / total_alpha_expected if total_alpha_expected > 0 else np.nan
overall_beta_success_rate = total_beta_successes / total_beta_expected if total_beta_expected > 0 else np.nan

# Fisher's exact on aggregated counts
if total_alpha_expected > 0 and total_beta_expected > 0:
    agg_table = [[total_alpha_successes, total_alpha_expected - total_alpha_successes],
                 [total_beta_successes, total_beta_expected - total_beta_successes]]
    _, agg_fisher_p = stats.fisher_exact(agg_table)
else:
    agg_fisher_p = np.nan

# Secondary A aggregate
total_alpha_executed = ab_valid["alpha_executed"].sum()
total_beta_executed = ab_valid["beta_executed"].sum()
overall_alpha_exec_rate = total_alpha_executed / total_alpha_expected if total_alpha_expected > 0 else np.nan
overall_beta_exec_rate = total_beta_executed / total_beta_expected if total_beta_expected > 0 else np.nan

# Mean F1 among executed (weighted by count)
alpha_exec_f1s = df[(df["family"] == "alpha")]["F1"].dropna().values
beta_exec_f1s = df[(df["family"] == "beta")]["F1"].dropna().values

print(f"  PRIMARY: End-to-end success rate (F1 >= {F1_SUCCESS_THRESHOLD})")
print(f"    Alpha: {total_alpha_successes}/{total_alpha_expected} = {overall_alpha_success_rate:.1%}")
print(f"    Beta:  {total_beta_successes}/{total_beta_expected} = {overall_beta_success_rate:.1%}")
print(f"    Fisher's exact (aggregated): p={agg_fisher_p:.4f}")
print(f"  SECONDARY A: SQL execution rate")
print(f"    Alpha: {total_alpha_executed}/{total_alpha_expected} = {overall_alpha_exec_rate:.1%}")
print(f"    Beta:  {total_beta_executed}/{total_beta_expected} = {overall_beta_exec_rate:.1%}")
print(f"    Mean F1 among executed - Alpha: {np.nanmean(alpha_exec_f1s):.4f}, Beta: {np.nanmean(beta_exec_f1s):.4f}")
print(f"  SECONDARY B: Penalized mean F1 (F1=0 for failures)")
print(f"    Alpha: {ab_valid['alpha_penalized_mean_F1'].mean():.4f}")
print(f"    Beta:  {ab_valid['beta_penalized_mean_F1'].mean():.4f}")

# =============================================================================
# 3. Analysis 2: Context-level progression (b0 < b1/b2 < b4)
#    Since b1/b2 are two versions at the same context level, we treat
#    the best of b1/b2 (or their average) as the "context=1/2" performance.
#    Then test: b0 < b1/b2 < b4
# =============================================================================

print("\nAnalysis 2: Context-level progression (b0 < b1/b2 < b4)...")

beta_progression_results = []

for model in df["model"].unique():
    beta_rows = df[(df["model"] == model) & (df["family"] == "beta")]
    if beta_rows.empty:
        continue

    b0_row = beta_rows[beta_rows["context_level"] == "0"]
    b1_row = beta_rows[beta_rows["context_level"] == "1"]
    b2_row = beta_rows[beta_rows["context_level"] == "2"]
    b4_row = beta_rows[beta_rows["context_level"] == "4"]

    metrics_by_tier = {}
    for metric in COMPARISON_METRICS:
        b0_val = b0_row[metric].values[0] if not b0_row.empty else np.nan
        b1_val = b1_row[metric].values[0] if not b1_row.empty else np.nan
        b2_val = b2_row[metric].values[0] if not b2_row.empty else np.nan
        b4_val = b4_row[metric].values[0] if not b4_row.empty else np.nan

        # Average of b1/b2 as "mid-context" tier
        mid_vals = [v for v in [b1_val, b2_val] if not np.isnan(v)]
        mid_val = np.mean(mid_vals) if mid_vals else np.nan

        metrics_by_tier[metric] = {"b0": b0_val, "b1": b1_val, "b2": b2_val, "mid": mid_val, "b4": b4_val}

    f1_tiers = metrics_by_tier["F1"]
    tier_vals = []
    tier_labels = []
    for label, key in [("b0", "b0"), ("mid(b1/b2)", "mid"), ("b4", "b4")]:
        if not np.isnan(f1_tiers[key]):
            tier_vals.append(f1_tiers[key])
            tier_labels.append(label)

    monotonic = all(tier_vals[i] <= tier_vals[i+1] for i in range(len(tier_vals)-1)) if len(tier_vals) >= 2 else None

    if len(tier_vals) >= 3:
        tau, p_kendall = stats.kendalltau(range(len(tier_vals)), tier_vals)
    else:
        tau, p_kendall = np.nan, np.nan

    beta_progression_results.append({
        "model": model,
        "model_display": MODEL_DISPLAY_NAMES.get(model, model),
        "tiers_available": " < ".join(tier_labels),
        "F1_tiers": " < ".join([f"{l}={v:.4f}" for l, v in zip(tier_labels, tier_vals)]),
        "monotonic_F1": monotonic,
        "kendall_tau": tau,
        "kendall_p": p_kendall,
        **{f"F1_{k}": v for k, v in f1_tiers.items()},
        **{f"PPV_{k}": metrics_by_tier["PPV"][k] for k in f1_tiers},
        **{f"Recall_{k}": metrics_by_tier["Recall"][k] for k in f1_tiers},
        **{f"FPR_{k}": metrics_by_tier["FPR"][k] for k in f1_tiers},
    })

beta_prog_df = pd.DataFrame(beta_progression_results)
beta_prog_df.to_csv(OUTPUT_DIR / "analysis2_context_progression.csv", index=False)

n_monotonic = beta_prog_df["monotonic_F1"].sum() if not beta_prog_df.empty else 0
n_total_prog = beta_prog_df["monotonic_F1"].notna().sum()
print(f"  Monotonically increasing F1 (b0 < mid < b4): {n_monotonic}/{n_total_prog} models")

# Wilcoxon signed-rank tests for pairwise context tiers
tier_pairs = [("b0", "mid", "b0 vs b1/b2"), ("mid", "b4", "b1/b2 vs b4"), ("b0", "b4", "b0 vs b4")]
tier_test_results = []

for lower_key, upper_key, label in tier_pairs:
    paired = beta_prog_df[[f"F1_{lower_key}", f"F1_{upper_key}"]].dropna()
    if len(paired) >= 5:
        w_stat, w_p = stats.wilcoxon(paired[f"F1_{lower_key}"], paired[f"F1_{upper_key}"])
    elif len(paired) >= 2:
        w_stat, w_p = stats.wilcoxon(paired[f"F1_{lower_key}"], paired[f"F1_{upper_key}"])
    else:
        w_stat, w_p = np.nan, np.nan

    n_improved = (paired[f"F1_{upper_key}"] > paired[f"F1_{lower_key}"]).sum()
    n_pair = len(paired)

    tier_test_results.append({
        "comparison": label,
        "n_models": n_pair,
        "n_improved": int(n_improved),
        "wilcoxon_W": w_stat,
        "wilcoxon_p": w_p,
    })
    if not np.isnan(w_p):
        print(f"    {label}: improved in {n_improved}/{n_pair} models, Wilcoxon p={w_p:.4f}")
    else:
        print(f"    {label}: improved in {n_improved}/{n_pair} models (too few for Wilcoxon)")

tier_tests_df = pd.DataFrame(tier_test_results)
tier_tests_df.to_csv(OUTPUT_DIR / "analysis2_tier_tests.csv", index=False)

# Friedman test across models that have all 3 tiers
full_tier_models = beta_prog_df.dropna(subset=["F1_b0", "F1_mid", "F1_b4"])
if len(full_tier_models) >= 3:
    friedman_stat, friedman_p = stats.friedmanchisquare(
        full_tier_models["F1_b0"], full_tier_models["F1_mid"], full_tier_models["F1_b4"]
    )
    print(f"  Friedman test (F1 across b0/mid/b4): chi2={friedman_stat:.3f}, p={friedman_p:.4f}")
else:
    friedman_stat, friedman_p = np.nan, np.nan
    print("  Friedman test: not enough models with all 3 tiers")

# =============================================================================
# 4. Analysis 3: Model ranking (including execution rate)
# =============================================================================

print("Analysis 3: Model comparison and ranking...")

# Expected attempts per model: 5 alpha * 4 context levels + 1 beta * 4 context levels = 24
# But not all context levels apply to all models, so compute per model from data
EXPECTED_ALPHA_PER_CONTEXT = 5
EXPECTED_BETA_PER_CONTEXT = 1

model_ranking_results = []

for model in df["model"].unique():
    model_df = df[df["model"] == model]
    beta_df_m = model_df[model_df["family"] == "beta"]
    alpha_df_m = model_df[model_df["family"] == "alpha"]

    # Determine which context levels this model attempted
    # Beta always available tells us which contexts were attempted
    beta_contexts = beta_df_m["context_level"].unique()
    alpha_contexts = alpha_df_m["context_level"].unique()
    all_contexts = set(beta_contexts) | set(alpha_contexts)

    # Expected total attempts
    n_expected_alpha = len(all_contexts) * EXPECTED_ALPHA_PER_CONTEXT
    n_expected_beta = len(beta_contexts) * EXPECTED_BETA_PER_CONTEXT
    n_expected_total = n_expected_alpha + n_expected_beta

    # Observed
    n_executed_alpha = len(alpha_df_m)
    n_executed_beta = len(beta_df_m)
    n_executed_total = len(model_df)

    # Execution rates
    exec_rate_alpha = n_executed_alpha / n_expected_alpha if n_expected_alpha > 0 else np.nan
    exec_rate_beta = n_executed_beta / n_expected_beta if n_expected_beta > 0 else np.nan
    exec_rate_total = n_executed_total / n_expected_total if n_expected_total > 0 else np.nan

    # Success rate (F1 >= 0.80)
    n_success_total = (model_df["F1"] >= F1_SUCCESS_THRESHOLD).sum()
    n_success_alpha = (alpha_df_m["F1"] >= F1_SUCCESS_THRESHOLD).sum()
    n_success_beta = (beta_df_m["F1"] >= F1_SUCCESS_THRESHOLD).sum()
    success_rate_total = n_success_total / n_expected_total if n_expected_total > 0 else np.nan

    # Penalized mean F1 (assign 0 to missing/failed attempts)
    alpha_f1_penalized = np.concatenate([alpha_df_m["F1"].dropna().values, np.zeros(n_expected_alpha - n_executed_alpha)])
    beta_f1_penalized = np.concatenate([beta_df_m["F1"].dropna().values, np.zeros(n_expected_beta - n_executed_beta)])
    all_f1_penalized = np.concatenate([alpha_f1_penalized, beta_f1_penalized])
    penalized_mean_f1 = np.mean(all_f1_penalized) if len(all_f1_penalized) > 0 else np.nan

    model_ranking_results.append({
        "model": model,
        "model_display": MODEL_DISPLAY_NAMES.get(model, model),
        # Counts
        "n_expected_total": n_expected_total,
        "n_executed_total": n_executed_total,
        "n_expected_alpha": n_expected_alpha,
        "n_executed_alpha": n_executed_alpha,
        "n_expected_beta": n_expected_beta,
        "n_executed_beta": n_executed_beta,
        # Execution rates
        "exec_rate_total": exec_rate_total,
        "exec_rate_alpha": exec_rate_alpha,
        "exec_rate_beta": exec_rate_beta,
        # Success rates (F1 >= threshold)
        "n_success_total": int(n_success_total),
        "success_rate_total": success_rate_total,
        "n_success_alpha": int(n_success_alpha),
        "n_success_beta": int(n_success_beta),
        # F1 metrics
        "mean_F1_executed": model_df["F1"].mean(),
        "mean_F1_beta_executed": beta_df_m["F1"].mean() if not beta_df_m.empty else np.nan,
        "penalized_mean_F1": penalized_mean_f1,
        "best_F1": model_df["F1"].max(),
        "best_prompt": model_df.loc[model_df["F1"].idxmax(), "prompt"] if not model_df.empty else None,
        # Other metrics (executed only)
        "mean_PPV_beta": beta_df_m["PPV"].mean() if not beta_df_m.empty else np.nan,
        "mean_Recall_beta": beta_df_m["Recall"].mean() if not beta_df_m.empty else np.nan,
        "mean_FPR_beta": beta_df_m["FPR"].mean() if not beta_df_m.empty else np.nan,
        "F1_b4": model_df.loc[model_df["prompt"] == "b4", "F1"].values[0] if not model_df[model_df["prompt"] == "b4"].empty else np.nan,
    })

ranking_df = pd.DataFrame(model_ranking_results).sort_values("penalized_mean_F1", ascending=False).reset_index(drop=True)
ranking_df["rank"] = range(1, len(ranking_df) + 1)
ranking_df.to_csv(OUTPUT_DIR / "analysis3_model_ranking.csv", index=False)

print("  Model ranking (by penalized mean F1, accounting for execution failures):")
for _, row in ranking_df.iterrows():
    print(f"    {row['rank']}. {row['model_display']:<22} "
          f"pen_F1={row['penalized_mean_F1']:.4f}  "
          f"exec={row['n_executed_total']}/{row['n_expected_total']} ({row['exec_rate_total']:.0%})  "
          f"success={row['n_success_total']}/{row['n_expected_total']} ({row['success_rate_total']:.0%})  "
          f"F1|exec={row['mean_F1_executed']:.4f}  "
          f"(best: {row['best_prompt']} F1={row['best_F1']:.4f})")

# Kruskal-Wallis test comparing models on beta F1
beta_only = df[df["family"] == "beta"]
groups = [g["F1"].dropna().values for _, g in beta_only.groupby("model") if len(g) >= 2]
if len(groups) >= 2:
    kw_stat, kw_p = stats.kruskal(*groups)
    print(f"  Kruskal-Wallis test (F1 across models, beta only): H={kw_stat:.3f}, p={kw_p:.4f}")
else:
    kw_stat, kw_p = np.nan, np.nan

# Pairwise Mann-Whitney U tests between top models (on beta prompts)
pairwise_model_results = []
models_sorted = ranking_df["model"].tolist()
for i, m1 in enumerate(models_sorted):
    for m2 in models_sorted[i+1:]:
        g1 = beta_only[beta_only["model"] == m1]["F1"].dropna().values
        g2 = beta_only[beta_only["model"] == m2]["F1"].dropna().values
        if len(g1) >= 2 and len(g2) >= 2:
            u_stat, u_p = stats.mannwhitneyu(g1, g2, alternative="two-sided")
        else:
            u_stat, u_p = np.nan, np.nan
        pairwise_model_results.append({
            "model_1": MODEL_DISPLAY_NAMES.get(m1, m1),
            "model_2": MODEL_DISPLAY_NAMES.get(m2, m2),
            "mean_F1_model1": np.nanmean(g1),
            "mean_F1_model2": np.nanmean(g2),
            "U_statistic": u_stat,
            "p_value": u_p,
            "significant_0.05": u_p < 0.05 if not np.isnan(u_p) else None,
        })

pairwise_df = pd.DataFrame(pairwise_model_results)
pairwise_df.to_csv(OUTPUT_DIR / "analysis3_pairwise_model_tests.csv", index=False)

# =============================================================================
# 5. Visualizations
# =============================================================================

print("\nGenerating visualizations...")

sns.set_theme(style="whitegrid", font_scale=1.1)
COLORS = sns.color_palette("tab10", n_colors=len(MODEL_DISPLAY_NAMES))
model_color_map = {m: COLORS[i] for i, m in enumerate(sorted(MODEL_DISPLAY_NAMES.keys()))}

# --- Fig 1: Model ranking (beta mean F1) ---
fig1_ranking = ranking_df.sort_values("mean_F1_beta_executed", ascending=False).reset_index(drop=True)
fig, ax = plt.subplots(figsize=(10, 6))
bars = ax.barh(
    fig1_ranking["model_display"],
    fig1_ranking["mean_F1_beta_executed"],
    color=[model_color_map.get(m, "gray") for m in fig1_ranking["model"]],
    edgecolor="black", linewidth=0.5
)
ax.set_xlabel("Mean F1 (Beta Prompts)")
ax.set_title("Model Ranking: Beta F1")
ax.invert_yaxis()
for bar, val in zip(bars, fig1_ranking["mean_F1_beta_executed"]):
    if not np.isnan(val):
        ax.text(val + 0.005, bar.get_y() + bar.get_height()/2, f"{val:.3f}", va="center", fontsize=9)
ax.set_xlim(0, min(1.0, fig1_ranking["mean_F1_beta_executed"].max() + 0.08))

plt.tight_layout()
plt.savefig(OUTPUT_DIR / "fig1_model_ranking.png", dpi=150)
plt.close()

# --- Fig 2: Context-level progression line plot (b0, mid(b1/b2), b4) ---
fig, axes = plt.subplots(2, 2, figsize=(14, 10))
metrics_to_plot = [("F1", "F1 Score"), ("PPV", "Precision (PPV)"), ("Recall", "Recall (Sensitivity)"), ("FPR", "False Positive Rate")]
tier_keys = ["b0", "mid", "b4"]
tier_labels_x = ["b0\n(zero-shot)", "b1/b2\n(mid-context)", "b4\n(full context)"]

for ax, (metric, label) in zip(axes.flat, metrics_to_plot):
    for _, row in beta_prog_df.iterrows():
        vals = [row.get(f"{metric}_{k}", np.nan) for k in tier_keys]
        available = [(i, v) for i, v in enumerate(vals) if not np.isnan(v)]
        if available:
            x_idx, y = zip(*available)
            ax.plot([tier_labels_x[i] for i in x_idx], y, marker="o", label=row["model_display"],
                    color=model_color_map.get(row["model"], "gray"), linewidth=2, markersize=6)
    ax.set_xlabel("Context Level")
    ax.set_ylabel(label)
    ax.set_title(f"{label} by Context Level")
    if metric == "FPR":
        ax.set_title(f"{label} by Context Level (lower is better)")

handles, labels = axes[0, 0].get_legend_handles_labels()
fig.legend(handles, labels, loc="lower center", ncol=4, bbox_to_anchor=(0.5, -0.02), fontsize=9)
plt.tight_layout(rect=[0, 0.08, 1, 1])
plt.savefig(OUTPUT_DIR / "fig2_beta_progression.png", dpi=150, bbox_inches="tight")
plt.close()

# --- Fig 3: Alpha vs Beta - two-panel publication figure ---
if not alpha_beta_df.empty:
    fig, axes = plt.subplots(1, 2, figsize=(14, max(6, len(alpha_beta_df) * 0.35)))
    plot_data = alpha_beta_df.copy()
    plot_data["label"] = plot_data["model_display"] + " (ctx=" + plot_data["context_level"] + ")"

    # Recompute success rate with 0.75 threshold for fig3
    fig3_threshold = 0.75
    plot_data["alpha_success_rate_75"] = plot_data.apply(
        lambda r: r["alpha_successes_F1_ge_80"] / r["alpha_expected"] if r["alpha_expected"] > 0 else np.nan, axis=1)
    plot_data["beta_success_rate_75"] = plot_data.apply(
        lambda r: r["beta_successes_F1_ge_80"] / r["beta_expected"] if r["beta_expected"] > 0 else np.nan, axis=1)
    # Recompute with 0.75 threshold from raw data
    for idx, row in plot_data.iterrows():
        model = row["model"]
        cl = row["context_level"]
        alpha_rows = df[(df["model"] == model) & (df["family"] == "alpha") & (df["context_level"] == cl)]
        beta_rows = df[(df["model"] == model) & (df["family"] == "beta") & (df["context_level"] == cl)]
        plot_data.at[idx, "alpha_success_rate_75"] = (alpha_rows["F1"] >= fig3_threshold).sum() / EXPECTED_ALPHA_ATTEMPTS
        plot_data.at[idx, "beta_success_rate_75"] = (beta_rows["F1"] >= fig3_threshold).sum() / EXPECTED_BETA_ATTEMPTS if not beta_rows.empty else 0

    # Panel A: End-to-end success rate (F1 >= 0.75)
    ax = axes[0]
    x = np.arange(len(plot_data))
    w = 0.35
    ax.barh(x - w/2, plot_data["alpha_success_rate_75"], w, label="Alpha (5 attempts)", color="steelblue", edgecolor="black", linewidth=0.5)
    ax.barh(x + w/2, plot_data["beta_success_rate_75"], w, label="Beta (1 attempt)", color="coral", edgecolor="black", linewidth=0.5)
    ax.set_yticks(x)
    ax.set_yticklabels(plot_data["label"], fontsize=8)
    ax.set_xlabel(f"Success Rate (F1 >= {fig3_threshold})")
    ax.set_title(f"Primary: End-to-End Success Rate (F1 >= {fig3_threshold})")
    ax.set_xlim(0, 1.05)
    ax.legend(fontsize=8)
    ax.invert_yaxis()

    # Panel B: Mean F1 (executed runs only)
    ax = axes[1]
    ax.barh(x - w/2, plot_data["alpha_mean_F1_executed"], w, label="Alpha", color="steelblue", edgecolor="black", linewidth=0.5)
    ax.barh(x + w/2, plot_data["beta_mean_F1_executed"], w, label="Beta", color="coral", edgecolor="black", linewidth=0.5)
    ax.set_yticks(x)
    ax.set_yticklabels(plot_data["label"], fontsize=8)
    ax.set_xlabel("Mean F1 (executed runs)")
    ax.set_title("Mean F1 (Executed Runs Only)")
    ax.set_xlim(0, 1.05)
    ax.legend(fontsize=8)
    ax.invert_yaxis()

    plt.tight_layout()
    plt.savefig(OUTPUT_DIR / "fig3_alpha_vs_beta.png", dpi=150)
    plt.close()

# --- Fig 4_2: Heatmaps with beta as merged single-cell row below alpha ---

heatmap_metrics_4_2 = [
    ("F1", "RdYlGn", "F1 Score Heatmap: Model x Prompt (beta below alpha)", "fig4_2_f1_heatmap.png"),
    ("PPV", "RdYlGn", "PPV (Precision) Heatmap: Model x Prompt (beta below alpha)", "fig4_2_ppv_heatmap.png"),
    ("Recall", "RdYlGn", "Recall (Sensitivity) Heatmap: Model x Prompt (beta below alpha)", "fig4_2_recall_heatmap.png"),
    ("FPR", "RdYlGn_r", "FPR Heatmap: Model x Prompt (beta below alpha, lower is better)", "fig4_2_fpr_heatmap.png"),
]

for metric, cmap_name, title, filename in heatmap_metrics_4_2:
    pivot_data = df.pivot_table(index="model_display", columns="prompt", values=metric, aggfunc="mean")

    # Alpha column order and context-level grouping info
    alpha_col_order = []
    context_groups = []  # list of (context_level, start_col_idx, n_cols)
    for cl in CONTEXT_LEVELS:
        cols_cl = []
        for p in range(1, 6):
            col = f"a{cl}p{p}"
            if col in pivot_data.columns:
                cols_cl.append(col)
        if cols_cl:
            context_groups.append((cl, len(alpha_col_order), len(cols_cl)))
            alpha_col_order.extend(cols_cl)

    n_alpha_cols = len(alpha_col_order)
    model_list = sorted(pivot_data.index.tolist())
    n_models = len(model_list)

    # Each model gets 2 rows: alpha (row 0) + beta (row 1)
    n_rows = n_models * 2

    # Build alpha data matrix (models x alpha_cols)
    alpha_matrix = np.full((n_models, n_alpha_cols), np.nan)
    for i, model_name in enumerate(model_list):
        for j, col in enumerate(alpha_col_order):
            if col in pivot_data.columns:
                alpha_matrix[i, j] = pivot_data.loc[model_name, col]

    # Get beta values per model per context level
    beta_values = {}  # (model_idx, context_level) -> value
    for i, model_name in enumerate(model_list):
        for cl in CONTEXT_LEVELS:
            bcol = f"b{cl}"
            if bcol in pivot_data.columns:
                beta_values[(i, cl)] = pivot_data.loc[model_name, bcol]
            else:
                beta_values[(i, cl)] = np.nan

    vmin = 0
    vmax = 1 if metric != "FPR" else np.nanmax(alpha_matrix)
    bmax = max((v for v in beta_values.values() if not np.isnan(v)), default=vmax)
    vmax = max(vmax, bmax) if not np.isnan(bmax) else vmax

    cmap_obj = cm.get_cmap(cmap_name)
    norm = Normalize(vmin=vmin, vmax=vmax)

    fig_height = max(8, n_rows * 0.38)
    fig_width = max(14, n_alpha_cols * 0.6)
    fig, ax = plt.subplots(figsize=(fig_width, fig_height))

    # Draw alpha cells
    for i in range(n_models):
        row_y = i * 2  # alpha row position (from top)
        for j in range(n_alpha_cols):
            val = alpha_matrix[i, j]
            if not np.isnan(val):
                color = cmap_obj(norm(val))
            else:
                color = "white"
            rect = Rectangle((j, row_y), 1, 1, facecolor=color, edgecolor="gray", linewidth=0.5)
            ax.add_patch(rect)
            if not np.isnan(val):
                ax.text(j + 0.5, row_y + 0.5, f"{val:.3f}", ha="center", va="center", fontsize=10)

    # Draw beta cells (merged across each context-level group)
    for i in range(n_models):
        row_y = i * 2 + 1  # beta row position
        for cl, start_col, n_cols in context_groups:
            val = beta_values.get((i, cl), np.nan)
            if not np.isnan(val):
                color = cmap_obj(norm(val))
            else:
                color = "white"
            rect = Rectangle((start_col, row_y), n_cols, 1, facecolor=color, edgecolor="gray", linewidth=0.5)
            ax.add_patch(rect)
            if not np.isnan(val):
                ax.text(start_col + n_cols / 2, row_y + 0.5, f"{val:.3f}",
                        ha="center", va="center", fontsize=10)

    ax.set_xlim(0, n_alpha_cols)
    ax.set_ylim(0, n_rows)
    ax.invert_yaxis()

    # Y-axis: model labels centered on their 2-row block
    y_ticks = []
    y_labels = []
    for i, model_name in enumerate(model_list):
        y_ticks.append(i * 2 + 0.5)
        y_labels.append(f"{model_name} (α)")
        y_ticks.append(i * 2 + 1.5)
        y_labels.append(f"{model_name} (β)")
    ax.set_yticks(y_ticks)
    ax.set_yticklabels(y_labels, fontsize=11)

    # X-axis top: alpha prompt labels (kept horizontal, not rotated)
    ax.set_xticks([j + 0.5 for j in range(n_alpha_cols)])
    ax.set_xticklabels(alpha_col_order, fontsize=10, rotation=0, ha="center")
    ax.xaxis.set_ticks_position("top")
    ax.xaxis.set_label_position("top")

    # X-axis bottom: beta labels (b0, b1, b2, b4) centered under their context group
    ax2 = ax.secondary_xaxis("bottom")
    beta_tick_positions = []
    beta_tick_labels = []
    for cl, start_col, n_cols in context_groups:
        beta_tick_positions.append(start_col + n_cols / 2)
        beta_tick_labels.append(f"b{cl}")
    ax2.set_xticks(beta_tick_positions)
    ax2.set_xticklabels(beta_tick_labels, fontsize=12)
    ax2.tick_params(length=0)

    # Horizontal lines to separate model groups
    for i in range(1, n_models):
        ax.axhline(i * 2, color="black", linewidth=1.5)

    # Vertical lines between context level groups
    for cl, start_col, n_cols in context_groups:
        end_col = start_col + n_cols
        if end_col < n_alpha_cols:
            ax.axvline(end_col, color="black", linewidth=1.5)

    # Colorbar
    sm = cm.ScalarMappable(cmap=cmap_obj, norm=norm)
    sm.set_array([])
    cbar = plt.colorbar(sm, ax=ax, fraction=0.02, pad=0.02)
    cbar.set_label(metric)

    ax.set_title(title, pad=40)
    plt.tight_layout()
    plt.savefig(OUTPUT_DIR / filename, dpi=150)
    plt.close()

# --- Fig 5: Best F1 per model with error bars (beta prompts) ---
beta_summary = beta_only.groupby("model_display").agg(
    mean_F1=("F1", "mean"), std_F1=("F1", "std"), n=("F1", "count")
).reset_index().sort_values("mean_F1", ascending=False)
beta_summary["se_F1"] = beta_summary["std_F1"] / np.sqrt(beta_summary["n"])

fig, ax = plt.subplots(figsize=(10, 6))
ax.barh(beta_summary["model_display"], beta_summary["mean_F1"],
        xerr=beta_summary["se_F1"], capsize=4,
        color="steelblue", edgecolor="black", linewidth=0.5, alpha=0.8)
ax.set_xlabel("Mean F1 (Beta Prompts) ± SE")
ax.set_title("Model Comparison: Beta Prompt F1 with Standard Error")
ax.invert_yaxis()
ax.set_xlim(0, 1.0)
plt.tight_layout()
plt.savefig(OUTPUT_DIR / "fig5_model_comparison_with_se.png", dpi=150)
plt.close()

# --- Fig 6: Recall vs PPV scatter (all prompts) ---
fig, ax = plt.subplots(figsize=(10, 8))
for model in df["model"].unique():
    mdf = df[df["model"] == model]
    ax.scatter(mdf["Recall"], mdf["PPV"], label=MODEL_DISPLAY_NAMES.get(model, model),
               color=model_color_map.get(model, "gray"), s=60, alpha=0.7, edgecolors="black", linewidth=0.3)
ax.set_xlabel("Recall (Sensitivity)")
ax.set_ylabel("PPV (Precision)")
ax.set_title("Precision-Recall Space by Model")
ax.set_xlim(0, 1.05)
ax.set_ylim(0, 1.05)
ax.plot([0, 1], [0, 1], "--", color="gray", alpha=0.5)
ax.legend(loc="lower right", fontsize=9)
plt.tight_layout()
plt.savefig(OUTPUT_DIR / "fig6_recall_vs_ppv.png", dpi=150)
plt.close()

# --- Fig 6a: Recall vs PPV scatter (alpha only) ---
alpha_only = df[df["family"] == "alpha"]
fig, ax = plt.subplots(figsize=(10, 8))
for model in alpha_only["model"].unique():
    mdf = alpha_only[alpha_only["model"] == model]
    ax.scatter(mdf["Recall"], mdf["PPV"], label=MODEL_DISPLAY_NAMES.get(model, model),
               color=model_color_map.get(model, "gray"), s=60, alpha=0.7, edgecolors="black", linewidth=0.3)
ax.set_xlabel("Recall (Sensitivity)")
ax.set_ylabel("PPV (Precision)")
ax.set_title("Precision-Recall Space by Model (Alpha Prompts Only)")
ax.set_xlim(0, 1.05)
ax.set_ylim(0, 1.05)
ax.plot([0, 1], [0, 1], "--", color="gray", alpha=0.5)
ax.legend(loc="lower right", fontsize=9)
plt.tight_layout()
plt.savefig(OUTPUT_DIR / "fig6a_recall_vs_ppv_alpha.png", dpi=150)
plt.close()

# --- Fig 6b: Recall vs PPV scatter (beta only, marker shape = context level) ---
CONTEXT_MARKERS = {"0": "o", "1": "s", "2": "^", "4": "D"}  # circle, square, triangle, diamond
CONTEXT_MARKER_LABELS = {"0": "v0 (zero-shot)", "1": "v1", "2": "v2", "4": "v4 (full)"}

fig, ax = plt.subplots(figsize=(10, 8))
model_handles = []
plotted_models = set()
plotted_contexts = set()
for model in beta_only["model"].unique():
    for cl, marker in CONTEXT_MARKERS.items():
        mdf = beta_only[(beta_only["model"] == model) & (beta_only["context_level"] == cl)]
        if mdf.empty:
            continue
        ax.scatter(mdf["Recall"], mdf["PPV"],
                   color=model_color_map.get(model, "gray"), marker=marker,
                   s=40, alpha=0.8, edgecolors="black", linewidth=0.4)
        if model not in plotted_models:
            h = ax.scatter([], [], marker="o", color=model_color_map.get(model, "gray"),
                           s=50, edgecolors="black", linewidth=0.4,
                           label=MODEL_DISPLAY_NAMES.get(model, model))
            model_handles.append(h)
            plotted_models.add(model)
        plotted_contexts.add(cl)

# Context-level shape handles
context_handles = []
for cl, marker in CONTEXT_MARKERS.items():
    if cl in plotted_contexts:
        h = ax.scatter([], [], marker=marker, color="gray", s=50, edgecolors="black", linewidth=0.4,
                       label=CONTEXT_MARKER_LABELS[cl])
        context_handles.append(h)

ax.set_xlabel("Recall (Sensitivity)")
ax.set_ylabel("PPV (Precision)")
ax.set_title("Precision-Recall Space by Model (Beta Prompts Only)")
ax.set_xlim(0, 1.05)
ax.set_ylim(0, 1.05)
ax.plot([0, 1], [0, 1], "--", color="gray", alpha=0.5)

# Combined legend: models then context shapes, in one box
spacer1 = Line2D([], [], marker="None", linestyle="None", label="")
model_title = Line2D([], [], marker="None", linestyle="None", label="")
context_title = Line2D([], [], marker="None", linestyle="None", label="")
all_handles = [model_title] + model_handles + [spacer1, context_title] + context_handles
all_labels = (["── Model (color) ──"] +
              [h.get_label() for h in model_handles] +
              ["", "── Context (shape) ──"] +
              [h.get_label() for h in context_handles])
ax.legend(handles=all_handles, labels=all_labels, loc="lower right", fontsize=9)

plt.tight_layout()
plt.savefig(OUTPUT_DIR / "fig6b_recall_vs_ppv_beta.png", dpi=150)
plt.close()

# --- Fig 7: Execution and success rates ---
F1_SUCCESS_THRESHOLD_FIG7 = 0.75

# Compute data for all fig7 variants
fig7a_data = []
fig7b_data = []
fig7c_data = []
for model in df["model"].unique():
    for cl in CONTEXT_LEVELS:
        alpha_rows = df[(df["model"] == model) & (df["family"] == "alpha") & (df["context_level"] == cl)]
        beta_rows = df[(df["model"] == model) & (df["family"] == "beta") & (df["context_level"] == cl)]

        # 7a: alpha execution rate
        n_executed = len(alpha_rows)
        exec_rate = n_executed / EXPECTED_ALPHA_ATTEMPTS
        fig7a_data.append({
            "model": model,
            "model_display": MODEL_DISPLAY_NAMES.get(model, model),
            "context_level": cl,
            "n_executed": n_executed,
            "exec_rate": exec_rate,
        })

        # 7b: alpha success rate
        n_success_alpha = (alpha_rows["F1"] >= F1_SUCCESS_THRESHOLD_FIG7).sum()
        success_rate_alpha = n_success_alpha / EXPECTED_ALPHA_ATTEMPTS
        fig7b_data.append({
            "model": model,
            "model_display": MODEL_DISPLAY_NAMES.get(model, model),
            "context_level": cl,
            "n_success": int(n_success_alpha),
            "success_rate": success_rate_alpha,
        })

        # 7c: beta success rate
        n_success_beta = (beta_rows["F1"] >= F1_SUCCESS_THRESHOLD_FIG7).sum() if not beta_rows.empty else 0
        success_rate_beta = n_success_beta / EXPECTED_BETA_ATTEMPTS
        fig7c_data.append({
            "model": model,
            "model_display": MODEL_DISPLAY_NAMES.get(model, model),
            "context_level": cl,
            "n_success": int(n_success_beta),
            "success_rate": success_rate_beta,
        })

fig7a_df = pd.DataFrame(fig7a_data)
fig7b_df = pd.DataFrame(fig7b_data)
fig7c_df = pd.DataFrame(fig7c_data)

# --- Fig 7a: Alpha execution rate (x=model, grouped by context) ---
fig7a_pivot = fig7a_df.pivot_table(index="model_display", columns="context_level", values="exec_rate")
fig7a_pivot = fig7a_pivot[[cl for cl in CONTEXT_LEVELS if cl in fig7a_pivot.columns]]

fig, ax = plt.subplots(figsize=(12, 6))
fig7a_pivot.plot(kind="bar", ax=ax, edgecolor="black", linewidth=0.5)
ax.set_xlabel("Model")
ax.set_ylabel("Execution Rate (out of 5 attempts)")
ax.set_title("Fig 7a: Alpha Execution Rate by Model and Context Level")
ax.set_ylim(0, 1.05)
ax.legend(title="Context Level", labels=[f"v{cl}" for cl in CONTEXT_LEVELS if cl in fig7a_pivot.columns],
          bbox_to_anchor=(1.02, 1), loc="upper left", fontsize=9)
ax.set_xticklabels(ax.get_xticklabels(), rotation=45, ha="right")
plt.tight_layout()
plt.savefig(OUTPUT_DIR / "fig7a_alpha_execution_rate.png", dpi=150, bbox_inches="tight")
plt.close()

# --- Fig 7b: Alpha success rate (x=model, grouped by context) ---
fig7b_pivot = fig7b_df.pivot_table(index="model_display", columns="context_level", values="success_rate")
fig7b_pivot = fig7b_pivot[[cl for cl in CONTEXT_LEVELS if cl in fig7b_pivot.columns]]

fig, ax = plt.subplots(figsize=(12, 6))
fig7b_pivot.plot(kind="bar", ax=ax, edgecolor="black", linewidth=0.5)
ax.set_xlabel("Model")
ax.set_ylabel(f"Success Rate (F1 >= {F1_SUCCESS_THRESHOLD_FIG7})")
ax.set_title(f"Fig 7b: Alpha Success Rate (F1 >= {F1_SUCCESS_THRESHOLD_FIG7}) by Model and Context Level")
ax.set_ylim(0, 1.05)
ax.legend(title="Context Level", labels=[f"v{cl}" for cl in CONTEXT_LEVELS if cl in fig7b_pivot.columns],
          bbox_to_anchor=(1.02, 1), loc="upper left", fontsize=9)
ax.set_xticklabels(ax.get_xticklabels(), rotation=45, ha="right")
plt.tight_layout()
plt.savefig(OUTPUT_DIR / "fig7b_alpha_success_rate.png", dpi=150, bbox_inches="tight")
plt.close()

# --- Fig 7c: Beta success rate (x=model, grouped by context) ---
fig7c_pivot = fig7c_df.pivot_table(index="model_display", columns="context_level", values="success_rate")
fig7c_pivot = fig7c_pivot[[cl for cl in CONTEXT_LEVELS if cl in fig7c_pivot.columns]]

fig, ax = plt.subplots(figsize=(12, 6))
fig7c_pivot.plot(kind="bar", ax=ax, edgecolor="black", linewidth=0.5)
ax.set_xlabel("Model")
ax.set_ylabel(f"Success Rate (F1 >= {F1_SUCCESS_THRESHOLD_FIG7})")
ax.set_title(f"Fig 7c: Beta Success Rate (F1 >= {F1_SUCCESS_THRESHOLD_FIG7}) by Model and Context Level")
ax.set_ylim(0, 1.05)
ax.legend(title="Context Level", labels=[f"v{cl}" for cl in CONTEXT_LEVELS if cl in fig7c_pivot.columns],
          bbox_to_anchor=(1.02, 1), loc="upper left", fontsize=9)
ax.set_xticklabels(ax.get_xticklabels(), rotation=45, ha="right")
plt.tight_layout()
plt.savefig(OUTPUT_DIR / "fig7c_beta_success_rate.png", dpi=150, bbox_inches="tight")
plt.close()

# --- Fig 7_1a: Alpha execution rate (x=context level, grouped by model) ---
fig7_1a_pivot = fig7a_df.pivot_table(index="context_level", columns="model_display", values="exec_rate")
fig7_1a_pivot = fig7_1a_pivot.loc[[cl for cl in CONTEXT_LEVELS if cl in fig7_1a_pivot.index]]
fig7_1a_pivot.index = [f"v{cl}" for cl in fig7_1a_pivot.index]

fig, ax = plt.subplots(figsize=(10, 6))
fig7_1a_pivot.plot(kind="bar", ax=ax, edgecolor="black", linewidth=0.5)
ax.set_xlabel("Context Level")
ax.set_ylabel("Execution Rate (out of 5 attempts)")
ax.set_title("Fig 7_1a: Alpha Execution Rate by Context Level")
ax.set_ylim(0, 1.05)
ax.legend(title="Model", bbox_to_anchor=(1.02, 1), loc="upper left", fontsize=9)
ax.set_xticklabels(ax.get_xticklabels(), rotation=0)
plt.tight_layout()
plt.savefig(OUTPUT_DIR / "fig7_1a_alpha_execution_rate.png", dpi=150, bbox_inches="tight")
plt.close()

# --- Fig 7_1b: Alpha success rate (x=context level, grouped by model) ---
fig7_1b_pivot = fig7b_df.pivot_table(index="context_level", columns="model_display", values="success_rate")
fig7_1b_pivot = fig7_1b_pivot.loc[[cl for cl in CONTEXT_LEVELS if cl in fig7_1b_pivot.index]]
fig7_1b_pivot.index = [f"v{cl}" for cl in fig7_1b_pivot.index]

fig, ax = plt.subplots(figsize=(10, 6))
fig7_1b_pivot.plot(kind="bar", ax=ax, edgecolor="black", linewidth=0.5)
ax.set_xlabel("Context Level")
ax.set_ylabel(f"Success Rate (F1 >= {F1_SUCCESS_THRESHOLD_FIG7})")
ax.set_title(f"Fig 7_1b: Alpha Success Rate (F1 >= {F1_SUCCESS_THRESHOLD_FIG7}) by Context Level")
ax.set_ylim(0, 1.05)
ax.legend(title="Model", bbox_to_anchor=(1.02, 1), loc="upper left", fontsize=9)
ax.set_xticklabels(ax.get_xticklabels(), rotation=0)
plt.tight_layout()
plt.savefig(OUTPUT_DIR / "fig7_1b_alpha_success_rate.png", dpi=150, bbox_inches="tight")
plt.close()

# --- Fig 7_1c: Beta success rate (x=context level, grouped by model) ---
fig7_1c_pivot = fig7c_df.pivot_table(index="context_level", columns="model_display", values="success_rate")
fig7_1c_pivot = fig7_1c_pivot.loc[[cl for cl in CONTEXT_LEVELS if cl in fig7_1c_pivot.index]]
fig7_1c_pivot.index = [f"v{cl}" for cl in fig7_1c_pivot.index]

fig, ax = plt.subplots(figsize=(10, 6))
fig7_1c_pivot.plot(kind="bar", ax=ax, edgecolor="black", linewidth=0.5)
ax.set_xlabel("Context Level")
ax.set_ylabel(f"Success Rate (F1 >= {F1_SUCCESS_THRESHOLD_FIG7})")
ax.set_title(f"Fig 7_1c: Beta Success Rate (F1 >= {F1_SUCCESS_THRESHOLD_FIG7}) by Context Level")
ax.set_ylim(0, 1.05)
ax.legend(title="Model", bbox_to_anchor=(1.02, 1), loc="upper left", fontsize=9)
ax.set_xticklabels(ax.get_xticklabels(), rotation=0)
plt.tight_layout()
plt.savefig(OUTPUT_DIR / "fig7_1c_beta_success_rate.png", dpi=150, bbox_inches="tight")
plt.close()

# --- Fig 8: F1 scores by context level per model (bar + line charts) ---
# Beta: one F1 per model per context level (raw value, NaN if didn't run)
fig8_beta_data = []
for model in df["model"].unique():
    for cl in CONTEXT_LEVELS:
        beta_rows = df[(df["model"] == model) & (df["family"] == "beta") & (df["context_level"] == cl)]
        f1_val = beta_rows["F1"].values[0] if not beta_rows.empty else np.nan
        fig8_beta_data.append({
            "model_display": MODEL_DISPLAY_NAMES.get(model, model),
            "context_level": cl,
            "F1": f1_val,
        })

fig8_beta_df = pd.DataFrame(fig8_beta_data)
fig8_beta_pivot = fig8_beta_df.pivot_table(index="model_display", columns="context_level", values="F1")
fig8_beta_pivot = fig8_beta_pivot[[cl for cl in CONTEXT_LEVELS if cl in fig8_beta_pivot.columns]]

# Alpha: individual F1 for each of 5 attempts per model per context level
fig8_alpha_data = []
for model in df["model"].unique():
    for cl in CONTEXT_LEVELS:
        alpha_rows = df[(df["model"] == model) & (df["family"] == "alpha") & (df["context_level"] == cl)]
        for p in range(1, 6):
            prompt_name = f"a{cl}p{p}"
            row = alpha_rows[alpha_rows["prompt"] == prompt_name]
            f1_val = row["F1"].values[0] if not row.empty else np.nan
            fig8_alpha_data.append({
                "model_display": MODEL_DISPLAY_NAMES.get(model, model),
                "context_level": cl,
                "prompt_variant": p,
                "prompt": prompt_name,
                "F1": f1_val,
            })

fig8_alpha_df = pd.DataFrame(fig8_alpha_data)

# --- Fig 8a: Bar chart - Beta F1 by model, grouped by context level (x=model) ---
fig, ax = plt.subplots(figsize=(12, 6))
fig8_beta_pivot.plot(kind="bar", ax=ax, edgecolor="black", linewidth=0.5)
ax.set_xlabel("Model")
ax.set_ylabel("F1 Score")
ax.set_title("Fig 8a: Beta F1 Score by Model and Context Level")
ax.set_ylim(0, 1.05)
ax.legend(title="Context Level", labels=[f"v{cl}" for cl in CONTEXT_LEVELS if cl in fig8_beta_pivot.columns],
          bbox_to_anchor=(1.02, 1), loc="upper left", fontsize=9)
ax.set_xticklabels(ax.get_xticklabels(), rotation=45, ha="right")
plt.tight_layout()
plt.savefig(OUTPUT_DIR / "fig8a_beta_f1_bar.png", dpi=150, bbox_inches="tight")
plt.close()

# --- Fig 8b: Bar chart - Beta F1 by context level, grouped by model (x=context) ---
fig8_beta_pivot_t = fig8_beta_df.pivot_table(index="context_level", columns="model_display", values="F1")
fig8_beta_pivot_t = fig8_beta_pivot_t.loc[[cl for cl in CONTEXT_LEVELS if cl in fig8_beta_pivot_t.index]]
fig8_beta_pivot_t.index = [f"v{cl}" for cl in fig8_beta_pivot_t.index]

fig, ax = plt.subplots(figsize=(10, 6))
fig8_beta_pivot_t.plot(kind="bar", ax=ax, edgecolor="black", linewidth=0.5)
ax.set_xlabel("Context Level")
ax.set_ylabel("F1 Score")
ax.set_title("Fig 8b: Beta F1 Score by Context Level")
ax.set_ylim(0, 1.05)
ax.legend(title="Model", bbox_to_anchor=(1.02, 1), loc="upper left", fontsize=9)
ax.set_xticklabels(ax.get_xticklabels(), rotation=0)
plt.tight_layout()
plt.savefig(OUTPUT_DIR / "fig8b_beta_f1_bar_by_context.png", dpi=150, bbox_inches="tight")
plt.close()

# --- Fig 8c: Line chart - Beta F1 across context levels per model ---
fig, ax = plt.subplots(figsize=(10, 6))
context_x = [f"v{cl}" for cl in CONTEXT_LEVELS]
for model in df["model"].unique():
    model_disp = MODEL_DISPLAY_NAMES.get(model, model)
    f1_vals = []
    for cl in CONTEXT_LEVELS:
        beta_rows = df[(df["model"] == model) & (df["family"] == "beta") & (df["context_level"] == cl)]
        f1_vals.append(beta_rows["F1"].values[0] if not beta_rows.empty else np.nan)
    # Connect dots even if a model skips a version
    available = [(cx, v) for cx, v in zip(context_x, f1_vals) if not np.isnan(v)]
    if available:
        x_pts, y_pts = zip(*available)
        ax.plot(x_pts, y_pts, marker="o", label=model_disp,
                color=model_color_map.get(model, "gray"), linewidth=2, markersize=7)

ax.set_xlabel("Context Level")
ax.set_ylabel("F1 Score")
ax.set_title("Fig 8c: Beta F1 Score Across Context Levels (Line)")
ax.set_ylim(0, 1.05)
ax.legend(title="Model", bbox_to_anchor=(1.02, 1), loc="upper left", fontsize=9)
ax.grid(True, alpha=0.3)
plt.tight_layout()
plt.savefig(OUTPUT_DIR / "fig8c_beta_f1_line.png", dpi=150, bbox_inches="tight")
plt.close()


# --- Fig 8e: Line chart - Alpha mean F1 across context levels per model ---
fig, ax = plt.subplots(figsize=(10, 6))
for model in df["model"].unique():
    model_disp = MODEL_DISPLAY_NAMES.get(model, model)
    mean_f1_vals = []
    for cl in CONTEXT_LEVELS:
        alpha_rows = df[(df["model"] == model) & (df["family"] == "alpha") & (df["context_level"] == cl)]
        if not alpha_rows.empty:
            mean_f1_vals.append(alpha_rows["F1"].mean())
        else:
            mean_f1_vals.append(np.nan)
    # Connect dots even if a model skips a version: filter out NaN points
    available = [(cx, v) for cx, v in zip(context_x, mean_f1_vals) if not np.isnan(v)]
    if available:
        x_pts, y_pts = zip(*available)
        ax.plot(x_pts, y_pts, marker="s", label=model_disp,
                color=model_color_map.get(model, "gray"), linewidth=2, markersize=7)

ax.set_xlabel("Context Level")
ax.set_ylabel("Mean F1 Score (across 5 attempts)")
ax.set_title("Fig 8e: Alpha Mean F1 Score Across Context Levels (Line)")
ax.set_ylim(0, 1.05)
ax.legend(title="Model", bbox_to_anchor=(1.02, 1), loc="upper left", fontsize=9)
ax.grid(True, alpha=0.3)
plt.tight_layout()
plt.savefig(OUTPUT_DIR / "fig8e_alpha_f1_line.png", dpi=150, bbox_inches="tight")
plt.close()

# =============================================================================
# 6. Summary Report
# =============================================================================

print("\nWriting summary report...")

report_lines = []
report_lines.append("=" * 80)
report_lines.append("T2DM PHENOTYPE PREDICTION ANALYSIS - SYNTHETIC DATASET")
report_lines.append("=" * 80)
report_lines.append(f"\nGold standard: {len(gold_ids)} T2DM-positive patients")
report_lines.append(f"Total population: {TOTAL_POPULATION}")
report_lines.append(f"Prevalence: {len(gold_ids)/TOTAL_POPULATION*100:.1f}%")
report_lines.append(f"Models evaluated: {df['model'].nunique()}")
report_lines.append(f"Total model-prompt outputs: {len(df)}")

report_lines.append("\n" + "=" * 80)
report_lines.append("ANALYSIS 1: VERSION COMPARISON (v1 vs v2)")
report_lines.append("=" * 80)
report_lines.append("\nContext: a1/b1 and a2/b2 are two implementation versions at the same context level.")
report_lines.append("Question: Is one version consistently better than the other?")
report_lines.append("")
report_lines.append("Method: Pool all outputs at context_level=1 (a1p1-a1p5 + b1) as v1, and all")
report_lines.append("at context_level=2 (a2p1-a2p5 + b2) as v2. Compare within each model using")
report_lines.append("Mann-Whitney U, then test consistency across models with Wilcoxon signed-rank.")
report_lines.append("")
report_lines.append("Per-model v1 vs v2 (mean F1):")
for _, row in version_combined_df.iterrows():
    sig_markers = [m for m in COMPARISON_METRICS if not np.isnan(row.get(f"p_value_{m}", np.nan)) and row[f"p_value_{m}"] < 0.05]
    sig_str = f" [sig: {', '.join(sig_markers)}]" if sig_markers else ""
    v1_f1 = row['v1_mean_F1']
    v2_f1 = row['v2_mean_F1']
    v1_str = f"{v1_f1:.4f}" if not np.isnan(v1_f1) else "N/A"
    v2_str = f"{v2_f1:.4f}" if not np.isnan(v2_f1) else "N/A"
    report_lines.append(f"  {row['model_display']:<22} v1={v1_str} (n={row['n_v1']})  v2={v2_str} (n={row['n_v2']}){sig_str}")

report_lines.append(f"\nAcross models: v2 better in {n_v2_better}/{n_nontie_combined + n_ties_combined} | sign test p={sign_test_p_combined:.4f}")
if not np.isnan(wilcoxon_p_v):
    report_lines.append(f"Wilcoxon signed-rank (paired model means): W={wilcoxon_stat_v:.1f}, p={wilcoxon_p_v:.4f}")
    if wilcoxon_p_v < 0.05:
        winner = "v2" if n_v2_better > n_v1_better else "v1"
        report_lines.append(f"  -> Significant: {winner} is consistently better across models.")
    else:
        report_lines.append("  -> Not significant: no consistent version advantage across models.")

report_lines.append("\n" + "=" * 80)
report_lines.append("ANALYSIS 1c: ALPHA vs BETA - PUBLICATION OUTCOMES")
report_lines.append("=" * 80)
report_lines.append("\nDesign: Alpha = 5 independent SQL generation attempts per context level.")
report_lines.append("        Beta  = 1 refined/consolidated SQL per context level.")
report_lines.append(f"        Success threshold: F1 >= {F1_SUCCESS_THRESHOLD}")
report_lines.append("")
report_lines.append("--- PRIMARY OUTCOME: End-to-end success rate ---")
report_lines.append(f"  Alpha: {total_alpha_successes}/{total_alpha_expected} attempts achieved F1>={F1_SUCCESS_THRESHOLD} ({overall_alpha_success_rate:.1%})")
report_lines.append(f"  Beta:  {total_beta_successes}/{total_beta_expected} attempts achieved F1>={F1_SUCCESS_THRESHOLD} ({overall_beta_success_rate:.1%})")
report_lines.append(f"  Fisher's exact test (aggregated): p={agg_fisher_p:.4f}")
if agg_fisher_p < 0.05:
    report_lines.append("  -> Statistically significant difference in success rates.")
else:
    report_lines.append("  -> No significant difference in end-to-end success rates.")

report_lines.append("")
report_lines.append("--- SECONDARY A: SQL execution rate + F1 among executed ---")
report_lines.append(f"  Alpha execution rate: {total_alpha_executed}/{total_alpha_expected} ({overall_alpha_exec_rate:.1%})")
report_lines.append(f"  Beta execution rate:  {total_beta_executed}/{total_beta_expected} ({overall_beta_exec_rate:.1%})")
report_lines.append(f"  Mean F1 (executed only) - Alpha: {np.nanmean(alpha_exec_f1s):.4f}, Beta: {np.nanmean(beta_exec_f1s):.4f}")

report_lines.append("")
report_lines.append("--- SECONDARY B (sensitivity): Penalized mean F1 (F1=0 for failures) ---")
report_lines.append(f"  Alpha penalized mean F1: {ab_valid['alpha_penalized_mean_F1'].mean():.4f}")
report_lines.append(f"  Beta penalized mean F1:  {ab_valid['beta_penalized_mean_F1'].mean():.4f}")
report_lines.append("  (Missing/failed/zero-row outputs assigned F1=0)")

report_lines.append("")
report_lines.append("--- Per model × context level detail ---")
report_lines.append(f"{'Model':<22} {'Ctx':>3} | {'α exec':>6} {'α succ':>6} {'α F1†':>6} {'α pen':>6} | {'β exec':>6} {'β succ':>6} {'β F1†':>6} {'β pen':>6} | {'note'}")
report_lines.append("-" * 110)
for _, row in alpha_beta_df.iterrows():
    a_f1_ex = f"{row['alpha_mean_F1_executed']:.3f}" if not np.isnan(row['alpha_mean_F1_executed']) else "  N/A"
    b_f1_ex = f"{row['beta_mean_F1_executed']:.3f}" if not np.isnan(row['beta_mean_F1_executed']) else "  N/A"
    report_lines.append(
        f"  {row['model_display']:<20} {row['context_level']:>3} | "
        f"{row['alpha_executed']}/{row['alpha_expected']:>1}   "
        f"{row['alpha_successes_F1_ge_80']}/{row['alpha_expected']:>1}   "
        f"{a_f1_ex} "
        f"{row['alpha_penalized_mean_F1']:.3f} | "
        f"{row['beta_executed']}/{row['beta_expected']:>1}   "
        f"{row['beta_successes_F1_ge_80']}/{row['beta_expected']:>1}   "
        f"{b_f1_ex} "
        f"{row['beta_penalized_mean_F1']:.3f} | "
        f"{row['test_note']}"
    )
report_lines.append("")
report_lines.append("† F1 computed only among successfully executed outputs.")
report_lines.append("  PPV and FPR are reported in the CSV (undefined for failed queries).")

report_lines.append("\n" + "=" * 80)
report_lines.append("ANALYSIS 2: CONTEXT-LEVEL PROGRESSION (b0 < b1/b2 < b4)")
report_lines.append("=" * 80)
report_lines.append("\nQuestion: Do beta prompts improve as more context is provided?")
report_lines.append("Structure: b0 (zero-shot) < b1/b2 (mid-context, averaged) < b4 (full context)")
report_lines.append(f"\nModels with monotonically increasing F1 (b0 < mid < b4): {n_monotonic}/{n_total_prog}")

if not np.isnan(friedman_stat):
    report_lines.append(f"Friedman test (F1 across b0/mid/b4): chi2={friedman_stat:.3f}, p={friedman_p:.4f}")
    if friedman_p < 0.05:
        report_lines.append("  -> Significant: context level significantly affects F1 performance.")
    else:
        report_lines.append("  -> Not significant at alpha=0.05.")

report_lines.append("\nPairwise tier comparisons (Wilcoxon signed-rank across models):")
for _, trow in tier_tests_df.iterrows():
    p_str = f"p={trow['wilcoxon_p']:.4f}" if not np.isnan(trow['wilcoxon_p']) else "N/A (too few)"
    sig_marker = " *" if (not np.isnan(trow['wilcoxon_p']) and trow['wilcoxon_p'] < 0.05) else ""
    report_lines.append(f"  {trow['comparison']}: improved in {trow['n_improved']}/{trow['n_models']} models, {p_str}{sig_marker}")

report_lines.append("\nPer-model progression:")
for _, row in beta_prog_df.iterrows():
    mono_str = "YES" if row["monotonic_F1"] else "NO"
    tau_str = f"tau={row['kendall_tau']:.3f}, p={row['kendall_p']:.4f}" if not np.isnan(row["kendall_tau"]) else "N/A"
    report_lines.append(f"  {row['model_display']}: {row['F1_tiers']}")
    report_lines.append(f"    Monotonic: {mono_str} | Kendall: {tau_str}")

report_lines.append("\n" + "=" * 80)
report_lines.append("ANALYSIS 3: MODEL RANKING")
report_lines.append("=" * 80)
report_lines.append("\nRanking by penalized mean F1 (accounts for execution failures):")
report_lines.append(f"{'Rank':<4} {'Model':<22} {'Pen F1':>7} {'Exec Rate':>10} {'Success Rate':>12} {'F1|exec':>8} {'Best':>12}")
report_lines.append("-" * 85)

for _, row in ranking_df.iterrows():
    report_lines.append(
        f"  {row['rank']:<2}  {row['model_display']:<22} "
        f"{row['penalized_mean_F1']:.4f}  "
        f"{row['n_executed_total']}/{row['n_expected_total']:>2} ({row['exec_rate_total']:.0%})  "
        f"{row['n_success_total']}/{row['n_expected_total']:>2} ({row['success_rate_total']:.0%})     "
        f"{row['mean_F1_executed']:.4f}  "
        f"{row['best_prompt']} ({row['best_F1']:.4f})"
    )

report_lines.append("")
report_lines.append("  Pen F1       = Penalized mean F1 (F1=0 for missing/failed SQL)")
report_lines.append("  Exec Rate    = Proportion of expected attempts that produced output")
report_lines.append("  Success Rate = Proportion of expected attempts achieving F1>=0.80")
report_lines.append("  F1|exec      = Mean F1 among successfully executed outputs only")

if not np.isnan(kw_stat):
    report_lines.append(f"\nKruskal-Wallis test (beta F1 across models): H={kw_stat:.3f}, p={kw_p:.4f}")
    if kw_p < 0.05:
        report_lines.append("  -> Significant differences exist between models.")

report_lines.append("\nPairwise comparisons (Mann-Whitney U, top pairs):")
sig_pairs = pairwise_df[pairwise_df["significant_0.05"] == True].head(20)
for _, row in sig_pairs.iterrows():
    report_lines.append(f"  {row['model_1']} vs {row['model_2']}: "
                       f"F1={row['mean_F1_model1']:.4f} vs {row['mean_F1_model2']:.4f}, p={row['p_value']:.4f} *")

report_lines.append("\n" + "=" * 80)
report_lines.append("OUTPUT FILES")
report_lines.append("=" * 80)
report_lines.append(f"\nAll tables (CSV) and figures (PNG) above are written to {OUTPUT_DIR}/,")
report_lines.append("alongside this summary_report.txt.")

report_text = "\n".join(report_lines)
(OUTPUT_DIR / "summary_report.txt").write_text(report_text)

print(report_text)
print("\n\nAll outputs saved to:", OUTPUT_DIR)
