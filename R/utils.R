# ---------------------------------------------------------------------------
# utils.R -- configuration, logging and small shared helpers.
# ---------------------------------------------------------------------------

load_config <- function(path = "config/config.yml") {
  if (!file.exists(path)) {
    stop("Config file not found at '", path, "'. ",
         "Are you running from the project root?", call. = FALSE)
  }
  cfg <- yaml::read_yaml(path)$default

  cfg$start_date <- as.Date(cfg$start_date)
  cfg$end_date   <- as.Date(cfg$end_date)
  for (nm in names(cfg$subperiods)) {
    cfg$subperiods[[nm]]$start <- as.Date(cfg$subperiods[[nm]]$start)
    cfg$subperiods[[nm]]$end   <- as.Date(cfg$subperiods[[nm]]$end)
  }

  if (cfg$end_date <= cfg$start_date) {
    stop("end_date must be after start_date.", call. = FALSE)
  }

  # Column names after sanitisation -- everything downstream refers to these.
  cfg$market_col <- sanitise(cfg$market)
  cfg$rf_col     <- sanitise(cfg$risk_free)

  for (d in c(cfg$cache_dir, cfg$processed_dir, cfg$figure_dir, cfg$table_dir)) {
    dir.create(d, recursive = TRUE, showWarnings = FALSE)
  }
  cfg
}

#' Ticker -> safe column name (^GSPC becomes GSPC).
sanitise <- function(x) gsub("[^A-Za-z0-9]", "", x)

log_msg <- function(..., level = "INFO") {
  cat(sprintf("[%s] %-5s %s\n", format(Sys.time(), "%H:%M:%S"), level,
              paste0(...)))
  invisible(NULL)
}

log_step <- function(...) {
  cat("\n", strrep("-", 74), "\n", sep = "")
  cat(paste0(...), "\n")
  cat(strrep("-", 74), "\n", sep = "")
  invisible(NULL)
}

#' Convert an annualised percentage yield to a monthly rate.
#'
#' CAVEAT ON CONVENTIONS. This applies compound de-annualisation,
#' (1 + y/100)^(1/12) - 1, which is appropriate for an investment/bond-
#' equivalent yield such as FRED's DGS1MO. It is NOT exact for a series quoted
#' on a bank-discount basis (Yahoo's ^IRX): a discount rate must first be
#' converted to a bond-equivalent yield. The error is a few basis points
#' annualised -- immaterial for beta, but the claim of exactness that an
#' earlier version of this file made was wrong, so it is stated plainly here.
#'
#' @param annual_pct Annualised yield, in percent.
annual_pct_to_monthly <- function(annual_pct) {
  (1 + annual_pct / 100)^(1 / 12) - 1
}

write_table <- function(df, path) {
  utils::write.csv(df, path, row.names = FALSE, na = "")
  log_msg("wrote ", path)
  invisible(path)
}

signif_stars <- function(p) {
  ifelse(is.na(p), "",
  ifelse(p < 0.01, "***",
  ifelse(p < 0.05, "**",
  ifelse(p < 0.10, "*", ""))))
}

#' Human-readable sample range, used in figure titles so they follow the config.
sample_label <- function(cfg) {
  paste(format(cfg$start_date, "%B %Y"), "-", format(cfg$end_date, "%B %Y"))
}

#' Figure caption built from the configured series, not hard-coded.
source_caption <- function(cfg) {
  paste0("Benchmark: ", cfg$market_label, ". Risk-free: ", cfg$risk_free_label,
         ".\nMonthly observations sampled at the last trading day of each month.")
}
