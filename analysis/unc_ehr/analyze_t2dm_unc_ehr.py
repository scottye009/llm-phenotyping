"""
SHIRE T2DM Phenotype Prediction Analysis - Real Data
=====================================================

NOTE ON REPRODUCIBILITY (public release):
This script runs inside the UNC Secure Health Informatics Research
Environment (SHIRE) against per-model prediction CSVs and cohort
person-ID files that are UNC EHR patient data and are NOT included in
this repository. It is shared so reviewers can see exactly how the
UNC EHR aggregate metrics reported in the paper were computed; it is
not runnable outside SHIRE without independent access to that
environment and its underlying (non-public) data.

Evaluates LLM-generated SQL phenotype outputs against a single ground-truth
reference:
  - eMERGE phenotype output: Z:\\output\\t2dm_v5.csv

The SHIRE labeled test cohort is NOT used as a ground-truth reference for LLM
metrics:
  - Cohort_1/person.csv = T2DM-positive
  - Cohort_2/person.csv = T2DM-negative
  - Cohort_3/person.csv = T2DM-negative
Instead, the discrepancy between the SHIRE cohort labels and the eMERGE
reference (reference_agreement_emerge_vs_shire.csv) is reported as motivation
for the study: it quantifies how much the rule-based eMERGE phenotype and the
independently labeled SHIRE cohort disagree, which is the gap LLM-generated
phenotypes may help close.

Overlapping person_ids between the SHIRE Cohort_1 (positive) and Cohort_2/3
(negative) files are resolved by giving the positive label precedence; those
IDs are removed from the negative pool before computing cohort sizes, the
labeled universe, or any metric. All cohort label counts and eMERGE recall/
precision figures reported below (console output, summary_report.txt,
cohort_label_counts_after_overlap_removal.csv, reference_agreement_by_cohort.csv)
are stated AFTER this overlap removal, and all LLM metrics are computed
against the same de-overlapped labeled universe.

Prompt structure:
  - Alpha: a1p1-a1p5, a2p1-a2p5, a3p1-a3p5
  - Beta:  b1, b2, b3
  - Levels 1 and 2 are two parallel implementations of the SAME limited-context
    approach. The primary progression analysis pools levels 1/2 and compares
    them against level 3 (full context).
  - Gemma now has levels 1, 2, and 3, like every other model, and is included
    in all analyses including the paired progression test.

Missing expected CSV files are treated as failed/unexecuted outputs: they count
against the execution rate but are excluded (as NaN) from mean F1 calculations.
Existing CSV files with 0 predicted patients are treated as executed zero-row
outputs (Recall = 0 when gold positives exist; PPV is undefined/NaN since no
positive predictions were made). In heatmap figures, undefined/missing cells
are displayed as 0 rather than left blank.

Run:
    python analyze_t2dm_unc_ehr.py

Dependencies:
    pip install pandas numpy scipy matplotlib
"""

from __future__ import annotations

import re
import warnings
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Set, Tuple

import matplotlib.pyplot as plt
import matplotlib.cm as cm
from matplotlib.patches import Rectangle
from matplotlib.colors import Normalize
from matplotlib.lines import Line2D
import numpy as np
import pandas as pd
import seaborn as sns
from scipy import stats

warnings.filterwarnings("ignore", category=FutureWarning)

# =============================================================================
# Configuration - edit only this section if your folders differ
# =============================================================================

RESULT_DIR = Path(r"Z:\output")
STANDARD_FILE = RESULT_DIR / "t2dm_v5.csv"
COHORT_ROOT = Path(r"Z:\T2DB_data")
OUTPUT_DIR = RESULT_DIR / "analysis_shire_real"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)


# Exact filename prefixes in Z:\output. The values are publication labels.
MODEL_DISPLAY_NAMES: Dict[str, str] = {
    "Claude": "Claude Sonnet 4.5",
    "Copilot": "Copilot",
    "Gemini": "Gemini",
    "Gemma": "Gemma-4-31B",
    "gpt": "ChatGPT 5.5",
    "Llama": "Llama-3.3-70B",
    "OMOP-SQL-Assistant": "OMOP-SQL-Assistant",
    "QueryGPT": "QueryGPT",
}

# All models, including Gemma, have levels 1, 2, and 3.
MODEL_LEVELS: Dict[str, Sequence[str]] = {
    model: ["1", "2", "3"]
    for model in MODEL_DISPLAY_NAMES
}

ALPHA_VARIANTS = ["p1", "p2", "p3", "p4", "p5"]
# emerge_t2dm_v5 is the sole ground-truth reference for LLM metrics.
# shire_cohort_labels is used only to compute reference_agreement (motivation),
# never as a reference for scoring LLM outputs.
REFERENCES = ["emerge_t2dm_v5"]
COMPARISON_METRICS = ["F1", "PPV", "Recall", "FPR", "Specificity", "Accuracy"]

# =============================================================================
# Helper functions
# =============================================================================


def fmt_num(value: object, digits: int = 4) -> str:
    """Format a numeric value for the text report."""
    if value is None or pd.isna(value):
        return "N/A"
    return f"{float(value):.{digits}f}"


def normalize_person_id(series: pd.Series) -> Set[str]:
    """Normalize person IDs safely without converting integer IDs to decimals."""
    s = series.dropna().astype(str).str.strip()
    s = s.str.replace(r"\.0$", "", regex=True)
    return set(s[s != ""])


def read_person_ids(csv_path: Path) -> Set[str]:
    """Read a CSV and return normalized person_id values."""
    if not csv_path.exists():
        raise FileNotFoundError(f"Missing required file: {csv_path}")
    df = pd.read_csv(csv_path, low_memory=False)
    col_lookup = {str(col).strip().lower(): col for col in df.columns}
    if "person_id" not in col_lookup:
        raise ValueError(
            f"{csv_path}: no person_id column. Columns: {list(df.columns)}"
        )
    return normalize_person_id(df[col_lookup["person_id"]])


def safe_read_prediction_ids(csv_path: Path) -> Tuple[Set[str], str, Optional[str]]:
    """
    Read a prediction CSV.

    Returns:
      ids, status, error_message

    status is one of:
      executed_nonzero, executed_zero_rows, read_error
    """
    try:
        ids = read_person_ids(csv_path)
        status = "executed_nonzero" if len(ids) > 0 else "executed_zero_rows"
        return ids, status, None
    except Exception as exc:  # preserve the failure in outputs instead of aborting
        return set(), "read_error", str(exc)


def expected_prompt_names(model: str) -> List[str]:
    """Return every expected prompt name for a model."""
    prompts: List[str] = []
    for level in MODEL_LEVELS[model]:
        prompts.extend([f"a{level}{variant}" for variant in ALPHA_VARIANTS])
        prompts.append(f"b{level}")
    return prompts


def parse_prompt(prompt: str) -> Dict[str, Optional[str]]:
    """Parse prompt names such as a1p3 or b2."""
    alpha = re.fullmatch(r"a(?P<level>[123])(?P<variant>p[1-5])", prompt)
    if alpha:
        return {
            "family": "alpha",
            "context_level": alpha.group("level"),
            "prompt_variant": alpha.group("variant"),
        }
    beta = re.fullmatch(r"b(?P<level>[123])", prompt)
    if beta:
        return {
            "family": "beta",
            "context_level": beta.group("level"),
            "prompt_variant": None,
        }
    raise ValueError(f"Unrecognized prompt: {prompt}")


def compute_metrics(pred_ids: Set[str], gold_ids: Set[str], universe_ids: Set[str]) -> Dict[str, float]:
    """Compute confusion-matrix metrics within the labeled SHIRE universe."""
    pred_in_universe = set(pred_ids) & universe_ids
    gold_in_universe = set(gold_ids) & universe_ids

    tp = len(pred_in_universe & gold_in_universe)
    fp = len(pred_in_universe - gold_in_universe)
    fn = len(gold_in_universe - pred_in_universe)
    tn = len(universe_ids) - tp - fp - fn

    if tn < 0:
        raise ValueError("TN is negative. Check person_id normalization and cohort overlap.")

    ppv = tp / (tp + fp) if (tp + fp) > 0 else np.nan
    recall = tp / (tp + fn) if (tp + fn) > 0 else np.nan
    fpr = fp / (fp + tn) if (fp + tn) > 0 else np.nan
    f1 = 2 * tp / (2 * tp + fp + fn) if (2 * tp + fp + fn) > 0 else np.nan
    jaccard = tp / (tp + fp + fn) if (tp + fp + fn) > 0 else np.nan
    specificity = tn / (tn + fp) if (tn + fp) > 0 else np.nan
    accuracy = (tp + tn) / len(universe_ids) if len(universe_ids) > 0 else np.nan

    return {
        "TP": tp,
        "FP": fp,
        "FN": fn,
        "TN": tn,
        "Predicted_Positive": tp + fp,
        "PPV": ppv,
        "Recall": recall,
        "F1": f1,
        "Jaccard": jaccard,
        "FPR": fpr,
        "Specificity": specificity,
        "Accuracy": accuracy,
    }


