test_that("estimate_capm recovers a known alpha and beta", {
  set.seed(123)
  n     <- 600
  mkt   <- rnorm(n, 0.006, 0.045)
  alpha <- 0.002
  beta  <- 1.35
  y     <- alpha + beta * mkt + rnorm(n, 0, 0.02)

  res <- estimate_capm(y, mkt)

  # testthat's `tolerance` is RELATIVE, which is meaningless for a quantity
  # this close to zero -- compare alpha in absolute terms.
  expect_lt(abs(res$alpha - alpha), 0.002)
  expect_lt(abs(res$beta  - beta),  0.05)
  expect_equal(res$n_obs, n)
  expect_gt(res$r_squared, 0.8)
})

test_that("a zero-alpha process is not flagged as significant", {
  set.seed(7)
  mkt <- rnorm(400, 0.005, 0.04)
  y   <- 1.0 * mkt + rnorm(400, 0, 0.03)

  res <- estimate_capm(y, mkt)
  expect_gt(res$alpha_p_hac, 0.10)
})

test_that("HAC standard errors differ from OLS under autocorrelation", {
  set.seed(11)
  n   <- 300
  mkt <- rnorm(n, 0, 0.04)
  e   <- as.numeric(stats::arima.sim(list(ar = 0.6), n = n, sd = 0.02))
  y   <- 0.001 + 1.1 * mkt + e

  res <- estimate_capm(y, mkt)
  # The whole point of reporting HAC: it should not coincide with OLS here.
  expect_false(isTRUE(all.equal(res$alpha_se_hac, res$alpha_se_ols,
                                tolerance = 1e-4)))
})

test_that("estimate_capm drops incomplete pairs and refuses tiny samples", {
  mkt <- c(0.01, NA, 0.02, -0.01, 0.03)
  y   <- c(0.02, 0.01, NA, -0.02, 0.04)
  expect_equal(estimate_capm(y, mkt)$n_obs, 3L)

  expect_error(estimate_capm(c(0.01, 0.02), c(0.01, 0.02)),
               "at least 3 observations")
})

test_that("signif_stars maps p-values to conventional thresholds", {
  expect_equal(signif_stars(c(0.001, 0.03, 0.08, 0.5, NA)),
               c("***", "**", "*", "", ""))
})

test_that("rolling_betas returns one row per asset per window position", {
  set.seed(5)
  n     <- 80
  dates <- seq(as.Date("2010-01-31"), by = "month", length.out = n)
  mkt   <- rnorm(n, 0.005, 0.04)
  m     <- cbind(AAA = 1.2 * mkt + rnorm(n, 0, 0.02),
                 BBB = 0.7 * mkt + rnorm(n, 0, 0.02),
                 GSPC = mkt)
  data <- list(excess = xts::xts(m, order.by = dates),
               asset_cols = c("AAA", "BBB"),
               market_col = "GSPC")

  roll <- rolling_betas(data, window = 36)

  expect_equal(nrow(roll), 2 * (n - 36 + 1))
  expect_setequal(unique(roll$ticker), c("AAA", "BBB"))
  expect_lt(abs(mean(roll$beta[roll$ticker == "AAA"]) - 1.2), 0.15)
})

test_that("test_beta_stability detects a beta break that is really there", {
  set.seed(21)
  n     <- 240
  dates <- seq(as.Date("2004-10-31"), by = "month", length.out = n)
  mkt   <- rnorm(n, 0.005, 0.042)

  # Impose a large, genuine beta shift inside the configured window.
  crisis <- dates >= as.Date("2007-12-01") & dates <= as.Date("2009-06-30")
  beta   <- ifelse(crisis, 2.2, 1.0)
  y      <- beta * mkt + rnorm(n, 0, 0.015)

  m <- cbind(AAA = y, MKT = mkt)
  data <- list(excess = xts::xts(m, order.by = dates),
               asset_cols = "AAA", market_col = "MKT")
  cfg <- list(
    assets = list(AAA = "Test Asset"),
    min_obs_subperiod = 12,
    subperiods = list(gfc = list(label = "GFC",
                                 start = as.Date("2007-12-01"),
                                 end   = as.Date("2009-06-30")))
  )

  st <- test_beta_stability(data, cfg)

  expect_equal(nrow(st), 1L)
  expect_gt(st$beta_shift, 0.8)          # recovers roughly +1.2
  expect_lt(st$chow_p, 0.05)             # and calls it significant
})

test_that("test_beta_stability does NOT flag a stable beta", {
  set.seed(22)
  n     <- 240
  dates <- seq(as.Date("2004-10-31"), by = "month", length.out = n)
  mkt   <- rnorm(n, 0.005, 0.042)
  y     <- 1.1 * mkt + rnorm(n, 0, 0.02)   # constant beta throughout

  m <- cbind(AAA = y, MKT = mkt)
  data <- list(excess = xts::xts(m, order.by = dates),
               asset_cols = "AAA", market_col = "MKT")
  cfg <- list(
    assets = list(AAA = "Test Asset"),
    min_obs_subperiod = 12,
    subperiods = list(gfc = list(label = "GFC",
                                 start = as.Date("2007-12-01"),
                                 end   = as.Date("2009-06-30")))
  )

  st <- test_beta_stability(data, cfg)
  expect_gt(st$chow_p, 0.10)
})
