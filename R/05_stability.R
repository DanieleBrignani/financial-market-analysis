# ---------------------------------------------------------------------------
# 05_stability.R -- formal tests of beta stability across regimes.
#
# WHY THIS FILE EXISTS. An earlier version of this project claimed "beta is not
# a constant" on the strength of a rolling-window chart. That is an impression,
# not a finding: rolling OLS estimates wander under pure sampling noise, and a
# 36-month window on monthly data is short enough for that wander to be large.
# Claiming instability requires testing it.
#
# The test is an interacted regression rather than a textbook Chow test:
#
#     r_i - rf = a + b (r_m - rf) + c D + d (r_m - rf) D + e
#
# where D is the crisis indicator. Then d is the CHANGE in beta inside the
# window, and the joint null c = d = 0 is the Chow null of no structural break.
# The interacted form is preferred here because it accepts a HAC covariance
# matrix directly, whereas the classical Chow F-statistic assumes homoskedastic
# and serially uncorrelated errors -- assumptions monthly equity returns
# violate, and which the rest of this project already declines to make.
# ---------------------------------------------------------------------------

#' HAC covariance function used throughout the stability tests.
hac_vcov <- function(model) {
  tryCatch(
    sandwich::NeweyWest(model, prewhite = FALSE, adjust = TRUE),
    error = function(e) stats::vcov(model)
  )
}

#' Test whether beta differs inside each configured sub-period.
#'
#' @return A data frame: one row per asset per sub-period, with the estimated
#'   beta shift, its HAC standard error, and the joint Chow-type Wald test.
test_beta_stability <- function(data, cfg) {
  ex  <- data$excess
  idx <- zoo::index(ex)
  mkt <- as.numeric(ex[, data$market_col])

  rows <- list()

  for (nm in names(cfg$subperiods)) {
    sp <- cfg$subperiods[[nm]]
    D  <- as.numeric(idx >= sp$start & idx <= sp$end)

    if (sum(D) < cfg$min_obs_subperiod) {
      warning("Skipping stability test for '", sp$label, "': only ", sum(D),
              " observations in the window.", call. = FALSE)
      next
    }

    for (a in data$asset_cols) {
      y <- as.numeric(ex[, a])

      unrestricted <- stats::lm(y ~ mkt * D)
      restricted   <- stats::lm(y ~ mkt)

      ct <- lmtest::coeftest(unrestricted, vcov. = hac_vcov(unrestricted))

      wald <- tryCatch(
        lmtest::waldtest(restricted, unrestricted, vcov = hac_vcov,
                         test = "Chisq"),
        error = function(e) NULL
      )

      rows[[length(rows) + 1]] <- data.frame(
        period          = sp$label,
        ticker          = a,
        name            = cfg$assets[[a]],
        n_crisis        = sum(D),
        n_total         = length(y),
        beta_base       = unname(stats::coef(unrestricted)["mkt"]),
        beta_shift      = unname(stats::coef(unrestricted)["mkt:D"]),
        shift_se_hac    = ct["mkt:D", 2],
        shift_t_hac     = ct["mkt:D", 3],
        shift_p_hac     = ct["mkt:D", 4],
        chow_chisq      = if (is.null(wald)) NA_real_ else wald[2, "Chisq"],
        chow_p          = if (is.null(wald)) NA_real_ else wald[2, "Pr(>Chisq)"],
        stringsAsFactors = FALSE
      )
    }
  }

  if (length(rows) == 0) return(NULL)

  out <- do.call(rbind, rows)
  out$shift_sig <- signif_stars(out$shift_p_hac)
  out$chow_sig  <- signif_stars(out$chow_p)
  rownames(out) <- NULL

  # TWO DISTINCT NULLS -- conflating them is a real inferential error:
  #   shift_p_hac : d = 0. Specific to BETA. This is the beta-stability test.
  #   chow_p      : c = d = 0 jointly. A break in the CAPM relation as a whole;
  #                 it can reject because the INTERCEPT moved while beta did not.
  # Any statement about beta constancy must cite shift_p_hac, not chow_p.
  n_beta <- sum(out$shift_p_hac < 0.05, na.rm = TRUE)
  n_any  <- sum(out$chow_p     < 0.05, na.rm = TRUE)
  log_msg("beta stability: ", n_beta, " of ", nrow(out),
          " asset-periods reject BETA constancy at 5% (shift test)")
  log_msg("CAPM stability: ", n_any, " of ", nrow(out),
          " reject the joint null of no break in alpha OR beta (Chow-type)")
  out
}

#' Count of asset-periods rejecting BETA constancy at a given level.
#' Exists so callers cannot accidentally reach for the joint Chow p-value.
count_beta_breaks <- function(stability, level = 0.05) {
  if (is.null(stability)) return(0L)
  sum(stability$shift_p_hac < level, na.rm = TRUE)
}

#' Format the stability results for reporting.
format_stability_table <- function(st) {
  data.frame(
    Period            = st$period,
    Asset             = st$name,
    `N (crisis)`      = st$n_crisis,
    `Beta outside`    = sprintf("%.3f", st$beta_base),
    `Shift in crisis` = sprintf("%+.3f", st$beta_shift),
    `SE (HAC)`        = sprintf("%.3f", st$shift_se_hac),
    `t`               = sprintf("%.2f", st$shift_t_hac),
    `p (beta shift)`  = sprintf("%.3f", st$shift_p_hac),
    `Sig (beta)`      = st$shift_sig,
    `p (joint Chow)`  = sprintf("%.3f", st$chow_p),
    `Sig (joint)`     = st$chow_sig,
    check.names       = FALSE,
    stringsAsFactors  = FALSE
  )
}