def sign_test(values: Iterable[float]) -> Dict[str, float]:
    """Two-sided sign test, excluding ties and missing values."""
    arr = np.asarray([float(v) for v in values if not pd.isna(v)])
    positive = int((arr > 0).sum())
    negative = int((arr < 0).sum())
    ties = int((arr == 0).sum())
    n_non_tie = positive + negative
    p_value = stats.binomtest(positive, n_non_tie, p=0.5).pvalue if n_non_tie else np.nan
    return {
        "n_positive": positive,
        "n_negative": negative,
        "n_ties": ties,
        "n_non_tie": n_non_tie,
        "sign_test_p_two_sided": p_value,
    }


def safe_wilcoxon(x: Sequence[float], y: Sequence[float], alternative: str = "two-sided") -> Tuple[float, float]:
    """Run a paired Wilcoxon test safely; return NaN when it is not meaningful."""
    paired = pd.DataFrame({"x": x, "y": y}).dropna()
    if len(paired) < 3:
        return np.nan, np.nan
    diffs = paired["y"] - paired["x"]
    if np.allclose(diffs, 0):
        return 0.0, 1.0
    try:
        stat, p_value = stats.wilcoxon(paired["x"], paired["y"], alternative=alternative)
        return float(stat), float(p_value)
    except ValueError:
        return np.nan, np.nan


def summarize_rows(rows: pd.DataFrame) -> Dict[str, float]:
    """Summarize expected prompt rows; F1/PPV/Recall/FPR are averaged over executed rows only."""
    if rows.empty:
        return {
            "n_expected": 0,
            "n_executed": 0,
            "n_nonzero": 0,
            "n_failed_or_missing": 0,
            "execution_rate": np.nan,
            "usable_output_rate": np.nan,
            "mean_F1_executed": np.nan,
            "mean_PPV_executed": np.nan,
            "mean_Recall_executed": np.nan,
            "mean_Jaccard_executed": np.nan,
            "mean_FPR_executed": np.nan,
        }

    executed = rows[rows["executed"]]
    n_expected = len(rows)
    n_executed = len(executed)
    n_nonzero = int(rows["usable_cohort"].sum())

    return {
        "n_expected": n_expected,
        "n_executed": n_executed,
        "n_nonzero": n_nonzero,
        "n_failed_or_missing": n_expected - n_executed,
        "execution_rate": n_executed / n_expected,
        "usable_output_rate": n_nonzero / n_expected,
        "mean_F1_executed": executed["F1"].mean() if not executed.empty else np.nan,
        "mean_PPV_executed": executed["PPV"].mean() if not executed.empty else np.nan,
        "mean_Recall_executed": executed["Recall"].mean() if not executed.empty else np.nan,
        "mean_Jaccard_executed": executed["Jaccard"].mean() if not executed.empty else np.nan,
        "mean_FPR_executed": executed["FPR"].mean() if not executed.empty else np.nan,
    }


def add_prefixed(target: Dict[str, object], prefix: str, values: Dict[str, object]) -> None:
    for key, value in values.items():
        target[f"{prefix}_{key}"] = value


# =============================================================================
# Load cohort references
# =============================================================================

print("Loading SHIRE cohort labels and eMERGE reference...")

cohort_1_ids = read_person_ids(COHORT_ROOT / "Cohort_1" / "person.csv")
cohort_2_ids = read_person_ids(COHORT_ROOT / "Cohort_2" / "person.csv")
cohort_3_ids = read_person_ids(COHORT_ROOT / "Cohort_3" / "person.csv")

shire_positive_ids = set(cohort_1_ids)
shire_negative_ids_raw = set(cohort_2_ids) | set(cohort_3_ids)
overlap_pos_neg = shire_positive_ids & shire_negative_ids_raw
if overlap_pos_neg:
    print(f"WARNING: {len(overlap_pos_neg)} person_ids occur in both positive and negative cohorts.")
    print("         Positive label takes precedence; overlap IDs are removed from negatives.")
shire_negative_ids = shire_negative_ids_raw - shire_positive_ids
shire_universe_ids = shire_positive_ids | shire_negative_ids

# Per-cohort sets with the same positive-precedence overlap removed, so that
# Cohort_2/Cohort_3 counts and metrics reported below are stated on the same
# de-overlapped basis as the pooled universe above (rather than on the raw
# person.csv counts, which include patients later reassigned to Cohort_1).
cohort_2_dedup_ids = cohort_2_ids - overlap_pos_neg
cohort_3_dedup_ids = cohort_3_ids - overlap_pos_neg
overlap_2_3 = cohort_2_dedup_ids & cohort_3_dedup_ids
if overlap_2_3:
    print(f"NOTE: {len(overlap_2_3)} person_ids occur in both Cohort_2 and Cohort_3 (both negative; "
          "counted once in the pooled negative universe, but appear in both per-cohort rows below).")

emerge_ids_raw = read_person_ids(STANDARD_FILE)
emerge_ids = emerge_ids_raw & shire_universe_ids
emerge_outside_universe = emerge_ids_raw - shire_universe_ids

reference_gold_ids: Dict[str, Set[str]] = {
    "emerge_t2dm_v5": emerge_ids,
}

cohort_counts_df = pd.DataFrame([
    {"cohort": "Cohort_1", "shire_expected_label": "positive",
     "n_raw": len(cohort_1_ids), "n_removed_as_overlap": 0,
     "n_after_removing_overlap": len(shire_positive_ids)},
    {"cohort": "Cohort_2", "shire_expected_label": "negative",
     "n_raw": len(cohort_2_ids), "n_removed_as_overlap": len(cohort_2_ids & overlap_pos_neg),
     "n_after_removing_overlap": len(cohort_2_dedup_ids)},
    {"cohort": "Cohort_3", "shire_expected_label": "negative",
     "n_raw": len(cohort_3_ids), "n_removed_as_overlap": len(cohort_3_ids & overlap_pos_neg),
     "n_after_removing_overlap": len(cohort_3_dedup_ids)},
    {"cohort": "Cohort_2_and_3_pooled", "shire_expected_label": "negative",
     "n_raw": len(shire_negative_ids_raw), "n_removed_as_overlap": len(overlap_pos_neg),
     "n_after_removing_overlap": len(shire_negative_ids)},
    {"cohort": "Labeled_universe", "shire_expected_label": "positive+negative",
     "n_raw": len(cohort_1_ids) + len(shire_negative_ids_raw), "n_removed_as_overlap": len(overlap_pos_neg),
     "n_after_removing_overlap": len(shire_universe_ids)},
])
cohort_counts_df.to_csv(OUTPUT_DIR / "cohort_label_counts_after_overlap_removal.csv", index=False)

print("\nSHIRE cohort label counts (after removing overlapping patients):")
for _, row in cohort_counts_df.iterrows():
    print(
        f"    {row['cohort']:<22} raw={row['n_raw']:<8} "
        f"removed_as_overlap={row['n_removed_as_overlap']:<6} -> "
        f"n_after_removing_overlap={row['n_after_removing_overlap']}"
    )
print(f"  eMERGE t2dm_v5 positive within universe: {len(emerge_ids)}")
if emerge_outside_universe:
    print(f"  NOTE: {len(emerge_outside_universe)} eMERGE IDs fall outside the labeled SHIRE universe and are excluded from metrics.")

# Agreement of the SHIRE cohort label (Cohort_1 positive) with eMERGE.
# eMERGE is the reference standard (gold); Cohort_1 is the thing being scored
# against it, exactly like an LLM prediction. So:
#   Recall = fraction of eMERGE-positive patients that Cohort_1 also captures
#   PPV (Precision) = fraction of Cohort_1 that eMERGE also confirms positive
#   Jaccard = |Cohort_1 ∩ eMERGE+| / |Cohort_1 ∪ eMERGE+| (order-independent)
reference_agreement = compute_metrics(shire_positive_ids, emerge_ids, shire_universe_ids)
print(
    "\nSHIRE Cohort_1 vs eMERGE (reference standard; universe after removing overlapping patients): "
    f"Recall={fmt_num(reference_agreement['Recall'])} | "
    f"Precision(PPV)={fmt_num(reference_agreement['PPV'])} | "
    f"F1={fmt_num(reference_agreement['F1'])} | "
    f"Jaccard={fmt_num(reference_agreement['Jaccard'])}"
)
reference_agreement_df = pd.DataFrame([{
    "comparison": "shire_cohort1_vs_emerge_t2dm_v5_reference_standard",
    "universe_n": len(shire_universe_ids),
    "emerge_positive_raw_n": len(emerge_ids_raw),
    "emerge_positive_in_universe_n": len(emerge_ids),
    "emerge_positive_outside_universe_n": len(emerge_outside_universe),
    "shire_positive_n": len(shire_positive_ids),
    **reference_agreement,
}])
reference_agreement_df.to_csv(OUTPUT_DIR / "reference_agreement_emerge_vs_shire.csv", index=False)

