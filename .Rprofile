# Project-level defaults. Loaded automatically when R starts in this directory,
# which is what makes `Rscript scripts/run_analysis.R` behave identically in
# VS Code, RStudio and CI.
options(
  stringsAsFactors      = FALSE,
  scipen                = 999,        # no scientific notation in printed output
  digits                = 6,
  warn                  = 1,          # surface warnings as they happen
  repos                 = c(CRAN = "https://cloud.r-project.org"),
  timeout               = 300,        # Yahoo can be slow
  readr.show_col_types  = FALSE
)

if (interactive()) {
  cat("financial-market-analysis\n")
  cat("  Rscript scripts/run_analysis.R   |   Rscript tests/testthat.R\n\n")
}
