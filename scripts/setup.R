#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# setup.R -- install every dependency. Run once:  Rscript scripts/setup.R
# ---------------------------------------------------------------------------

pkgs <- c(
  "quantmod",   # Yahoo Finance download
  "xts",        # time-indexed matrices
  "zoo",        # na.locf and index helpers
  "ggplot2",    # figures
  "tidyr",      # pivot_longer
  "scales",     # axis formatting
  "sandwich",   # Newey-West HAC covariance
  "lmtest",     # coeftest, Durbin-Watson, Breusch-Pagan
  "tseries",    # Jarque-Bera
  "yaml",       # configuration
  "testthat"    # unit tests
)

missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]

if (length(missing) == 0) {
  cat("All", length(pkgs), "dependencies are already installed.\n")
} else {
  cat("Installing:", paste(missing, collapse = ", "), "\n\n")
  install.packages(missing, repos = "https://cloud.r-project.org")
}

still_missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(still_missing) > 0) {
  stop("Failed to install: ", paste(still_missing, collapse = ", "),
       "\nOn Linux you may need system libraries: libcurl4-openssl-dev, ",
       "libssl-dev, libxml2-dev.", call. = FALSE)
}

cat("\nSetup complete. Next:\n\n")
cat("  From a shell (PowerShell / bash):\n")
cat("    Rscript tests/testthat.R\n")
cat("    Rscript scripts/run_analysis.R\n\n")
cat("  From the R console (prompt '>'):\n")
cat("    source(\"tests/testthat.R\")\n")
cat("    source(\"scripts/run_analysis.R\")\n")
