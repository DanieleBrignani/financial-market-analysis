# ---------------------------------------------------------------------------
# 02_returns.R -- monthly simple returns, excess returns, descriptives.
# ---------------------------------------------------------------------------

#' Monthly simple returns from a month-end price panel.
#'
#' A return computed from P[t-1] to P[t] describes month t and carries date t.
compute_returns <- function(monthly_prices, price_cols) {
  missing_cols <- setdiff(price_cols, colnames(monthly_prices))
  if (length(missing_cols) > 0) {
    stop("Column(s) not found in the price panel: ",
         paste(missing_cols, collapse = ", "), call. = FALSE)
  }
  px  <- monthly_prices[, price_cols, drop = FALSE]
  ret <- px / xts::lag.xts(px, k = 1) - 1
  ret[-1, , drop = FALSE]
}

#' Build the excess-return panel.
#'
#' The rate that is risk-free for month t is the yield quoted at the end of
#' month t-1: it is known when the position is opened. Using the end-of-month-t
#' yield is look-ahead bias.
build_excess_returns <- function(monthly_prices, cfg) {
  asset_cols <- names(cfg$assets)
  mkt_col    <- cfg$market_col
  rf_col     <- cfg$rf_col

  returns <- compute_returns(monthly_prices, c(asset_cols, mkt_col))

  rf_annual  <- xts::lag.xts(monthly_prices[, rf_col, drop = FALSE], k = 1)
  rf_monthly <- annual_pct_to_monthly(rf_annual)
  colnames(rf_monthly) <- "rf"

  merged <- xts::merge.xts(returns, rf_monthly, join = "inner")
  merged <- merged[stats::complete.cases(merged), ]

  if (nrow(merged) < 24) {
    stop("Only ", nrow(merged), " usable monthly observations.", call. = FALSE)
  }

  rf     <- merged[, "rf", drop = FALSE]
  rets   <- merged[, setdiff(colnames(merged), "rf"), drop = FALSE]
  excess <- rets - matrix(rep(zoo::coredata(rf), ncol(rets)),
                          nrow = nrow(rets), ncol = ncol(rets))
  colnames(excess) <- colnames(rets)

  log_msg("excess returns: ", nrow(excess), " months, ", ncol(excess),
          " series")

  list(returns = rets, rf = rf, excess = excess,
       asset_cols = asset_cols, market_col = mkt_col)
}

#' Descriptive statistics for a monthly return panel.
#'
#' THREE CONVENTIONS, REPORTED SEPARATELY, because conflating them is a common
#' and consequential error:
#'
#'   ann_return_arith  (1 + arithmetic mean)^12 - 1. Consistent with the CAPM,
#'                     which is a statement about expected (arithmetic) returns.
#'                     NOT the realised compound growth rate.
#'   cagr              prod(1 + r)^(12/n) - 1. The geometric mean: what an
#'                     investor actually earned. Always <= the arithmetic
#'                     figure, and the gap widens with volatility.
#'   sharpe            sqrt(12) * mean(r) / sd(r), the standard annualisation.
#'                     Dividing a GEOMETRIC annualised return by an annualised
#'                     standard deviation mixes conventions and understates the
#'                     ratio; an earlier version of this file did exactly that.
#'
#' The Sharpe ratio is only interpretable when `panel` holds EXCESS returns.
describe_returns <- function(panel, labels = NULL) {
  cols <- colnames(panel)

  out <- do.call(rbind, lapply(cols, function(cn) {
    x <- stats::na.omit(as.numeric(panel[, cn]))
    n <- length(x)
    data.frame(
      series           = cn,
      name             = if (!is.null(labels) && cn %in% names(labels))
                           labels[[cn]] else cn,
      n_months         = n,
      mean_monthly     = mean(x),
      sd_monthly       = stats::sd(x),
      min_monthly      = min(x),
      max_monthly      = max(x),
      skewness         = mean((x - mean(x))^3) / stats::sd(x)^3,
      excess_kurt      = mean((x - mean(x))^4) / stats::sd(x)^4 - 3,
      ann_return_arith = (1 + mean(x))^12 - 1,
      cagr             = prod(1 + x)^(12 / n) - 1,
      ann_vol          = stats::sd(x) * sqrt(12),
      sharpe           = sqrt(12) * mean(x) / stats::sd(x),
      max_drawdown     = max_drawdown(x),
      stringsAsFactors = FALSE
    )
  }))
  rownames(out) <- NULL
  out
}

#' Maximum drawdown of a simple-return series, as a positive fraction.
max_drawdown <- function(r) {
  wealth <- cumprod(1 + r)
  peak   <- cummax(wealth)
  max(1 - wealth / peak)
}
