# T2DM standard corrections v4

## Why v4 was needed
Validation against the synthetic OMOP database showed that the prior diagnosis reconstruction still contaminated the T1DM exclusion bucket. In the mapped concept audit, the T1 bucket included standard concepts such as **Type 2 diabetes mellitus**, which caused `t1dm_dx_dt_cnt` and `t2dm_dx_dt_cnt` to collapse onto the same patient population and forced the final classifier to return zero rows.

## What changed in v4

### 1. Diagnosis concept sets now explicitly de-overlap T1DM and T2DM
The full-OMOP diagnosis logic now:
- builds T1DM descendants from the standard concept **Type 1 diabetes mellitus** using `concept_ancestor`
- builds T2DM descendants from the standard concept **Type 2 diabetes mellitus** using `concept_ancestor`
- computes the intersection of the two descendant sets
- removes that overlap from **both** the T1DM and T2DM diagnosis buckets before creating diagnosis-date counts

This change is the main fix for the previously observed T1 contamination issue.

### 2. Everything else stays aligned with v3
Unchanged from v3:
- same 5-path eMERGE-style case flow
- same distinct diagnosis-date counting logic
- same earliest T1DM medication date logic
- same earliest T2DM medication date logic
- same abnormal lab thresholds and logic
- same executable approximation for Path 5 (`>= 2` distinct T2DM diagnosis dates when T1 medication exists and T2 medication does not)

## What v4 does **not** claim
This is still a **best-effort operationalization** of the published eMERGE case algorithm, not a guaranteed exact reproduction. In particular:
- Path 5 remains an approximation because physician-entered diagnosis provenance was not available reliably in the synthetic implementation.
- The standard concept hierarchy itself may still include concepts that behave differently from the original appendix code tables, but v4 removes the direct T1/T2 contamination that was causing total collapse.

## Recommended validation after running v4
Re-run the diagnosis overlap audit and confirm:
- `t2_people` is no longer identical to `t1_people`
- overlap is much smaller than before
- the final classifier returns a non-zero cohort

Then compare performance against:
- the prior standard implementation
- SHIRE corrected implementation
- your labeled cohort metrics
