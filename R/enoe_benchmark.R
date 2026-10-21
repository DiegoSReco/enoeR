# ============================================================
#  enoe_benchmark.R
#  Compare ENOE microdata estimates with INEGI published figures
# ============================================================

#' @keywords internal
.rate_indicators <- c("tasa_desocupacion", "tasa_participacion")

#' @keywords internal
.enoe_parse_period <- function(nms) {
  parsed <- regmatches(nms, regexec("(^|_)(\\d{4})_t([1-4])$", nms))
  if (any(lengths(parsed) == 0L))
    stop("Elements must be named 'enoe_{year}_t{quarter}'.", call. = FALSE)
  data.table::data.table(
    period  = nms,
    year    = vapply(parsed, function(p) as.integer(p[3L]), integer(1L)),
    quarter = vapply(parsed, function(p) as.integer(p[4L]), integer(1L))
  )
}


#' Official labour-force indicators from the SDEM table
#'
#' @description
#' Computes, for every quarter, the strategic indicators with INEGI's rules
#' ("Conociendo la base de datos", sections 6 and 8): general criterion
#' `r_def = 00`, `c_res` in (1, 3), `eda` 15-98, and the precoded fields
#' `clase1` (1 = PEA, 2 = NEA) and `clase2` (1 = employed, 2 = unemployed).
#' Estimates are weighted totals with `fac_tri` (2020 Q3 onwards) or `fac`.
#'
#' Indicators: `pob_total` (`r_def = 00` and `c_res` 1 or 3), `pob_15mas`,
#' `pea`, `nea`, `ocupados`, `desocupados`, `tasa_desocupacion` (percent of
#' PEA) and `tasa_participacion` (percent of the population 15+).
#'
#' @param enoe_list_output Output of [enoe_list()] including the `sdem` table.
#'
#' @return Long `data.table` with `period`, `year`, `quarter`, `weight`
#'   (weight column used), `indicator`, `value` and `n` (unweighted sample size
#'   behind the estimate; for rates, the size of the denominator). Standard
#'   errors are not computed: they need the survey design (`upm`, `est_d`).
#'
#' @examples
#' \dontrun{
#' x <- enoe_list(2019, 2019, tables = "sdem")
#' enoe_indicators(x)
#' }
#'
#' @seealso [enoe_benchmark()]
#' @importFrom data.table data.table rbindlist
#' @export
enoe_indicators <- function(enoe_list_output) {
  quarters <- Filter(.is_quarter, enoe_list_output)
  if (length(quarters) == 0L)
    stop("'enoe_list_output' must be the output of enoe_list().")
  per <- .enoe_parse_period(names(quarters))

  rows <- lapply(seq_along(quarters), function(i) {
    sdem <- quarters[[i]][["sdem"]]
    if (is.null(sdem)) {
      warning(sprintf("No 'sdem' table in %s; skipped.", per$period[i]),
              call. = FALSE)
      return(NULL)
    }
    dt   <- .enoe_lower(sdem)
    need <- c("r_def", "c_res", "eda", "clase1", "clase2")
    if (!all(need %in% names(dt)))
      stop(sprintf("%s: missing column(s) %s.", per$period[i],
                   paste(setdiff(need, names(dt)), collapse = ", ")),
           call. = FALSE)
    wcol <- intersect(c("fac_tri", "fac"), names(dt))[1L]
    if (is.na(wcol))
      stop(sprintf("%s: no weight column (fac_tri or fac).", per$period[i]),
           call. = FALSE)

    w    <- as.numeric(dt[[wcol]])
    ok   <- as.integer(dt$r_def) == 0L & as.integer(dt$c_res) %in% c(1L, 3L)
    a15  <- ok & as.integer(dt$eda) %in% 15L:98L
    c1   <- as.integer(dt$clase1); c2 <- as.integer(dt$clase2)
    tot  <- function(m) sum(w[m %in% TRUE])
    cnt  <- function(m) sum(m %in% TRUE)

    pea <- tot(a15 & c1 == 1L); des <- tot(a15 & c2 == 2L)
    p15 <- tot(a15)
    data.table::data.table(
      period = per$period[i], year = per$year[i], quarter = per$quarter[i],
      weight = wcol,
      indicator = c("pob_total", "pob_15mas", "pea", "nea", "ocupados",
                    "desocupados", "tasa_desocupacion", "tasa_participacion"),
      value = c(tot(ok), p15, pea, tot(a15 & c1 == 2L), tot(a15 & c2 == 1L),
                des, 100 * des / pea, 100 * pea / p15),
      n = c(cnt(ok), cnt(a15), cnt(a15 & c1 == 1L), cnt(a15 & c1 == 2L),
            cnt(a15 & c2 == 1L), cnt(a15 & c2 == 2L), cnt(a15 & c1 == 1L),
            cnt(a15))
    )
  })
  data.table::rbindlist(rows)
}


