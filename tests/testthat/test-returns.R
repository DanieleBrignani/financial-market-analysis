test_that("annual percentage yields compound to the right monthly rate", {
  # A 12.68% annual yield compounds to almost exactly 1% per month.
  expect_equal(annual_pct_to_monthly(12.682503), 0.01, tolerance = 1e-6)
  expect_equal(annual_pct_to_monthly(0), 0)
  # Compounding must sit below the naive linear approximation for positive rates.
  expect_lt(annual_pct_to_monthly(6), 6 / 1200)
})

test_that("returns are dated at the END of the holding period", {
  dates <- as.Date(c("2020-01-31", "2020-02-29", "2020-03-31"))
  px    <- xts::xts(matrix(c(100, 110, 121), ncol = 1,
                           dimnames = list(NULL, "AAA")), order.by = dates)

  r <- compute_returns(px, "AAA")

  expect_equal(nrow(r), 2L)
  # The 10% gain earned during February must carry February's date, not January's.
  expect_equal(zoo::index(r)[1], as.Date("2020-02-29"))
  expect_equal(as.numeric(r[1]), 0.10, tolerance = 1e-12)
  expect_equal(as.numeric(r[2]), 0.10, tolerance = 1e-12)
})

test_that("compute_returns rejects unknown columns", {
  px <- xts::xts(matrix(1:3, ncol = 1, dimnames = list(NULL, "AAA")),
                 order.by = as.Date(c("2020-01-31", "2020-02-29", "2020-03-31")))
  expect_error(compute_returns(px, "ZZZ"), "not found")
})

test_that("maximum drawdown is correct and non-negative", {
  # +100% then -50% returns to the starting level: peak-to-trough is 50%.
  expect_equal(max_drawdown(c(1, -0.5)), 0.5, tolerance = 1e-12)
  expect_equal(max_drawdown(c(0.01, 0.01, 0.01)), 0, tolerance = 1e-12)
  expect_gte(max_drawdown(rnorm(100, 0, 0.05)), 0)
})

test_that("descriptive statistics annualise consistently", {
  set.seed(1)
  panel <- xts::xts(matrix(rnorm(120, 0.01, 0.04), ncol = 1,
                           dimnames = list(NULL, "AAA")),
                    order.by = seq(as.Date("2010-01-31"), by = "month",
                                   length.out = 120))
  d <- describe_returns(panel)

  expect_equal(nrow(d), 1L)
  expect_equal(d$n_months, 120L)
  expect_equal(d$ann_vol, d$sd_monthly * sqrt(12), tolerance = 1e-12)
  # Sharpe is asserted in its own test below, against the sqrt(12) convention.
  expect_true("ann_return_arith" %in% names(d))
  expect_true("cagr" %in% names(d))
})

test_that("arithmetic annualisation and CAGR are distinct and correctly ordered", {
  # +50% then -30%: the compound outcome (+5% over two months) is far below
  # what compounding the arithmetic mean (+10%) would imply.
  x <- c(0.50, -0.30)
  panel <- xts::xts(matrix(x, ncol = 1, dimnames = list(NULL, "AAA")),
                    order.by = as.Date(c("2020-01-31", "2020-02-29")))
  d <- describe_returns(panel)

  expect_equal(d$ann_return_arith, (1 + mean(x))^12 - 1, tolerance = 1e-12)
  expect_equal(d$cagr, prod(1 + x)^(12 / 2) - 1, tolerance = 1e-12)
  # Jensen: the geometric mean never exceeds the arithmetic mean.
  expect_lt(d$cagr, d$ann_return_arith)
})

test_that("Sharpe uses the standard sqrt(12) annualisation", {
  set.seed(3)
  x <- rnorm(240, 0.008, 0.045)
  panel <- xts::xts(matrix(x, ncol = 1, dimnames = list(NULL, "AAA")),
                    order.by = seq(as.Date("2004-10-31"), by = "month",
                                   length.out = 240))
  d <- describe_returns(panel)

  expect_equal(d$sharpe, sqrt(12) * mean(x) / stats::sd(x), tolerance = 1e-12)
  # It must NOT equal the mixed-convention version this project used to report.
  mixed <- (prod(1 + x)^(12 / 240) - 1) / (stats::sd(x) * sqrt(12))
  expect_false(isTRUE(all.equal(d$sharpe, mixed, tolerance = 1e-6)))
})