# Per-cohort agreement breakdown, with eMERGE as the reference standard (gold)
# throughout, matching the top-level reference_agreement direction. Cohort_1/2/3
# may carry different meaning (e.g. different sites or negative-selection
# criteria), so pooling them into a single positive/negative universe (as above)
# could hide cohort-specific disagreement between eMERGE and the SHIRE labels.
# Cohort_2/Cohort_3 use the overlap-removed sets so a patient reassigned to
# Cohort_1 (positive) is not also counted here.
#
# Each cohort is treated as a "prediction" scored against eMERGE (gold):
#   Cohort_1 predicts everyone in it positive  -> TP/FP cells apply, Precision(PPV) is meaningful
#   Cohort_2/3 predict everyone in them negative -> FN/TN cells apply, NPV is meaningful
# share_of_all_emerge_positive_rate is this cohort's share of ALL eMERGE
# positives in the universe (the true "recall contribution"); for Cohort_2/3
# it quantifies eMERGE-positive patients that leaked into a supposedly-negative
# cohort. Jaccard_vs_emerge_positive is the order-independent set overlap
# between this cohort's raw membership and the eMERGE-positive set.
cohort_definitions = [
    ("Cohort_1", cohort_1_ids, "positive"),
    ("Cohort_2", cohort_2_dedup_ids, "negative"),
    ("Cohort_3", cohort_3_dedup_ids, "negative"),
]
cohort_agreement_rows: List[Dict[str, object]] = []
for cohort_name, cohort_ids, expected_label in cohort_definitions:
    n = len(cohort_ids)
    emerge_positive_n = len(cohort_ids & emerge_ids_raw)
    emerge_negative_n = n - emerge_positive_n
    agree_n = emerge_positive_n if expected_label == "positive" else emerge_negative_n
    disagree_n = n - agree_n
    other_cohort_ids = set().union(*[ids for name, ids, _ in cohort_definitions if name != cohort_name])
    overlap_with_other_cohorts_n = len(cohort_ids & other_cohort_ids)
    union_n = len(cohort_ids | emerge_ids_raw)
    jaccard_vs_emerge = emerge_positive_n / union_n if union_n else np.nan
    share_of_all_emerge_positive_rate = emerge_positive_n / len(emerge_ids) if len(emerge_ids) else np.nan

    if expected_label == "positive":
        tp, fp, fn, tn = emerge_positive_n, emerge_negative_n, np.nan, np.nan
        precision = tp / (tp + fp) if (tp + fp) else np.nan
        npv = np.nan
    else:
        tp, fp, fn, tn = np.nan, np.nan, emerge_positive_n, emerge_negative_n
        precision = np.nan
        npv = tn / (tn + fn) if (tn + fn) else np.nan
    cohort_agreement_rows.append({
        "cohort": cohort_name,
        "shire_expected_label": expected_label,
        "n_after_removing_overlap": n,
        "TP": tp,
        "FP": fp,
        "FN": fn,
        "TN": tn,
        "emerge_positive_n": emerge_positive_n,
        "emerge_negative_n": emerge_negative_n,
        "Precision_PPV_within_cohort": precision,
        "NPV_within_cohort": npv,
        "share_of_all_emerge_positive_n": emerge_positive_n,
        "share_of_all_emerge_positive_rate": share_of_all_emerge_positive_rate,
        "Jaccard_vs_emerge_positive": jaccard_vs_emerge,
        "agree_with_emerge_n": agree_n,
        "agree_with_emerge_rate": agree_n / n if n else np.nan,
        "disagree_with_emerge_n": disagree_n,
        "disagree_with_emerge_rate": disagree_n / n if n else np.nan,
        "overlap_with_other_cohorts_n": overlap_with_other_cohorts_n,
    })
cohort_agreement_df = pd.DataFrame(cohort_agreement_rows)
cohort_agreement_df.to_csv(OUTPUT_DIR / "reference_agreement_by_cohort.csv", index=False)

# =============================================================================
# Load every expected LLM output and calculate metrics against both references
# =============================================================================

print("\nLoading expected LLM outputs...")

available_csvs = {path.stem: path for path in RESULT_DIR.glob("*.csv")}
expected_stems: Set[str] = set()
rows: List[Dict[str, object]] = []

for model, model_display in MODEL_DISPLAY_NAMES.items():
    for prompt in expected_prompt_names(model):
        expected_stem = f"{model}_{prompt}"
        expected_stems.add(expected_stem)
        parsed = parse_prompt(prompt)
        path = available_csvs.get(expected_stem)

        if path is None:
            pred_ids: Set[str] = set()
            file_status = "missing_output"
            error_message = None
        else:
            pred_ids, file_status, error_message = safe_read_prediction_ids(path)

        executed = file_status in {"executed_nonzero", "executed_zero_rows"}
        usable_cohort = executed and len(pred_ids & shire_universe_ids) > 0
        pred_outside_universe = pred_ids - shire_universe_ids

        for reference_name, gold_ids in reference_gold_ids.items():
            if executed:
                metrics = compute_metrics(pred_ids, gold_ids, shire_universe_ids)
            else:
                metrics = {metric: np.nan for metric in [
                    "TP", "FP", "FN", "TN", "Predicted_Positive", "PPV", "Recall",
                    "F1", "Jaccard", "FPR", "Specificity", "Accuracy"
                ]}

            rows.append({
                "reference": reference_name,
                "model": model,
                "model_display": model_display,
                "prompt": prompt,
                "family": parsed["family"],
                "context_level": parsed["context_level"],
                "prompt_variant": parsed["prompt_variant"],
                "expected_file": f"{expected_stem}.csv",
                "file_found": path is not None,
                "file_status": file_status,
                "error_message": error_message,
                "executed": executed,
                "usable_cohort": usable_cohort,
                "n_predicted_raw": len(pred_ids),
                "n_predicted_in_universe": len(pred_ids & shire_universe_ids),
                "n_predicted_outside_universe": len(pred_outside_universe),
                **metrics,
            })

metrics_df = pd.DataFrame(rows)
metrics_df.to_csv(OUTPUT_DIR / "all_metrics_long.csv", index=False)

# Wide table: one row per model-prompt with side-by-side metrics for both references.
# Pivot only on the true row key. Using dropna=False with many index columns can
# make pandas build a huge Cartesian product of index levels and exhaust memory.
wide_id_cols = [
    "model", "model_display", "prompt", "family", "context_level", "prompt_variant",
    "expected_file", "file_found", "file_status", "executed", "usable_cohort",
    "n_predicted_raw", "n_predicted_in_universe", "n_predicted_outside_universe",
]
wide_value_cols = [
    "TP", "FP", "FN", "TN", "PPV", "Recall", "F1", "Jaccard", "FPR", "Specificity",
    "Accuracy",
]
wide_base = metrics_df[wide_id_cols].drop_duplicates(subset=["model", "prompt"])
wide_values = metrics_df.pivot(
    index=["model", "prompt"],
    columns="reference",
    values=wide_value_cols,
).reset_index()
wide_values.columns = [
    "__".join([str(x) for x in col if str(x) != ""]).rstrip("__") if isinstance(col, tuple) else str(col)
    for col in wide_values.columns
]
wide_metrics_df = wide_base.merge(wide_values, on=["model", "prompt"], how="left")
wide_metrics_df.to_csv(OUTPUT_DIR / "all_metrics_wide.csv", index=False)

unexpected_files = sorted(
    stem for stem in available_csvs
    if stem not in expected_stems and stem != STANDARD_FILE.stem
)
if unexpected_files:
    pd.DataFrame({"unexpected_csv_stem": unexpected_files}).to_csv(
        OUTPUT_DIR / "qc_unexpected_csv_files.csv", index=False
    )

print(f"  Expected prompt files: {len(expected_stems)}")
print(f"  Found expected files:  {metrics_df.loc[metrics_df['reference'] == REFERENCES[0], 'file_found'].sum()}")
print(f"  Missing expected files:{(~metrics_df.loc[metrics_df['reference'] == REFERENCES[0], 'file_found']).sum()}")

# Execution status breakdown: confirms whether every expected file actually
# executed, or whether some are missing/failed vs. executed with 0 predicted
# rows (which is a valid outcome, not a failure, but drives F1/PPV to 0/NaN).
status_rows = metrics_df[metrics_df["reference"] == REFERENCES[0]]
status_counts = status_rows["file_status"].value_counts()
execution_status_df = status_counts.rename_axis("file_status").reset_index(name="n_prompts")
execution_status_df.to_csv(OUTPUT_DIR / "qc_execution_status.csv", index=False)

# read_error is a genuine failure (unreadable CSV / no person_id column), distinct
# from executed_zero_rows (readable CSV, 0 predicted patients). List both by name
# so a read_error isn't mistaken for a harmless zero-row output.
status_detail_df = status_rows[status_rows["file_status"].isin(["read_error", "executed_zero_rows"])][
    ["model", "prompt", "expected_file", "file_status", "error_message"]
].sort_values(["file_status", "model", "prompt"])
status_detail_df.to_csv(OUTPUT_DIR / "qc_execution_status_detail.csv", index=False)