#' Compare estimates with reference figures
#'
#' @description
#' Merges [enoe_indicators()] with a table of published figures (INEGI
#' tabulados or a paper) and flags the differences. Counts are compared in
#' relative terms; rates (`tasa_*`) in percentage points.
#'
#' @param estimates Output of [enoe_indicators()].
#' @param reference `data.frame` with `year`, `quarter`, `indicator`, `value`
#'   and optionally `source`. Use the same indicator names and units as
#'   [enoe_indicators()] (persons, percent). See [enoe_reference()].
#' @param tol_rel Relative tolerance for counts. Default `0.005` (0.5%).
#' @param tol_pp Tolerance for rates in percentage points. Default `0.1`.
#'   Both defaults are conventions, not INEGI figures: set them to what the
#'   comparison needs.
#'
#' @return A `data.table` with `year`, `quarter`, `indicator`, `enoeR`,
#'   `reference`, `diff`, `rel_diff`, `tolerance` and `within_tolerance`.
#'   Rows present on one side only have `within_tolerance = NA` and trigger a
#'   warning.
#'
#' @examples
#' \dontrun{
#' est <- enoe_indicators(x)
#' ref <- enoe_reference(c(pea = "<series id>", ocupados = "<series id>"))
#' enoe_benchmark(est, ref)
#' }
#'
#' @seealso [enoe_indicators()], [enoe_reference()]
#' @importFrom data.table as.data.table fifelse
#' @export
enoe_benchmark <- function(estimates, reference, tol_rel = 0.005, tol_pp = 0.1) {
  reference <- data.table::as.data.table(reference)
  need <- c("year", "quarter", "indicator", "value")
  if (!all(need %in% names(reference)))
    stop("'reference' needs columns: ", paste(need, collapse = ", "))
  if (!"source" %in% names(reference)) reference$source <- NA_character_

  keys <- c("year", "quarter", "indicator")
  e <- estimates[, c(keys, "value", "n"), with = FALSE]
  data.table::setnames(e, c("value", "n"), c("enoeR", "n"))
  r <- reference[, c(keys, "value", "source"), with = FALSE]
  data.table::setnames(r, "value", "reference")
  if (anyDuplicated(r, by = keys))
    stop("'reference' has duplicated (year, quarter, indicator) rows.")

  m <- merge(e, r, by = keys, all = TRUE)
  is_rate <- m$indicator %in% .rate_indicators
  m$diff      <- m$enoeR - m$reference
  m$rel_diff  <- m$diff / m$reference
  m$tolerance <- data.table::fifelse(is_rate, tol_pp, tol_rel)
  m$within_tolerance <- data.table::fifelse(
    is_rate, abs(m$diff) <= tol_pp, abs(m$rel_diff) <= tol_rel
  )
  n_one_side <- sum(is.na(m$enoeR) | is.na(m$reference))
  if (n_one_side > 0L)
    warning(sprintf("%d row(s) have an estimate or a reference but not both.",
                    n_one_side), call. = FALSE)
  data.table::setorderv(m, keys)
  m[]
}


# ── INEGI indicators API ─────────────────────────────────────────────────────

#' @keywords internal
.inegi_fetch <- function(url) {
  res <- curl::curl_fetch_memory(url)
  if (res$status_code != 200L)
    stop(sprintf("HTTP %d", res$status_code), call. = FALSE)
  rawToChar(res$content)
}

#' @keywords internal
.parse_inegi <- function(txt, id) {
  j <- jsonlite::fromJSON(txt, simplifyVector = FALSE)
  s <- j[["Series"]]
  if (is.null(s) || length(s) == 0L)
    stop(sprintf("No series returned for indicator %s.", id), call. = FALSE)
  s   <- s[[1L]]
  obs <- s[["OBSERVATIONS"]]
  get <- function(o, k) { v <- o[[k]]; if (is.null(v)) NA_character_ else as.character(v) }
  tp  <- vapply(obs, get, character(1L), k = "TIME_PERIOD")
  val <- suppressWarnings(as.numeric(vapply(obs, get, character(1L), k = "OBS_VALUE")))
  fq  <- if (is.null(s[["FREQ"]])) NA_character_ else as.character(s[["FREQ"]])
  um  <- if (is.null(s[["UNIT_MULT"]])) NA_character_ else as.character(s[["UNIT_MULT"]])
  un  <- if (is.null(s[["UNIT"]])) NA_character_ else as.character(s[["UNIT"]])
  data.table::data.table(
    id = as.character(id), freq = fq, unit = un, unit_mult = um,
    time_period = tp, value = val
  )
}

