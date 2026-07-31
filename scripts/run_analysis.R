#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# run_analysis.R -- end-to-end pipeline.
#
# Usage:
#   Rscript scripts/run_analysis.R              # normal run (uses cache)
#   Rscript scripts/run_analysis.R --refresh    # force re-download
#   Rscript scripts/run_analysis.R --offline    # committed snapshot only
#
# Must be run from the project root.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(quantmod)
  library(xts)
  library(zoo)
  library(ggplot2)
  library(tidyr)
  library(scales)
  library(sandwich)
  library(lmtest)
  library(tseries)
  library(yaml)
})

args    <- commandArgs(trailingOnly = TRUE)
refresh <- "--refresh" %in% args
offline <- "--offline" %in% args

if (!dir.exists("R") || !file.exists("config/config.yml")) {
  stop("Run this script from the project root, e.g.\n",
       "  Rscript scripts/run_analysis.R", call. = FALSE)
}

for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)

t_start <- Sys.time()
set.seed(42)

log_step("FINANCIAL MARKET ANALYSIS -- CAPM STUDY")

cfg <- load_config()
if (offline) cfg$offline <- TRUE
log_msg("sample: ", format(cfg$start_date), " to ", format(cfg$end_date))
log_msg("mode:   ", if (isTRUE(cfg$offline)) "offline (snapshot)" else "online (Yahoo Finance)")

# -- 1. Data ----------------------------------------------------------------
log_step("1/6  Data acquisition")
monthly <- get_monthly_panel(cfg, refresh = refresh)

# -- 2. Returns -------------------------------------------------------------
log_step("2/6  Return construction")
data <- build_excess_returns(monthly, cfg)

labels <- c(cfg$assets, stats::setNames(list(cfg$market_label), data$market_col))
desc_excess <- describe_returns(data$excess, labels)
desc_total  <- describe_returns(data$returns, labels)

write_table(desc_excess, file.path(cfg$table_dir, "descriptive_excess_returns.csv"))
write_table(desc_total,  file.path(cfg$table_dir, "descriptive_total_returns.csv"))

cat("\nAnnualised summary (excess returns)\n")
print(data.frame(
  Asset        = desc_excess$name,
  Months       = desc_excess$n_months,
  `Ann.arith`  = sprintf("%7.2f%%", 100 * desc_excess$ann_return_arith),
  `CAGR`       = sprintf("%7.2f%%", 100 * desc_excess$cagr),
  `Ann.vol`    = sprintf("%7.2f%%", 100 * desc_excess$ann_vol),
  Sharpe       = sprintf("%6.2f",   desc_excess$sharpe),
  `Max.DD`     = sprintf("%7.2f%%", 100 * desc_excess$max_drawdown),
  check.names  = FALSE
), row.names = FALSE)

# -- 3. CAPM ----------------------------------------------------------------
log_step("3/6  CAPM estimation (Newey-West HAC inference)")
capm <- run_all_capm(data, cfg)
write_table(capm, file.path(cfg$table_dir, "capm_estimates.csv"))

capm_table <- format_capm_table(capm)
write_table(capm_table, file.path(cfg$table_dir, "capm_summary.csv"))
cat("\n")
print(capm_table, row.names = FALSE)
cat("\nSignificance of alpha (HAC): *** p<0.01, ** p<0.05, * p<0.10\n")

# -- 4. Rolling betas -------------------------------------------------------
log_step("4/6  Rolling-window betas")
roll <- rolling_betas(data, window = cfg$rolling_window_months)
if (!is.null(roll)) {
  write_table(roll, file.path(cfg$table_dir, "rolling_betas.csv"))
}

log_step("5/6  Beta stability tests (Chow-type, HAC)")
stability <- test_beta_stability(data, cfg)
if (!is.null(stability)) {
  write_table(stability, file.path(cfg$table_dir, "beta_stability.csv"))
  cat("\n")
  print(format_stability_table(stability), row.names = FALSE)
  cat("\nChow p-value tests the joint null of no shift in intercept or slope.\n")
  cat("*** p<0.01, ** p<0.05, * p<0.10\n")
}

corr <- stats::cor(zoo::coredata(data$excess), use = "complete.obs")
write_table(data.frame(series = rownames(corr), round(corr, 4)),
            file.path(cfg$table_dir, "correlation_matrix.csv"))

# -- 5. Figures -------------------------------------------------------------
log_step("6/6  Figures")
make_all_figures(data, capm, roll, cfg, stability)

# -- Provenance -------------------------------------------------------------
writeLines(
  c(paste("Generated:", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
    paste("Sample:", format(min(zoo::index(data$excess))), "to",
          format(max(zoo::index(data$excess)))),
    paste("Observations:", nrow(data$excess)),
    "",
    capture.output(utils::sessionInfo())),
  file.path(cfg$table_dir, "session_info.txt")
)

log_step(sprintf("DONE in %.1f seconds", 
                 as.numeric(difftime(Sys.time(), t_start, units = "secs"))))
log_msg("tables  -> ", cfg$table_dir)
log_msg("figures -> ", cfg$figure_dir)