print("  Execution status breakdown:")
for status in ["executed_nonzero", "executed_zero_rows", "missing_output", "read_error"]:
    n = int(status_counts.get(status, 0))
    print(f"    {status:<20} {n}")
if status_counts.get("missing_output", 0) == 0 and status_counts.get("read_error", 0) == 0:
    print("  -> All expected prompts executed. Any 0/NaN metrics come from executed_zero_rows outputs, not missing files.")
if status_counts.get("read_error", 0) > 0:
    print("  WARNING: read_error means the CSV exists but could not be read (e.g. no person_id column). "
          "These are treated as unexecuted, NOT as zero-row outputs. See qc_execution_status_detail.csv.")
    for _, row in status_rows[status_rows["file_status"] == "read_error"].iterrows():
        print(f"    read_error: {row['expected_file']} -> {row['error_message']}")

# =============================================================================
# Analysis 1: QC comparison of level 1 vs level 2 implementations
# =============================================================================

print("\nAnalysis 1: level 1 vs level 2 implementation QC...")

qc_1_vs_2_rows: List[Dict[str, object]] = []
for reference in REFERENCES:
    ref_df = metrics_df[metrics_df["reference"] == reference]
    for model in MODEL_DISPLAY_NAMES:
        if "1" not in MODEL_LEVELS[model] or "2" not in MODEL_LEVELS[model]:
            continue
        for family in ["alpha", "beta"]:
            row_out: Dict[str, object] = {
                "reference": reference,
                "model": model,
                "model_display": MODEL_DISPLAY_NAMES[model],
                "family": family,
            }
            level_1 = ref_df[(ref_df["model"] == model) & (ref_df["family"] == family) & (ref_df["context_level"] == "1")]
            level_2 = ref_df[(ref_df["model"] == model) & (ref_df["family"] == family) & (ref_df["context_level"] == "2")]
            s1 = summarize_rows(level_1)
            s2 = summarize_rows(level_2)
            add_prefixed(row_out, "level1", s1)
            add_prefixed(row_out, "level2", s2)
            row_out["diff_level2_minus_level1_F1"] = s2["mean_F1_executed"] - s1["mean_F1_executed"]
            qc_1_vs_2_rows.append(row_out)

qc_1_vs_2_df = pd.DataFrame(qc_1_vs_2_rows)
qc_1_vs_2_df.to_csv(OUTPUT_DIR / "analysis1_level1_vs_level2_qc.csv", index=False)

# =============================================================================
# Analysis 2: Alpha vs beta prompting
# =============================================================================

print("Analysis 2: alpha vs beta prompting...")

alpha_beta_rows: List[Dict[str, object]] = []
context_groups: Dict[str, Sequence[str]] = {
    "level1": ["1"],
    "level2": ["2"],
    "limited_1_2_pooled": ["1", "2"],
    "full_3": ["3"],
}

for reference in REFERENCES:
    ref_df = metrics_df[metrics_df["reference"] == reference]
    for model in MODEL_DISPLAY_NAMES:
        available_levels = set(MODEL_LEVELS[model])
        for group_name, group_levels in context_groups.items():
            if not set(group_levels).issubset(available_levels):
                continue
            model_group = ref_df[(ref_df["model"] == model) & (ref_df["context_level"].isin(group_levels))]
            alpha_summary = summarize_rows(model_group[model_group["family"] == "alpha"])
            beta_summary = summarize_rows(model_group[model_group["family"] == "beta"])
            row_out: Dict[str, object] = {
                "reference": reference,
                "model": model,
                "model_display": MODEL_DISPLAY_NAMES[model],
                "context_group": group_name,
                "context_levels": ",".join(group_levels),
            }
            add_prefixed(row_out, "alpha", alpha_summary)
            add_prefixed(row_out, "beta", beta_summary)
            row_out["diff_beta_minus_alpha_F1"] = beta_summary["mean_F1_executed"] - alpha_summary["mean_F1_executed"]
            row_out["diff_beta_minus_alpha_execution_rate"] = beta_summary["execution_rate"] - alpha_summary["execution_rate"]
            alpha_beta_rows.append(row_out)

alpha_beta_df = pd.DataFrame(alpha_beta_rows)
alpha_beta_df.to_csv(OUTPUT_DIR / "analysis2_alpha_vs_beta.csv", index=False)

# Across-model paired exploratory tests; one row per model prevents treating prompt
# attempts as independent biological observations.
alpha_beta_test_rows: List[Dict[str, object]] = []
for reference in REFERENCES:
    for group_name in context_groups:
        subset = alpha_beta_df[
            (alpha_beta_df["reference"] == reference)
            & (alpha_beta_df["context_group"] == group_name)
        ].dropna(subset=["alpha_mean_F1_executed", "beta_mean_F1_executed"])
        if subset.empty:
            continue
        w_two, p_two = safe_wilcoxon(
            subset["alpha_mean_F1_executed"], subset["beta_mean_F1_executed"], "two-sided"
        )
        w_greater, p_greater = safe_wilcoxon(
            subset["alpha_mean_F1_executed"], subset["beta_mean_F1_executed"], "greater"
        )
        signs = sign_test(subset["diff_beta_minus_alpha_F1"])
        alpha_beta_test_rows.append({
            "reference": reference,
            "context_group": group_name,
            "n_models": len(subset),
            "alpha_mean_F1_across_models": subset["alpha_mean_F1_executed"].mean(),
            "beta_mean_F1_across_models": subset["beta_mean_F1_executed"].mean(),
            "wilcoxon_W_two_sided": w_two,
            "wilcoxon_p_two_sided": p_two,
            "wilcoxon_W_beta_greater": w_greater,
            "wilcoxon_p_beta_greater": p_greater,
            **signs,
            "note": "Exploratory across-model paired comparison; beta has fewer prompt attempts than alpha.",
        })

alpha_beta_tests_df = pd.DataFrame(alpha_beta_test_rows)
alpha_beta_tests_df.to_csv(OUTPUT_DIR / "analysis2_alpha_vs_beta_tests.csv", index=False)

# =============================================================================
# Analysis 3: Does full context (3) outperform limited context (1/2 pooled)?
# =============================================================================

print("Analysis 3: limited context (1/2 pooled) vs full context (3)...")

progression_rows: List[Dict[str, object]] = []
for reference in REFERENCES:
    ref_df = metrics_df[metrics_df["reference"] == reference]
    for model in MODEL_DISPLAY_NAMES:
        if not {"1", "2", "3"}.issubset(set(MODEL_LEVELS[model])):
            continue
        for family in ["alpha", "beta"]:
            model_family = ref_df[(ref_df["model"] == model) & (ref_df["family"] == family)]
            limited = summarize_rows(model_family[model_family["context_level"].isin(["1", "2"])])
            full = summarize_rows(model_family[model_family["context_level"] == "3"])
            row_out: Dict[str, object] = {
                "reference": reference,
                "model": model,
                "model_display": MODEL_DISPLAY_NAMES[model],
                "family": family,
            }
            add_prefixed(row_out, "limited_1_2", limited)
            add_prefixed(row_out, "full_3", full)
            row_out["diff_full3_minus_limited12_F1"] = full["mean_F1_executed"] - limited["mean_F1_executed"]
            row_out["improved_full3_F1"] = row_out["diff_full3_minus_limited12_F1"] > 0
            progression_rows.append(row_out)

progression_df = pd.DataFrame(progression_rows)
progression_df.to_csv(OUTPUT_DIR / "analysis3_context_progression_12_vs_3.csv", index=False)

progression_test_rows: List[Dict[str, object]] = []
for reference in REFERENCES:
    for family in ["alpha", "beta"]:
        subset = progression_df[
            (progression_df["reference"] == reference)
            & (progression_df["family"] == family)
        ].dropna(subset=["limited_1_2_mean_F1_executed", "full_3_mean_F1_executed"])
        w_two, p_two = safe_wilcoxon(
            subset["limited_1_2_mean_F1_executed"], subset["full_3_mean_F1_executed"], "two-sided"
        )
        w_greater, p_greater = safe_wilcoxon(
            subset["limited_1_2_mean_F1_executed"], subset["full_3_mean_F1_executed"], "greater"
        )
        signs = sign_test(subset["diff_full3_minus_limited12_F1"])
        progression_test_rows.append({
            "reference": reference,
            "family": family,
            "n_models": len(subset),
            "limited_1_2_mean_F1_across_models": subset["limited_1_2_mean_F1_executed"].mean(),
            "full_3_mean_F1_across_models": subset["full_3_mean_F1_executed"].mean(),
            "n_models_improved_full3": int(subset["improved_full3_F1"].sum()),
            "wilcoxon_W_two_sided": w_two,
            "wilcoxon_p_two_sided": p_two,
            "wilcoxon_W_full3_greater": w_greater,
            "wilcoxon_p_full3_greater": p_greater,
            **signs,
            "note": "Primary context comparison across all models.",
        })

progression_tests_df = pd.DataFrame(progression_test_rows)
progression_tests_df.to_csv(OUTPUT_DIR / "analysis3_context_progression_tests.csv", index=False)

# =============================================================================
# Analysis 4: Comparable model ranking using level 3 only
# =============================================================================