#' Download series from INEGI's indicators API
#'
#' @description
#' Requests `INDICATOR/{id}/es/{area}/false/{source}/2.0/{token}?type=json`
#' from `https://www.inegi.org.mx/app/api/indicadores/desarrolladores/jsonxml/`
#' (INEGI, "API de Indicadores"). The token is read from the `INEGI_TOKEN`
#' environment variable by default and is never printed: it is removed from
#' error messages.
#'
#' @param ids Character vector of indicator ids. Confirm them in INEGI's BIE;
#'   the package does not assume any.
#' @param token INEGI personal token. Default `Sys.getenv("INEGI_TOKEN")`.
#' @param source `"BIE"` (default) or `"BISE"`. INEGI's page documents `BISE`
#'   in its examples; check which one holds your series.
#' @param area Geographic area code, `"00"` for national.
#' @param fetch Function taking a URL and returning the response text. For
#'   tests; defaults to a `curl` request.
#'
#' @return A `data.table` with `id`, `freq`, `unit`, `unit_mult`,
#'   `time_period` (as returned) and `value`.
#'
#' @seealso [enoe_reference()]
#' @importFrom curl curl_fetch_memory
#' @export
inegi_series <- function(ids, token = Sys.getenv("INEGI_TOKEN"),
                         source = c("BIE", "BISE"), area = "00",
                         fetch = .inegi_fetch) {
  source <- match.arg(source)
  if (!is.character(token) || length(token) != 1L || !nzchar(token))
    stop("Set the INEGI_TOKEN environment variable with your INEGI token.")
  base <- paste0("https://www.inegi.org.mx/app/api/indicadores/",
                 "desarrolladores/jsonxml/INDICATOR")
  out <- lapply(as.character(ids), function(id) {
    url <- sprintf("%s/%s/es/%s/false/%s/2.0/%s?type=json",
                   base, id, area, source, token)
    txt <- tryCatch(fetch(url), error = function(e)
      stop(sprintf("INEGI API request failed for indicator %s: %s", id,
                   gsub(token, "<token>", conditionMessage(e), fixed = TRUE)),
           call. = FALSE))
    .parse_inegi(txt, id)
  })
  data.table::rbindlist(out)
}

#' Reference table of quarterly figures from INEGI's API
#'
#' @description
#' Downloads the given series with [inegi_series()] and returns them in the
#' format [enoe_benchmark()] expects. Only observations whose `TIME_PERIOD`
#' looks like `YYYY/0Q` (Q = 1-4) in a quarterly series (`FREQ` containing
#' "trim") are kept; check `time_period` and `freq` on the first real call.
#'
#' @param series Named character vector: names are [enoe_indicators()] names
#'   (for example `pea`), values are INEGI indicator ids.
#' @param scale Numeric, scalar or named like `series`, multiplied into the
#'   values (for example `1000` if INEGI reports thousands of persons).
#'   Check `unit` and `unit_mult` in [inegi_series()] before choosing.
#' @inheritParams inegi_series
#'
#' @return `data.table` with `year`, `quarter`, `indicator`, `value`, `source`.
#'
#' @seealso [enoe_benchmark()]
#' @export
enoe_reference <- function(series, scale = 1, token = Sys.getenv("INEGI_TOKEN"),
                           source = c("BIE", "BISE"), area = "00",
                           fetch = .inegi_fetch) {
  source <- match.arg(source)
  if (is.null(names(series)) || any(!nzchar(names(series))))
    stop("'series' must be a named vector: indicator name = INEGI id.")
  raw <- inegi_series(unname(series), token = token, source = source,
                      area = area, fetch = fetch)

  m   <- regmatches(raw$time_period, regexec("^(\\d{4})/0([1-4])$", raw$time_period))
  ok  <- lengths(m) == 3L & grepl("trim", raw$freq, ignore.case = TRUE)
  if (!any(ok))
    stop("No quarterly observations recognised; inspect inegi_series() output.")
  if (any(!ok))
    warning(sprintf("%d observation(s) dropped (not quarterly 'YYYY/0Q').",
                    sum(!ok)), call. = FALSE)
  raw <- raw[ok]; m <- m[ok]

  sc <- if (length(scale) == 1L) rep(scale, length(series))
        else scale[names(series)]
  names(sc) <- names(series)
  data.table::data.table(
    year      = vapply(m, function(p) as.integer(p[2L]), integer(1L)),
    quarter   = vapply(m, function(p) as.integer(p[3L]), integer(1L)),
    indicator = names(series)[match(raw$id, unname(series))],
    value     = raw$value * sc[names(series)[match(raw$id, unname(series))]],
    source    = paste0("INEGI ", source)
  )
}
