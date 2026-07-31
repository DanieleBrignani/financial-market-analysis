# Pre-publication checklist

The repository is not publishable straight from the archive: three artefacts are
produced by running it, and the README references them.

## 1. Run the pipeline

From the R console, in the project root:

```r
source("scripts/setup.R")        # once
source("tests/testthat.R")       # expect [ FAIL 0 | PASS 15 ]
source("scripts/run_analysis.R")
```

## 2. Check that everything was produced

```r
list.files("output/figures")     # expect 7 .png
list.files("output/tables")      # expect 7 .csv + session_info.txt
file.exists("data/processed/monthly_prices.csv")   # must be TRUE
```

## 3. Fill in the results

Open `output/tables/capm_summary.csv` and `output/tables/beta_stability.csv`,
and replace the "Numbers pending re-run" block in `README.md` with the measured
values. Cite `p (beta shift)` for any claim about beta constancy, and
`p (joint Chow)` only for claims about a break in the relation as a whole.

## 4. Move out of OneDrive

OneDrive syncing a `.git` directory corrupts repositories. Move the project to
e.g. `C:\Projects\financial-market-analysis` before initialising git.

## 5. Publish

```bash
git init
git add .
git commit -m "CAPM analysis: reproducible pipeline with HAC inference and structural-break tests"
git branch -M main
git remote add origin https://github.com/<user>/financial-market-analysis.git
git push -u origin main
```

Confirm that `data/processed/monthly_prices.csv` and `output/figures/*.png` are
in the commit — `.gitignore` keeps them deliberately, and CI plus the README
images both depend on them.

## 6. Verify

- The rolling-beta image renders on the GitHub project page.
- The Actions tab shows a green run.
- No "Numbers pending re-run" text remains in the README.