print("Analysis 4: model ranking on shared full-context level 3...")

ranking_rows: List[Dict[str, object]] = []
for reference in REFERENCES:
    ref_df = metrics_df[(metrics_df["reference"] == reference) & (metrics_df["context_level"] == "3")]
    for model in MODEL_DISPLAY_NAMES:
        model_rows = ref_df[ref_df["model"] == model]
        alpha = summarize_rows(model_rows[model_rows["family"] == "alpha"])
        beta = summarize_rows(model_rows[model_rows["family"] == "beta"])
        combined = summarize_rows(model_rows)
        row_out: Dict[str, object] = {
            "reference": reference,
            "model": model,
            "model_display": MODEL_DISPLAY_NAMES[model],
        }
        add_prefixed(row_out, "all_level3", combined)
        add_prefixed(row_out, "alpha_level3", alpha)
        add_prefixed(row_out, "beta_level3", beta)
        ranking_rows.append(row_out)

ranking_df = pd.DataFrame(ranking_rows)
ranking_df["rank"] = ranking_df.groupby("reference")["all_level3_mean_F1_executed"].rank(method="min", ascending=False).astype("Int64")
ranking_df = ranking_df.sort_values(["reference", "rank", "model_display"])
ranking_df.to_csv(OUTPUT_DIR / "analysis4_model_ranking_level3.csv", index=False)

# =============================================================================
# Analysis 5: Beta results by model and context level (all levels, standalone)
# =============================================================================
# Beta appears throughout Analyses 1-4, but always inside a QC/comparison slice
# (level1-vs-level2, alpha-vs-beta, or level-3-only ranking). This is the single
# table of every beta prompt's own metrics across all context levels, for when
# you just want to look at beta on its own.

print("Analysis 5: beta results by model and context level...")

beta_results_df = metrics_df[metrics_df["family"] == "beta"][[
    "reference", "model", "model_display", "context_level", "prompt",
    "file_status", "executed", "usable_cohort",
    "TP", "FP", "FN", "TN", "PPV", "Recall", "F1", "Jaccard", "Specificity", "Accuracy",
]].sort_values(["reference", "model_display", "context_level"])
beta_results_df.to_csv(OUTPUT_DIR / "analysis5_beta_results_by_level.csv", index=False)

# =============================================================================
# Figures
# =============================================================================

print("\nGenerating figures...")


def save_level3_ranking_plot(reference: str) -> None:
    data = ranking_df[ranking_df["reference"] == reference].sort_values("rank")
    fig, ax = plt.subplots(figsize=(10, 6))
    ax.barh(data["model_display"], data["all_level3_mean_F1_executed"])
    ax.set_xlabel("Mean F1 at level 3")
    ax.set_ylabel("Model")
    ax.set_title(f"Level-3 Model Ranking - {reference}")
    ax.set_xlim(0, 1.0)
    ax.invert_yaxis()
    for y, value in enumerate(data["all_level3_mean_F1_executed"]):
        ax.text(min(value + 0.01, 0.98), y, f"{value:.3f}", va="center", fontsize=9)
    fig.tight_layout()
    fig.savefig(OUTPUT_DIR / f"fig1_level3_ranking_{reference}.png", dpi=180)
    plt.close(fig)


def save_progression_plot(reference: str, family: str) -> None:
    data = progression_df[
        (progression_df["reference"] == reference)
        & (progression_df["family"] == family)
    ].copy()
    fig, ax = plt.subplots(figsize=(9, 6))
    for _, row in data.iterrows():
        ax.plot(
            ["Limited context\n(levels 1/2 pooled)", "Full context\n(level 3)"],
            [row["limited_1_2_mean_F1_executed"], row["full_3_mean_F1_executed"]],
            marker="o",
            label=row["model_display"],
        )
    ax.set_ylabel("Mean F1")
    ax.set_title(f"Context Progression ({family.title()}) - {reference}")
    ax.set_ylim(0, 1.0)
    ax.legend(fontsize=8, loc="best")
    fig.tight_layout()
    fig.savefig(OUTPUT_DIR / f"fig2_context_progression_{family}_{reference}.png", dpi=180)
    plt.close(fig)


def save_alpha_beta_plot(reference: str, group_name: str) -> None:
    data = alpha_beta_df[
        (alpha_beta_df["reference"] == reference)
        & (alpha_beta_df["context_group"] == group_name)
    ].sort_values("model_display")
    y = np.arange(len(data))
    width = 0.36
    fig, ax = plt.subplots(figsize=(10, 6))
    ax.barh(y - width / 2, data["alpha_mean_F1_executed"], height=width, label="Alpha")
    ax.barh(y + width / 2, data["beta_mean_F1_executed"], height=width, label="Beta")
    ax.set_yticks(y)
    ax.set_yticklabels(data["model_display"])
    ax.set_xlabel("Mean F1")
    ax.set_title(f"Alpha vs Beta - {group_name} - {reference}")
    ax.set_xlim(0, 1.0)
    ax.legend()
    fig.tight_layout()
    fig.savefig(OUTPUT_DIR / f"fig3_alpha_vs_beta_{group_name}_{reference}.png", dpi=180)
    plt.close(fig)


for reference in REFERENCES:
    save_level3_ranking_plot(reference)
    save_progression_plot(reference, "alpha")
    save_progression_plot(reference, "beta")
    save_alpha_beta_plot(reference, "limited_1_2_pooled")
    save_alpha_beta_plot(reference, "full_3")

# =============================================================================
# Additional Figures (matching synthetic analysis)
# =============================================================================

print("Generating additional figures...")

sns.set_theme(style="whitegrid", font_scale=1.1)
COLORS = sns.color_palette("tab10", n_colors=len(MODEL_DISPLAY_NAMES))
model_color_map = {m: COLORS[i] for i, m in enumerate(sorted(MODEL_DISPLAY_NAMES.keys()))}

CONTEXT_LEVELS_SHIRE = ["1", "2", "3"]

# emerge_t2dm_v5 is the sole reference for these additional plots.
PRIMARY_REF = "emerge_t2dm_v5"
ref_df_primary = metrics_df[metrics_df["reference"] == PRIMARY_REF]

# --- Fig 4_2: Heatmaps with beta as merged single-cell row below alpha ---
# Generic merged-row heatmap (alpha = one column per prompt, beta = one merged
# cell per context level), reused for F1, PPV (precision), and Recall.


def save_merged_row_heatmap(reference: str, value_col: str, metric_label: str, filename_key: str) -> None:
    # NaN cells (unexecuted/missing prompt outputs, or PPV undefined because a
    # zero-row output made no positive predictions) are displayed as 0 so the
    # grid stays fully filled; see summary_report.txt / module docstring for
    # why each cell is 0 versus a genuinely low nonzero score.
    ref_data = metrics_df[metrics_df["reference"] == reference]
    pivot_data = ref_data.pivot_table(index="model_display", columns="prompt", values=value_col, aggfunc="mean")
    pivot_data = pivot_data.fillna(0.0)

    # Alpha column order and context-level grouping info
    alpha_col_order = []
    context_groups_fig = []  # list of (context_level, start_col_idx, n_cols)
    for cl in CONTEXT_LEVELS_SHIRE:
        cols_cl = []
        for p in range(1, 6):
            col = f"a{cl}p{p}"
            if col in pivot_data.columns:
                cols_cl.append(col)
        if cols_cl:
            context_groups_fig.append((cl, len(alpha_col_order), len(cols_cl)))
            alpha_col_order.extend(cols_cl)

    n_alpha_cols = len(alpha_col_order)
    model_list = sorted(pivot_data.index.tolist())
    n_models = len(model_list)
    n_rows = n_models * 2

    # Build alpha data matrix
    alpha_matrix = np.full((n_models, n_alpha_cols), np.nan)
    for i, model_name in enumerate(model_list):
        for j, col in enumerate(alpha_col_order):
            if col in pivot_data.columns and model_name in pivot_data.index:
                alpha_matrix[i, j] = pivot_data.loc[model_name, col]

    # Get beta values per model per context level
    beta_values = {}
    for i, model_name in enumerate(model_list):
        for cl in CONTEXT_LEVELS_SHIRE:
            bcol = f"b{cl}"
            if bcol in pivot_data.columns and model_name in pivot_data.index:
                beta_values[(i, cl)] = pivot_data.loc[model_name, bcol]
            else:
                beta_values[(i, cl)] = np.nan

    vmin = 0
    vmax = 1
    cmap_obj = cm.get_cmap("RdYlGn")
    norm = Normalize(vmin=vmin, vmax=vmax)

    fig_height = max(8, n_rows * 0.38)
    fig_width = max(14, n_alpha_cols * 0.6)
    fig, ax = plt.subplots(figsize=(fig_width, fig_height))

    # Draw alpha cells
    for i in range(n_models):
        row_y = i * 2
        for j in range(n_alpha_cols):
            val = alpha_matrix[i, j]
            color = cmap_obj(norm(val)) if not np.isnan(val) else "white"
            rect = Rectangle((j, row_y), 1, 1, facecolor=color, edgecolor="gray", linewidth=0.5)
            ax.add_patch(rect)
            if not np.isnan(val):
                ax.text(j + 0.5, row_y + 0.5, f"{val:.3f}", ha="center", va="center", fontsize=10)

    # Draw beta cells (merged)
    for i in range(n_models):
        row_y = i * 2 + 1
        for cl, start_col, n_cols in context_groups_fig:
            val = beta_values.get((i, cl), np.nan)
            color = cmap_obj(norm(val)) if not np.isnan(val) else "white"
            rect = Rectangle((start_col, row_y), n_cols, 1, facecolor=color, edgecolor="gray", linewidth=0.5)
            ax.add_patch(rect)
            if not np.isnan(val):
                ax.text(start_col + n_cols / 2, row_y + 0.5, f"{val:.3f}",
                        ha="center", va="center", fontsize=10)

    ax.set_xlim(0, n_alpha_cols)
    ax.set_ylim(0, n_rows)
    ax.invert_yaxis()

    # Y-axis labels
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

    # X-axis bottom: beta labels
    ax2 = ax.secondary_xaxis("bottom")
    beta_tick_positions = []
    beta_tick_labels = []
    for cl, start_col, n_cols in context_groups_fig:
        beta_tick_positions.append(start_col + n_cols / 2)
        beta_tick_labels.append(f"b{cl}")
    ax2.set_xticks(beta_tick_positions)
    ax2.set_xticklabels(beta_tick_labels, fontsize=12)
    ax2.tick_params(length=0)

    # Horizontal lines to separate model groups
    for i in range(1, n_models):
        ax.axhline(i * 2, color="black", linewidth=1.5)

    # Vertical lines between context level groups
    for cl, start_col, n_cols in context_groups_fig:
        end_col = start_col + n_cols
        if end_col < n_alpha_cols:
            ax.axvline(end_col, color="black", linewidth=1.5)

    # Colorbar
    sm = cm.ScalarMappable(cmap=cmap_obj, norm=norm)
    sm.set_array([])
    cbar = plt.colorbar(sm, ax=ax, fraction=0.02, pad=0.02)
    cbar.set_label(metric_label)

    ax.set_title(f"{metric_label} Heatmap (α rows + merged β rows) - {reference}", pad=40)
    plt.tight_layout()
    plt.savefig(OUTPUT_DIR / f"fig4_2_{filename_key}_heatmap_{reference}.png", dpi=150)
    plt.close()


