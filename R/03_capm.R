# ---------------------------------------------------------------------------
# 03_capm.R -- CAPM estimation.
#
# The regression is the standard time-series test of the Sharpe-Lintner CAPM:
#
#     r_it - rf_t = alpha_i + beta_i (r_mt - rf_t) + eps_it
#
# under which the null of interest is alpha_i = 0. Reporting the point
# estimates alone -- as `print(lm(...))` does -- says nothing about whether an
# alpha is distinguishable from zero, which is the entire question.
#
# Monthly equity residuals are heteroskedastic and mildly autocorrelated, so
# OLS standard errors overstate precision. Estimates below are reported with
# Newey-West HAC standard errors; classical SEs are kept alongside so the
# difference is visible rather than hidden.
#
# Bandwidth: sandwich::NeweyWest() defaults to the automatic selection of
# Newey & West (1994). (Andrews 1991 is a distinct procedure implemented in
# sandwich::kernHAC -- an earlier version of this project mis-attributed the
# default to it.)
# ---------------------------------------------------------------------------

#' Estimate a single CAPM regression with HAC inference.
#'
#' @param y Numeric vector of asset excess returns.
#' @param x Numeric vector of market excess returns.
#' @param hac_lags Newey-West truncation lag; NULL for automatic selection.
#' @return A one-row data frame of estimates and diagnostics.
estimate_capm <- function(y, x, hac_lags = NULL) {
  ok <- stats::complete.cases(y, x)
  y  <- y[ok]; x <- x[ok]
  n  <- length(y)

  if (n < 3) {
    stop("Need at least 3 observations to estimate a CAPM regression; got ",
         n, ".", call. = FALSE)
  }

  fit <- stats::lm(y ~ x)

  vcov_hac <- if (is.null(hac_lags)) {
    sandwich::NeweyWest(fit, prewhite = FALSE, adjust = TRUE)
  } else {
    sandwich::NeweyWest(fit, lag = hac_lags, prewhite = FALSE, adjust = TRUE)
  }
  hac <- lmtest::coeftest(fit, vcov. = vcov_hac)
  cls <- summary(fit)$coefficients

  data.frame(
    n_obs        = n,
    alpha        = unname(stats::coef(fit)[1]),
    alpha_se_ols = cls[1, 2],
    alpha_se_hac = hac[1, 2],
    alpha_t_hac  = hac[1, 3],
    alpha_p_hac  = hac[1, 4],
    alpha_ann    = (1 + unname(stats::coef(fit)[1]))^12 - 1,
    beta         = unname(stats::coef(fit)[2]),
    beta_se_ols  = cls[2, 2],
    beta_se_hac  = hac[2, 2],
    beta_t_hac   = hac[2, 3],
    beta_p_hac   = hac[2, 4],
    r_squared    = summary(fit)$r.squared,
    resid_sd     = stats::sd(stats::residuals(fit)),
    dw_stat      = tryCatch(unname(lmtest::dwtest(fit)$statistic),
                            error = function(e) NA_real_),
    bp_p_value   = tryCatch(unname(lmtest::bptest(fit)$p.value),
                            error = function(e) NA_real_),
    jb_p_value   = tryCatch(unname(tseries::jarque.bera.test(
                              stats::residuals(fit))$p.value),
                            error = function(e) NA_real_),
    stringsAsFactors = FALSE
  )
}

