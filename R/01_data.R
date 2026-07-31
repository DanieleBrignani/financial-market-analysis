# ---------------------------------------------------------------------------
# 01_data.R -- acquisition and caching of daily price / yield series.
#
# Supports two sources, because the correct benchmark and the correct
# risk-free proxy do not live in the same place:
#   * yahoo -- equities and ETFs; adjusted close reinvests distributions.
#   * FRED  -- Treasury constant-maturity yields; single-column series with
#              NA on non-business days.
# ---------------------------------------------------------------------------

#' Download one series, with on-disk caching.
#'
#' @param symbol Ticker or FRED series id.
#' @param src "yahoo" or "FRED".
#' @return A single-column xts named after the sanitised symbol.
fetch_symbol <- function(symbol, from, to, cache_dir, src = "yahoo",
                         refresh = FALSE) {
  col        <- sanitise(symbol)
  cache_file <- file.path(cache_dir, sprintf(
    "%s_%s_%s_%s.rds", src, col, format(from, "%Y%m%d"), format(to, "%Y%m%d")))

  if (file.exists(cache_file) && !refresh) {
    log_msg("cache hit  ", symbol, " (", src, ")")
    return(readRDS(cache_file))
  }

  log_msg("downloading ", symbol, " from ", src, " ...")
  raw <- tryCatch(
    quantmod::getSymbols(symbol, src = src, from = from, to = to,
                         auto.assign = FALSE, warnings = FALSE),
    error = function(e) {
      stop("Failed to download '", symbol, "' from ", src, ": ",
           conditionMessage(e),
           "\nCheck connectivity, or set `offline: true` in config/config.yml.",
           call. = FALSE)
    }
  )

  if (is.null(raw) || nrow(raw) == 0) {
    stop(src, " returned no rows for '", symbol, "'.", call. = FALSE)
  }

  series <- if (identical(src, "FRED")) {
    # FRED returns one column and ignores from/to, so subset explicitly.
    raw[, 1, drop = FALSE]
  } else {
    quantmod::Ad(raw)
  }
  colnames(series) <- col
  series <- series[paste0(format(from), "/", format(to))]

  # FRED marks holidays as NA; carry the last quoted yield forward.
  series <- zoo::na.locf(series, na.rm = FALSE)
  series <- series[!is.na(series[, 1]), , drop = FALSE]

  if (nrow(series) == 0) {
    stop("No usable observations for '", symbol, "' in the requested window.",
         call. = FALSE)
  }

  saveRDS(series, cache_file)
  log_msg("cached ", symbol, " (", nrow(series), " observations)")
  series
}

#' Download every configured series and merge on the date index.
fetch_universe <- function(cfg, refresh = FALSE) {
  specs <- c(
    lapply(names(cfg$assets), function(a) list(sym = a, src = "yahoo")),
    list(list(sym = cfg$market,    src = cfg$market_source)),
    list(list(sym = cfg$risk_free, src = cfg$risk_free_source))
  )

  series_list <- lapply(specs, function(s) {
    fetch_symbol(s$sym, cfg$start_date, cfg$end_date, cfg$cache_dir,
                 src = s$src, refresh = refresh)
  })

  panel <- Reduce(function(a, b) xts::merge.xts(a, b, join = "outer"),
                  series_list)
  panel <- zoo::na.locf(panel, na.rm = FALSE)
  panel <- panel[stats::complete.cases(panel), ]

  if (nrow(panel) == 0) {
    stop("Merged panel is empty after removing incomplete rows.", call. = FALSE)
  }

  log_msg("merged panel: ", nrow(panel), " daily rows x ", ncol(panel),
          " series")
  panel
}

#' Last trading day of each calendar month.
to_month_end <- function(daily_panel) {
  ep <- xts::endpoints(daily_panel, on = "months")
  ep <- ep[ep > 0]
  monthly <- daily_panel[ep, ]
  log_msg("month-end sample: ", nrow(monthly), " observations (",
          format(zoo::index(monthly)[1], "%Y-%m"), " to ",
          format(zoo::index(monthly)[nrow(monthly)], "%Y-%m"), ")")
  monthly
}

save_snapshot <- function(monthly, cfg) {
  path <- file.path(cfg$processed_dir, "monthly_prices.csv")
  df   <- cbind(data.frame(date = zoo::index(monthly)),
                as.data.frame(zoo::coredata(monthly)))
  write_table(df, path)
  path
}

load_snapshot <- function(cfg) {
  path <- file.path(cfg$processed_dir, "monthly_prices.csv")
  if (!file.exists(path)) {
    stop("Offline mode is on but no snapshot exists at '", path, "'.\n",
         "Run once with `offline: false` to create it.", call. = FALSE)
  }
  df <- utils::read.csv(path, stringsAsFactors = FALSE)
  log_msg("loaded snapshot: ", nrow(df), " monthly observations")
  xts::xts(as.matrix(df[, -1, drop = FALSE]), order.by = as.Date(df$date))
}

get_monthly_panel <- function(cfg, refresh = FALSE) {
  if (isTRUE(cfg$offline)) return(load_snapshot(cfg))
  monthly <- to_month_end(fetch_universe(cfg, refresh = refresh))
  save_snapshot(monthly, cfg)
  monthly
}