for reference in REFERENCES:
    save_merged_row_heatmap(reference, "F1", "F1", "f1")
    save_merged_row_heatmap(reference, "PPV", "Precision (PPV)", "ppv")
    save_merged_row_heatmap(reference, "Recall", "Recall", "recall")

# --- Fig 6: Recall vs PPV scatter (all prompts) ---
for reference in REFERENCES:
    ref_data = metrics_df[(metrics_df["reference"] == reference) & (metrics_df["executed"] == True)]
    fig, ax = plt.subplots(figsize=(10, 8))
    for model in MODEL_DISPLAY_NAMES:
        mdf = ref_data[ref_data["model"] == model]
        ax.scatter(mdf["Recall"], mdf["PPV"], label=MODEL_DISPLAY_NAMES.get(model, model),
                   color=model_color_map.get(model, "gray"), s=60, alpha=0.7, edgecolors="black", linewidth=0.3)
    ax.set_xlabel("Recall (Sensitivity)")
    ax.set_ylabel("PPV (Precision)")
    ax.set_title(f"Precision-Recall Space by Model - {reference}")
    ax.set_xlim(0, 1.05)
    ax.set_ylim(0, 1.05)
    ax.plot([0, 1], [0, 1], "--", color="gray", alpha=0.5)
    ax.legend(loc="upper left", fontsize=9)
    plt.tight_layout()
    plt.savefig(OUTPUT_DIR / f"fig6_recall_vs_ppv_{reference}.png", dpi=150)
    plt.close()

# --- Fig 6a: Recall vs PPV scatter (alpha only) ---
for reference in REFERENCES:
    ref_data = metrics_df[(metrics_df["reference"] == reference) & (metrics_df["executed"] == True) & (metrics_df["family"] == "alpha")]
    fig, ax = plt.subplots(figsize=(10, 8))
    for model in MODEL_DISPLAY_NAMES:
        mdf = ref_data[ref_data["model"] == model]
        ax.scatter(mdf["Recall"], mdf["PPV"], label=MODEL_DISPLAY_NAMES.get(model, model),
                   color=model_color_map.get(model, "gray"), s=60, alpha=0.7, edgecolors="black", linewidth=0.3)
    ax.set_xlabel("Recall (Sensitivity)")
    ax.set_ylabel("PPV (Precision)")
    ax.set_title(f"Precision-Recall Space (Alpha Only) - {reference}")
    ax.set_xlim(0, 1.05)
    ax.set_ylim(0, 1.05)
    ax.plot([0, 1], [0, 1], "--", color="gray", alpha=0.5)
    ax.legend(loc="upper left", fontsize=9)
    plt.tight_layout()
    plt.savefig(OUTPUT_DIR / f"fig6a_recall_vs_ppv_alpha_{reference}.png", dpi=150)
    plt.close()

# --- Fig 6b: Recall vs PPV scatter (beta only, marker shape = context level) ---
CONTEXT_MARKERS = {"1": "o", "2": "s", "3": "*"}
CONTEXT_MARKER_LABELS = {"1": "v1 (limited)", "2": "v2 (limited)", "3": "v3 (full)"}

for reference in REFERENCES:
    ref_data = metrics_df[(metrics_df["reference"] == reference) & (metrics_df["executed"] == True) & (metrics_df["family"] == "beta")]
    fig, ax = plt.subplots(figsize=(10, 8))
    model_handles = []
    plotted_models = set()
    plotted_contexts = set()
    for model in MODEL_DISPLAY_NAMES:
        for cl, marker in CONTEXT_MARKERS.items():
            mdf = ref_data[(ref_data["model"] == model) & (ref_data["context_level"] == cl)]
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

    context_handles = []
    for cl, marker in CONTEXT_MARKERS.items():
        if cl in plotted_contexts:
            h = ax.scatter([], [], marker=marker, color="gray", s=50, edgecolors="black", linewidth=0.4,
                           label=CONTEXT_MARKER_LABELS[cl])
            context_handles.append(h)

    ax.set_xlabel("Recall (Sensitivity)")
    ax.set_ylabel("PPV (Precision)")
    ax.set_title(f"Precision-Recall Space (Beta Only) - {reference}")
    ax.set_xlim(0, 1.05)
    ax.set_ylim(0, 1.05)
    ax.plot([0, 1], [0, 1], "--", color="gray", alpha=0.5)

    # Combined legend
    spacer1 = Line2D([], [], marker="None", linestyle="None", label="")
    model_title = Line2D([], [], marker="None", linestyle="None", label="")
    context_title = Line2D([], [], marker="None", linestyle="None", label="")
    all_handles = [model_title] + model_handles + [spacer1, context_title] + context_handles
    all_labels = (["── Model (color) ──"] +
                  [h.get_label() for h in model_handles] +
                  ["", "── Context (shape) ──"] +
                  [h.get_label() for h in context_handles])
    ax.legend(handles=all_handles, labels=all_labels, loc="upper left", fontsize=9)

    plt.tight_layout()
    plt.savefig(OUTPUT_DIR / f"fig6b_recall_vs_ppv_beta_{reference}.png", dpi=150)
    plt.close()

# --- Fig 8: F1 scores by context level per model (bar + line charts) ---
context_x_labels = [f"v{cl}" for cl in CONTEXT_LEVELS_SHIRE]

# --- Fig 8a: Bar chart - Beta F1 by model, grouped by context level ---
fig8_beta_data = []
for model in MODEL_DISPLAY_NAMES:
    for cl in MODEL_LEVELS[model]:
        beta_rows = ref_df_primary[(ref_df_primary["model"] == model) & (ref_df_primary["family"] == "beta") & (ref_df_primary["context_level"] == cl)]
        f1_val = beta_rows["F1"].values[0] if not beta_rows.empty and beta_rows["executed"].any() else np.nan
        fig8_beta_data.append({
            "model_display": MODEL_DISPLAY_NAMES[model],
            "context_level": cl,
            "F1": f1_val,
        })

fig8_beta_df = pd.DataFrame(fig8_beta_data)
fig8_beta_pivot = fig8_beta_df.pivot_table(index="model_display", columns="context_level", values="F1")
fig8_beta_pivot = fig8_beta_pivot[[cl for cl in CONTEXT_LEVELS_SHIRE if cl in fig8_beta_pivot.columns]]

fig, ax = plt.subplots(figsize=(12, 6))
fig8_beta_pivot.plot(kind="bar", ax=ax, edgecolor="black", linewidth=0.5)
ax.set_xlabel("Model")
ax.set_ylabel("F1 Score")
ax.set_title("Fig 8a: Beta F1 Score by Model and Context Level")
ax.set_ylim(0, 1.05)
ax.legend(title="Context Level", labels=[f"v{cl}" for cl in CONTEXT_LEVELS_SHIRE if cl in fig8_beta_pivot.columns],
          bbox_to_anchor=(1.02, 1), loc="upper left", fontsize=9)
