#!/usr/bin/env Rscript
# Run with:  Rscript tests/testthat.R   (from the project root)

suppressPackageStartupMessages({
  library(testthat)
  library(xts)
  library(zoo)
  library(sandwich)
  library(lmtest)
  library(tseries)
})

if (!dir.exists("R")) {
  stop("Run from the project root: Rscript tests/testthat.R", call. = FALSE)
}

for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)

res <- testthat::test_dir("tests/testthat", reporter = "summary", stop_on_failure = TRUE)
