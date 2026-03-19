# ============================================================
#  enoe_list.R
#  Multi-period batch download
# ============================================================

#' Download ENOE microdata for multiple quarters
#'
#' @description
#' Iterates over a range of years and quarters, calling [enoe_load()] for
#' each period and collecting results in a named list.  Failed downloads
#' are skipped with a warning (network errors, missing releases) and the
#' rest of the batch continues.  An availability summary is printed upon
#' completion.
#'
#' @param start_year Integer. First year to download.
#' @param end_year   Integer. Last year to download (inclusive).
#' @param start_q    Integer. First quarter in `start_year` (1–4). Default `1`.
#' @param end_q      Integer. Last quarter in `end_year`   (1–4). Default `4`.
#' @param tables     Character vector. Tables to load per quarter.
#'   See [enoe_load()] for valid values. Default: all five.
#' @param quiet      Logical. Suppress per-quarter messages. Default `FALSE`.
#' @param retry_times Integer. Number of retries on network error. Default `2`.
#' @param retry_wait  Integer. Seconds to wait between retries. Default `10`.
#'
#' @return A named list where each element corresponds to one quarter
#'   (`"enoe_{year}_t{quarter}"`) and is itself a named list of
#'   `data.table` objects (one per table), as returned by [enoe_load()].
#'   Failed quarters are stored as `NULL`.  The list carries an
#'   `"enoe_meta"` attribute with download metadata.
#'
#' @examples
#' \dontrun{
#' # All quarters 2022–2024, all tables
#' enoe_list_output <- enoe_list(2022, 2024)
#'
#' # Only SDEM and COE1T
#' enoe_list_output <- enoe_list(2021, 2023, tables = c("sdem", "coe1t"))
#'
#' # Access one quarter
#' sdem_2023q1 <- enoe_list_output$enoe_2023_t1$sdem
#' }
#'
#' @seealso [enoe_load()], [enoe_stack()], [enoe_extract()]
#' @export
enoe_list <- function(
    start_year,
    end_year,
    start_q     = 1L,
    end_q       = 4L,
    tables      = c("sdem", "coe1t", "coe2t", "hog", "viv"),
    quiet       = FALSE,
    retry_times = 2L,
    retry_wait  = 10L
) {

  # ── 0. Validate ──────────────────────────────────────────────
  start_year <- as.integer(start_year)
  end_year   <- as.integer(end_year)
  start_q    <- as.integer(start_q)
  end_q      <- as.integer(end_q)

  if (start_year > end_year)
    stop("'start_year' must be <= 'end_year'.")
  if (!start_q %in% 1L:4L || !end_q %in% 1L:4L)
    stop("'start_q' and 'end_q' must be between 1 and 4.")
  if (start_year == end_year && start_q > end_q)
    stop("'start_q' must be <= 'end_q' when start_year == end_year.")

  # ── 1. Build quarter grid ────────────────────────────────────
  grid <- do.call(rbind, lapply(start_year:end_year, function(yr) {
    qs <- if      (yr == start_year && yr == end_year) start_q:end_q
          else if (yr == start_year)                    start_q:4L
          else if (yr == end_year)                      1L:end_q
          else                                          1L:4L
    data.frame(year = yr, quarter = qs, stringsAsFactors = FALSE)
  }))
 
  # Remove ETOE quarter
  etoe <- grid$year == 2020L & grid$quarter == 2L
  if (any(etoe)) {
    message("  ⚠  2020 Q2 excluded (ETOE period — no ENOE microdata).")
    grid <- grid[!etoe, ]
  }

  total <- nrow(grid)
  if (total == 0L) stop("No valid quarters remain after filtering.")

  if (!quiet) {
    message(glue::glue(
      "\n╔══════════════════════════════════════════════╗",
      "\n║  enoeR :: Batch Download                     ║",
      "\n║  Period : {start_year} Q{start_q}  →  {end_year} Q{end_q}  ║",
      "\n║  Tables : {paste(tables, collapse = ', ')}",
      "\n║  Quarters: {total}",
      "\n╚══════════════════════════════════════════════╝\n"
    ))
  }

  # ── 2. Download loop ─────────────────────────────────────────
  raw <- lapply(seq_len(total), function(i) {
    yr <- grid$year[i]
    qt <- grid$quarter[i]
    key <- glue::glue("enoe_{yr}_t{qt}")

    if (!quiet)
      message(glue::glue("  [{i}/{total}] {yr} Q{qt} ..."))

    result <- NULL
    elapsed <- NA_real_
    for (attempt in seq_len(retry_times + 1L)) {
      tryCatch({
        t0 <- proc.time()["elapsed"]
        result <- enoe_load(
          año    = yr,
          n_trim = qt,
          tables = tables,
          quiet  = TRUE
        )
        elapsed <- proc.time()["elapsed"] - t0 # if succeful stop timer
        break
      }, error = function(e) {
        if (attempt <= retry_times) {
          message(glue::glue(
            "    ⚠  Attempt {attempt} failed. Retrying in {retry_wait}s...",
            " ({conditionMessage(e)})"
          ))
          Sys.sleep(retry_wait)
        } else {
          message(glue::glue(
            "    ✗  FAILED after {retry_times} retries: {yr} Q{qt}.",
            " ({conditionMessage(e)})"
          ))
        }
      })
    }

    if (!quiet && !is.null(result)) {
      ok <- Filter(Negate(is.null), result)
      summary_str <- paste(
        sapply(names(ok), function(t)
        glue::glue("{t}={format(nrow(ok[[t]]), big.mark = ',')}rows")),
        collapse = " | "
      )
      message(glue::glue("    ✓ {summary_str} | time={round(elapsed, 1)}s"))
    }

    list(key = key, data = result, elapsed = elapsed)
  })

  # ── 3. Assemble output ───────────────────────────────────────
  enoe_list_output <- stats::setNames(
    lapply(raw, `[[`, "data"),
    sapply(raw, `[[`, "key")
  )

  n_ok   <- sum(!vapply(enoe_list_output, is.null, logical(1L)))
  n_fail <- total - n_ok

  if (!quiet) {
    message(glue::glue(
      "\n┌──────────────────────────────────────────────┐",
      "\n│  Complete: {n_ok}/{total} OK  |  {n_fail} failed",
      "\n└──────────────────────────────────────────────┘"
    ))
    avail_df <- data.frame(
      Quarter = names(enoe_list_output),
      Status  = ifelse(vapply(enoe_list_output, is.null, logical(1L)),
                       "FAILED", "OK"),
      stringsAsFactors = FALSE
    )
    print(avail_df, row.names = FALSE)
  }

  # ── 4. Metadata attribute ────────────────────────────────────
  attr(enoe_list_output, "enoe_meta") <- list(
    start_year  = start_year,
    end_year    = end_year,
    start_q     = start_q,
    end_q       = end_q,
    tables      = tables,
    n_quarters  = total,
    n_ok        = n_ok,
    n_failed    = n_fail,
    failed_keys = names(enoe_list_output)[vapply(enoe_list_output, is.null, logical(1L))],
    timestamp   = Sys.time()
  )

  enoe_list_output
}