ax.set_xticklabels(ax.get_xticklabels(), rotation=45, ha="right")
plt.tight_layout()
plt.savefig(OUTPUT_DIR / "fig8a_beta_f1_bar.png", dpi=150, bbox_inches="tight")
plt.close()

# --- Fig 8b: Bar chart - Beta F1 by context level, grouped by model ---
fig8_beta_pivot_t = fig8_beta_df.pivot_table(index="context_level", columns="model_display", values="F1")
fig8_beta_pivot_t = fig8_beta_pivot_t.loc[[cl for cl in CONTEXT_LEVELS_SHIRE if cl in fig8_beta_pivot_t.index]]
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
for model in MODEL_DISPLAY_NAMES:
    model_disp = MODEL_DISPLAY_NAMES[model]
    f1_vals = []
    for cl in CONTEXT_LEVELS_SHIRE:
        if cl not in MODEL_LEVELS[model]:
            f1_vals.append(np.nan)
            continue
        beta_rows = ref_df_primary[(ref_df_primary["model"] == model) & (ref_df_primary["family"] == "beta") & (ref_df_primary["context_level"] == cl)]
        f1_vals.append(beta_rows["F1"].values[0] if not beta_rows.empty and beta_rows["executed"].any() else np.nan)
    ax.plot(context_x_labels, f1_vals, marker="o", label=model_disp,
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

# --- Fig 8d: Bar chart - All prompts F1 per model (x = each prompt label) ---
# Each model gets its own subplot. X-axis shows every prompt: a1p1..a1p5, b1, a2p1..a2p5, b2, a3p1..a3p5, b3
# Bars colored by context level. NaN (missing) leaves a gap.
CONTEXT_COLORS_SHIRE = {"1": "#1f77b4", "2": "#ff7f0e", "3": "#2ca02c"}

# Build full prompt order for SHIRE (levels 1, 2, 3)
all_prompt_order_shire = []
for cl in CONTEXT_LEVELS_SHIRE:
    for p in range(1, 6):
        all_prompt_order_shire.append(f"a{cl}p{p}")
    all_prompt_order_shire.append(f"b{cl}")

fig, axes = plt.subplots(2, 4, figsize=(22, 10))
axes_flat = axes.flat
model_list_sorted = sorted(MODEL_DISPLAY_NAMES.keys(), key=lambda m: MODEL_DISPLAY_NAMES[m])

for idx, model in enumerate(model_list_sorted):
    if idx >= len(axes_flat):
        break
    ax = axes_flat[idx]
    model_disp = MODEL_DISPLAY_NAMES[model]
    model_data = ref_df_primary[ref_df_primary["model"] == model]

    f1_vals = []
    bar_colors = []
    for prompt in all_prompt_order_shire:
        row = model_data[model_data["prompt"] == prompt]
        if not row.empty and row["executed"].any():
            f1_vals.append(row["F1"].values[0])
        else:
            f1_vals.append(np.nan)
        cl = prompt[1]  # context level character
        bar_colors.append(CONTEXT_COLORS_SHIRE.get(cl, "gray"))

    x_pos = np.arange(len(all_prompt_order_shire))
    for i, (val, color) in enumerate(zip(f1_vals, bar_colors)):
        if not np.isnan(val):
            ax.bar(i, val, color=color, edgecolor="black", linewidth=0.3, width=0.8)

    ax.set_title(model_disp, fontsize=10)
    ax.set_ylim(0, 1.05)
    ax.set_xticks(x_pos)
    ax.set_xticklabels(all_prompt_order_shire, fontsize=5.5, rotation=90)
    ax.set_ylabel("F1")

    # Vertical separators between context groups
    offset = 0
    for cl in CONTEXT_LEVELS_SHIRE:
        offset += 6  # 5 alpha + 1 beta
        if offset < len(all_prompt_order_shire):
            ax.axvline(offset - 0.5, color="black", linewidth=0.8, linestyle=":")

for idx in range(len(model_list_sorted), len(axes_flat)):
    axes_flat[idx].set_visible(False)

# Shared legend for context levels
context_legend_handles = [plt.Rectangle((0, 0), 1, 1, facecolor=CONTEXT_COLORS_SHIRE[cl], edgecolor="black", linewidth=0.5)
                          for cl in CONTEXT_LEVELS_SHIRE]
fig.legend(context_legend_handles, [f"Context v{cl}" for cl in CONTEXT_LEVELS_SHIRE],
           title="Context Level", bbox_to_anchor=(1.0, 0.5), loc="center left", fontsize=9)
fig.suptitle("Fig 8d: F1 Score per Prompt per Model (all alpha + beta)", fontsize=13)
plt.tight_layout(rect=[0, 0, 0.95, 0.96])
plt.savefig(OUTPUT_DIR / "fig8d_alpha_f1_bar_per_model.png", dpi=150, bbox_inches="tight")
plt.close()

# --- Fig 8e: Line chart - Alpha mean F1 across context levels per model ---
fig, ax = plt.subplots(figsize=(10, 6))
for model in MODEL_DISPLAY_NAMES:
    model_disp = MODEL_DISPLAY_NAMES[model]
    mean_f1_vals = []
    for cl in CONTEXT_LEVELS_SHIRE:
        if cl not in MODEL_LEVELS[model]:
            mean_f1_vals.append(np.nan)
            continue
        alpha_rows = ref_df_primary[(ref_df_primary["model"] == model) & (ref_df_primary["family"] == "alpha") & (ref_df_primary["context_level"] == cl) & (ref_df_primary["executed"] == True)]
        mean_f1_vals.append(alpha_rows["F1"].mean() if not alpha_rows.empty else np.nan)
    ax.plot(context_x_labels, mean_f1_vals, marker="s", label=model_disp,
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

# --- Fig 9: Beta F1 (mean & best across models) vs eMERGE, compared to Cohort_1 baseline ---
# Cohort_1 baseline: treating the SHIRE Cohort_1 labels themselves as a "prediction"
# scored against eMERGE (the same reference_agreement computed earlier), i.e. how
# well a simple site-labeled positive cohort would score if it were an LLM output.
cohort1_baseline_f1 = reference_agreement["F1"]

fig9_beta_f1_by_context = {}
for cl in CONTEXT_LEVELS_SHIRE:
    f1_vals = []
    for model in MODEL_DISPLAY_NAMES:
        if cl not in MODEL_LEVELS[model]:
            continue
        beta_rows = ref_df_primary[(ref_df_primary["model"] == model) & (ref_df_primary["family"] == "beta") & (ref_df_primary["context_level"] == cl)]
        if not beta_rows.empty and beta_rows["executed"].any():
            f1_vals.append(beta_rows["F1"].values[0])
    fig9_beta_f1_by_context[cl] = f1_vals

fig9_mean_f1_vals = [np.mean(fig9_beta_f1_by_context[cl]) if fig9_beta_f1_by_context[cl] else np.nan for cl in CONTEXT_LEVELS_SHIRE]
fig9_best_f1_vals = [np.max(fig9_beta_f1_by_context[cl]) if fig9_beta_f1_by_context[cl] else np.nan for cl in CONTEXT_LEVELS_SHIRE]

fig, ax = plt.subplots(figsize=(9, 6))
ax.plot(context_x_labels, fig9_mean_f1_vals, marker="o", label="LLM mean F1 (beta)",
        color="#1f77b4", linewidth=2, markersize=8)
ax.plot(context_x_labels, fig9_best_f1_vals, marker="^", label="LLM best F1 (beta)",
        color="#2ca02c", linewidth=2, markersize=8)
ax.axhline(cohort1_baseline_f1, color="black", linestyle="--", linewidth=1.5,
           label=f"Cohort_1 baseline (F1={cohort1_baseline_f1:.3f})")
ax.set_xlabel("Context Level")
ax.set_ylabel("F1 Score (vs eMERGE ground truth)")
ax.set_title("Fig 9: Beta F1 (Mean & Best Across Models) vs eMERGE, Compared to Cohort_1 Baseline")
ax.set_ylim(0, 1.05)
ax.legend(loc="upper left", fontsize=9)
ax.grid(True, alpha=0.3)
plt.tight_layout()
plt.savefig(OUTPUT_DIR / "fig9_beta_f1_mean_best_vs_cohort1_baseline.png", dpi=150, bbox_inches="tight")
plt.close()

# =============================================================================
# Text summary report
# =============================================================================

print("Writing summary report...")

report: List[str] = []
report.append("=" * 88)
report.append("T2DM PHENOTYPE PREDICTION ANALYSIS - SHIRE REAL DATA")
report.append("=" * 88)
report.append("")
report.append(f"Labeled SHIRE universe (after removing overlapping patients): {len(shire_universe_ids)} patients")
report.append(f"  Cohort_1 positive:     {len(shire_positive_ids)}")
report.append(f"  Cohort_2/3 negative:   {len(shire_negative_ids)}")
for _, row in cohort_counts_df.iterrows():
    report.append(
        f"    {row['cohort']:<22} raw={int(row['n_raw']):<8} "
        f"removed_as_overlap={int(row['n_removed_as_overlap']):<6} -> "
        f"n_after_removing_overlap={int(row['n_after_removing_overlap'])}"
    )
report.append(f"eMERGE t2dm_v5 positives within labeled universe: {len(emerge_ids)}")
report.append(f"eMERGE IDs excluded because outside labeled universe: {len(emerge_outside_universe)}")
report.append("")
report.append("EXECUTION STATUS (all expected model x prompt outputs)")
for status in ["executed_nonzero", "executed_zero_rows", "missing_output", "read_error"]:
    n = int(status_counts.get(status, 0))
    report.append(f"  {status:<20} {n}")
if status_counts.get("missing_output", 0) == 0 and status_counts.get("read_error", 0) == 0:
    report.append("  -> All expected prompts executed. Any 0/NaN metrics below come from executed_zero_rows outputs (0 predicted patients), not missing files.")
if status_counts.get("read_error", 0) > 0:
    report.append("  NOTE: read_error means the CSV exists but could not be read (e.g. no person_id column) -- treated as unexecuted, distinct from executed_zero_rows. See qc_execution_status_detail.csv for the file list and error messages.")
    for _, row in status_rows[status_rows["file_status"] == "read_error"].iterrows():
        report.append(f"    read_error: {row['expected_file']} -> {row['error_message']}")
if status_counts.get("executed_zero_rows", 0) > 0:
    for _, row in status_rows[status_rows["file_status"] == "executed_zero_rows"].iterrows():
        report.append(f"    executed_zero_rows: {row['expected_file']}")
report.append("")
report.append("REFERENCE AGREEMENT: SHIRE Cohort_1 vs eMERGE t2dm_v5 (eMERGE is the reference standard; universe after removing overlapping patients)")
report.append(f"  Recall (Sensitivity) = {fmt_num(reference_agreement['Recall'])}  -- fraction of eMERGE-positive patients Cohort_1 captures (TP={fmt_num(reference_agreement['TP'], 0)}, FN={fmt_num(reference_agreement['FN'], 0)})")
report.append(f"  Precision (PPV)      = {fmt_num(reference_agreement['PPV'])}  -- fraction of Cohort_1 confirmed positive by eMERGE (TP={fmt_num(reference_agreement['TP'], 0)}, FP={fmt_num(reference_agreement['FP'], 0)})")
report.append(f"  Jaccard              = {fmt_num(reference_agreement['Jaccard'])}  -- |Cohort_1 ∩ eMERGE+| / |Cohort_1 ∪ eMERGE+|")
report.append(f"  F1={fmt_num(reference_agreement['F1'])} | PPV={fmt_num(reference_agreement['PPV'])} | Recall={fmt_num(reference_agreement['Recall'])} | Jaccard={fmt_num(reference_agreement['Jaccard'])} | FPR={fmt_num(reference_agreement['FPR'])}")
report.append("")
report.append("REFERENCE AGREEMENT BY COHORT (eMERGE is the reference standard; counts after removing overlapping patients; Cohort_1/2/3 may carry different meaning; broken out in case they disagree with eMERGE differently)")
for _, row in cohort_agreement_df.iterrows():
    cell_label, cell_agree, cell_disagree = (
        ("TP/FP", "TP", "FP") if row["shire_expected_label"] == "positive" else ("FN/TN", "TN", "FN")
    )
    metric_label, metric_value = (
        ("Precision(PPV)", row["Precision_PPV_within_cohort"]) if row["shire_expected_label"] == "positive"
        else ("NPV", row["NPV_within_cohort"])
    )
    report.append(
        f"  {row['cohort']:<10} expected={row['shire_expected_label']:<9} n={int(row['n_after_removing_overlap']):<6} "
        f"[{cell_label}]={fmt_num(row[cell_agree], 0)}/{fmt_num(row[cell_disagree], 0)} | "
        f"{metric_label}={fmt_num(metric_value)} | "
        f"share_of_all_eMERGE_positives={fmt_num(row['share_of_all_emerge_positive_rate'])} | "
        f"Jaccard_vs_eMERGE_positive={fmt_num(row['Jaccard_vs_emerge_positive'])} | "
        f"overlap_with_other_cohorts={int(row['overlap_with_other_cohorts_n'])}"
    )
report.append("")
report.append("Prompt design:")
report.append("  - Levels 1 and 2 are two parallel implementations of the same limited-context approach.")
report.append("  - Primary progression question: do pooled levels 1/2 perform worse than level 3?")
report.append("  - Gemma has levels 1, 2, and 3, like every other model, and is included in all analyses.")

report.append("\n" + "=" * 88)
report.append("ANALYSIS 1: LEVEL 1 VS LEVEL 2 IMPLEMENTATION QC")
report.append("=" * 88)
report.append("These are parallel implementations of the same limited-context approach; this is a QC check, not the primary hypothesis test.")
for family in ["alpha", "beta"]:
    fam = qc_1_vs_2_df[qc_1_vs_2_df["family"] == family]
    report.append(f"  {family.title()}:")
    for _, row in fam.iterrows():
        report.append(
            f"    {row['model_display']:<22} level1={fmt_num(row['level1_mean_F1_executed'])} -> "
            f"level2={fmt_num(row['level2_mean_F1_executed'])} | diff={fmt_num(row['diff_level2_minus_level1_F1'])}"
        )

report.append("\n" + "=" * 88)
report.append("ANALYSIS 2: ALPHA VS BETA PROMPTING")
report.append("=" * 88)
report.append("Primary descriptive metric: mean F1 across executed prompts.")
for _, row in alpha_beta_tests_df.iterrows():
    report.append(
        f"  {row['context_group']:<20} alpha={fmt_num(row['alpha_mean_F1_across_models'])} | "
        f"beta={fmt_num(row['beta_mean_F1_across_models'])} | "
        f"beta better in {int(row['n_positive'])}/{int(row['n_non_tie']) if int(row['n_non_tie']) else 0} non-tied models | "
        f"Wilcoxon one-sided p={fmt_num(row['wilcoxon_p_beta_greater'])}"
    )
report.append("  Note: Wilcoxon tests are exploratory because alpha and beta use different numbers of generated attempts.")

report.append("\n" + "=" * 88)
report.append("ANALYSIS 3: LIMITED CONTEXT (LEVELS 1/2 POOLED) VS FULL CONTEXT (LEVEL 3)")
report.append("=" * 88)
for _, row in progression_tests_df.iterrows():
    report.append(
        f"  {row['family'].title():<6} limited={fmt_num(row['limited_1_2_mean_F1_across_models'])} -> "
        f"full={fmt_num(row['full_3_mean_F1_across_models'])} | "
        f"improved in {int(row['n_models_improved_full3'])}/{int(row['n_models'])} models | "
        f"Wilcoxon one-sided p={fmt_num(row['wilcoxon_p_full3_greater'])}"
    )

report.append("\n" + "=" * 88)
report.append("ANALYSIS 4: MODEL RANKING ON COMMON FULL-CONTEXT LEVEL 3")
report.append("=" * 88)
report.append("Ranking uses all six expected level-3 outputs per model: five alpha attempts plus one beta output.")
for _, row in ranking_df.sort_values("rank").iterrows():
    report.append(
        f"  {int(row['rank'])}. {row['model_display']:<22} "
        f"F1={fmt_num(row['all_level3_mean_F1_executed'])} | "
        f"Exec={int(row['all_level3_n_executed'])}/{int(row['all_level3_n_expected'])} ({row['all_level3_execution_rate']:.0%}) | "
        f"Alpha={fmt_num(row['alpha_level3_mean_F1_executed'])} | Beta={fmt_num(row['beta_level3_mean_F1_executed'])}"
    )

report.append("\n" + "=" * 88)
report.append("ANALYSIS 5: BETA RESULTS BY MODEL AND CONTEXT LEVEL (all levels, own metrics vs eMERGE)")
report.append("=" * 88)
for reference in REFERENCES:
    ref_beta = beta_results_df[beta_results_df["reference"] == reference]
    for _, row in ref_beta.iterrows():
        report.append(
            f"  {row['model_display']:<22} v{row['context_level']} ({row['prompt']:<3}) "
            f"status={row['file_status']:<17} "
            f"F1={fmt_num(row['F1'])} | PPV={fmt_num(row['PPV'])} | Recall={fmt_num(row['Recall'])} | Jaccard={fmt_num(row['Jaccard'])}"
        )

report.append("\n" + "=" * 88)
report.append("OUTPUT FILES")
report.append("=" * 88)
for output_path in sorted(OUTPUT_DIR.glob("*")):
    report.append(f"  - {output_path.name}")

report_text = "\n".join(report)
(OUTPUT_DIR / "summary_report.txt").write_text(report_text, encoding="utf-8")

print("\n" + report_text)
print(f"\nDone. Outputs saved to: {OUTPUT_DIR}")