#' Run CAPM for every asset over a given date window.
#'
#' @param data List returned by `build_excess_returns()`.
#' @param cfg Project configuration.
#' @param start,end Optional Date bounds. NULL means the full sample.
#' @param period_label Label written into the output.
#' @return A data frame, one row per asset. Returns NULL (with a warning) if
#'   the window is too short to support inference.
run_capm_period <- function(data, cfg, start = NULL, end = NULL,
                            period_label = "Full sample") {
  ex  <- data$excess
  idx <- zoo::index(ex)

  keep <- rep(TRUE, length(idx))
  if (!is.null(start)) keep <- keep & idx >= start
  if (!is.null(end))   keep <- keep & idx <= end
  sub <- ex[keep, , drop = FALSE]

  if (nrow(sub) < cfg$min_obs_subperiod) {
    warning("Skipping '", period_label, "': only ", nrow(sub),
            " observations, below the minimum of ", cfg$min_obs_subperiod,
            ".", call. = FALSE)
    return(NULL)
  }

  mkt <- as.numeric(sub[, data$market_col])

  res <- do.call(rbind, lapply(data$asset_cols, function(a) {
    row <- estimate_capm(as.numeric(sub[, a]), mkt, hac_lags = cfg$hac_lags)
    cbind(
      data.frame(period = period_label,
                 ticker = a,
                 name   = cfg$assets[[a]],
                 start  = min(zoo::index(sub)),
                 end    = max(zoo::index(sub)),
                 stringsAsFactors = FALSE),
      row
    )
  }))

  res$alpha_sig <- signif_stars(res$alpha_p_hac)
  rownames(res) <- NULL

  log_msg(sprintf("CAPM | %-24s | %3d months | beta %.2f-%.2f",
                  period_label, nrow(sub),
                  min(res$beta), max(res$beta)))
  res
}

#' Run the full sample and every configured sub-period.
run_all_capm <- function(data, cfg) {
  results <- list(run_capm_period(data, cfg, period_label = "Full sample"))

  for (nm in names(cfg$subperiods)) {
    sp <- cfg$subperiods[[nm]]
    results[[length(results) + 1]] <- run_capm_period(
      data, cfg, start = sp$start, end = sp$end, period_label = sp$label
    )
  }

  out <- do.call(rbind, Filter(Negate(is.null), results))
  rownames(out) <- NULL
  out
}

#' Rolling-window betas.
#'
#' Sub-period regressions on 18 monthly observations are extremely noisy. A
#' rolling window shows how beta actually evolves and makes the crisis-period
#' point estimates interpretable in context rather than in isolation.
#'
#' @param data List returned by `build_excess_returns()`.
#' @param window Window length in months.
#' @return A long data frame: date, ticker, beta, alpha.
rolling_betas <- function(data, window = 36) {
  ex  <- data$excess
  idx <- zoo::index(ex)
  n   <- nrow(ex)

  if (n < window + 1) {
    warning("Sample shorter than the rolling window; skipping.", call. = FALSE)
    return(NULL)
  }

  mkt <- as.numeric(ex[, data$market_col])

  out <- do.call(rbind, lapply(data$asset_cols, function(a) {
    y <- as.numeric(ex[, a])

    est <- t(vapply(window:n, function(i) {
      w   <- (i - window + 1):i
      fit <- stats::lm(y[w] ~ mkt[w])
      se  <- tryCatch(
        sqrt(diag(sandwich::NeweyWest(fit, prewhite = FALSE, adjust = TRUE))),
        error = function(e) sqrt(diag(stats::vcov(fit)))
      )
      c(stats::coef(fit), se)
    }, numeric(4)))

    data.frame(
      date       = idx[window:n],
      ticker     = a,
      alpha      = est[, 1],
      beta       = est[, 2],
      alpha_se   = est[, 3],
      beta_se    = est[, 4],
      beta_lo    = est[, 2] - 1.96 * est[, 4],
      beta_hi    = est[, 2] + 1.96 * est[, 4],
      stringsAsFactors = FALSE
    )
  }))
  rownames(out) <- NULL
  log_msg("rolling betas: ", window, "-month window, ", nrow(out),
          " asset-months (with HAC bands)")
  out
}

#' Format the CAPM results into a publication-style table.
format_capm_table <- function(capm) {
  data.frame(
    Period          = capm$period,
    Asset           = capm$name,
    N               = capm$n_obs,
    `Alpha (mo, %)` = sprintf("%.3f", 100 * capm$alpha),
    `Alpha (ann,%)` = sprintf("%.2f", 100 * capm$alpha_ann),
    `t(alpha) HAC`  = sprintf("%.2f", capm$alpha_t_hac),
    Sig             = capm$alpha_sig,
    Beta            = sprintf("%.3f", capm$beta),
    `SE(beta) HAC`  = sprintf("%.3f", capm$beta_se_hac),
    `R2`            = sprintf("%.3f", capm$r_squared),
    check.names     = FALSE,
    stringsAsFactors = FALSE
  )
}
