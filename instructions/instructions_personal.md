# Personal Domain Instructions — <User's name here>

Project- and domain-specific rules extracted from the generalized `instructions.md`. These apply to personal projects and HPC environments. Load this alongside `instructions.md` when working in those repos.

---

## 1. SLURM / HPC / GPU

- **`PYTHONUNBUFFERED=1` in all batch/SLURM scripts** so output appears in logs immediately.
- **SBATCH: use job arrays for embarrassingly parallel work** (one job per unit), not for-loops submitting individual jobs.
- **Do not assign `--mem` unless needed for scheduling. Do not set `--time` unless required.**
- **Singularity: one `singularity exec` wrapping the entire bash script** — never per-process singularity calls.
- **Never change SIF references** in scripts with actively running jobs.
- **Multi-GPU distribution:** `JOB_COUNT % N_GPUS` round-robin in the main shell, not subshell functions.
- **Multi-machine coordination on shared filesystems:** lock/done files — `mkdir` for atomic claim, touch `.done` on success, `rmdir` on failure.
- **Print node name, GPU info, and RAM reserved at job start** for debugging.
- **Save models to `{hostname}/` subdirectories** to prevent overwrites between machines.

## 2. Research Data & Reproducibility

- **Train/val/test splits** — no positional or data leakage.
- **Document data provenance:** what input file, what dataset or reference, what truth set, what parameters.
- **Guard external calls with try/except per-record,** not per-run.

## 3. SV Model Metrics & Evaluation

- **Always report metrics by data type × size bin.** Never just overall accuracy.
- **Show TP, FP, FN** — not just recall or accuracy. Include precision alongside recall — 90% recall at 10% precision is useless.
- **Report balanced accuracy** (mean per-class recall) for imbalanced datasets.
- **When comparing models, show the same metrics side-by-side in a table.**
- **When val accuracy differs significantly from test, investigate before celebrating.**

## 4. Training & Model Development

- **Use balanced accuracy for early stopping and LR scheduling,** not val_loss — and make the metric configurable (`--early-stop {bal_acc, val_loss}`).
- **Save the checkpoint that maximizes the chosen metric,** not just the latest; verify the saved checkpoint actually captures the best epoch.
- **Report per-class recall in training logs,** not just overall accuracy.
- **Sweep hyperparameters systematically:** coarse grid first, then fine grid around winners. **Use consistent data splits across all experiments.**
- **When features change, rebuild datasets and retrain** — never mix old and new features.

## 5. Feature Engineering

- **Always include ALL signal variants** (raw + z-score + derived) without being asked.
- **Normalization is technology-agnostic:** relative measures (fractions, ratios, z-scores), not absolute counts. Statistics/normalization constants computed from data, never hardcoded for a specific unique dataset or dataset with different treatments or curation.
- **When adding features, ADD alongside existing ones** — never remove or replace working features.
- **Document every feature** with its mathematical definition, value range, and physical meaning in `features.md`.
- **Verify train/inference consistency:** features built from arrays (training) must match features from BAM reads (inference). When a normalization uses a denominator, verify it represents the correct quantity (e.g., overlapping reads vs. read starts).

## 6. Pipeline & Analysis Conventions

- **Mirror the pipeline in the analysis document.** If the pipeline is scoring → overlaps → graph → models → value expansion, the analysis follows the same order.
- **Each architecture/dataset type gets the same section structure** for consistency.
- **Mark legacy results** (old code) with `*` or similar; new results are clean/unmarked.
- **Independent jobs run in parallel** — e.g., Indendent datasets that don't serialize.

## 7. Standard Project Files

- `features.md` — exhaustive documentation of every input feature with math and examples.
- `progress.md` — project progress tracker, updated as milestones are reached.
- `TASKS.md` — persistent task list per `instructions.md` §3.
- `CLAUDE.md` — project-specific instructions for AI assistants, including which communication mode (expert/instructional) the User has chosen for the project.
