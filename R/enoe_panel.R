# ============================================================
#  enoe_panel.R
#  Build a rotating-panel dataset across quarters
# ============================================================

#' Build a long panel from several ENOE quarters
#'
#' @description
#' Joins each quarter with [enoe_join()], stacks them, and adds a tracking id
#' so the same unit can be followed across quarters.
#'
#' * `level = "person"` (alias `"personal"`): key is
#'   `ent-con-v_sel-n_hog-h_mud-n_ren`.
#' * `level = "household"`: key is `ent-con-v_sel-n_hog-h_mud`.
#'
#' The key (`slot_id`) is reused by INEGI: once a dwelling leaves the sample
#' (after the fifth interview) the same key can return with `n_ent = 1` for
#' another household or person. A new `spell` therefore starts whenever
#' `n_ent` does not advance by the calendar gap, and `panel_id` is
#' `slot_id#spell`, one unit followed for at most five interviews.
#'
#' By default the complete sample is used (`sample = "all"`): face-to-face
#' (`tipo == 1`) and phone (`tipo == 2`) interviews, which exist from 2020 Q3.
#' Use `sample = "face_to_face"` or `"phone"` to restrict it.
#'
#' @details
#' ENOE is a rotating panel: a dwelling is interviewed five times (`n_ent`
#' 1-5), so between two consecutive quarters at most 4/5 of the sample can be
#' followed, and 3/5 across two quarters. Since 2020 Q2 has no ENOE data, the
#' 2020 Q1 -> Q3 gap spans two calendar quarters and `n_ent` rises by 2.
#'
#' ## Phone sample
#' * 2020 Q3 - 2022 Q4 (ENOE-N): phone households come from the ETOE sample,
#'   are interviewed monthly with no quarterly rotation, and can appear up to
#'   three times in one quarter (INEGI, "Seguimiento e identificacion de
#'   viviendas"). A panel row needs one record per id and quarter, so the
#'   record of the `phone_month` (first or last `mes_cal` available) is kept
#'   and the others are counted in the checks. For these records `n_ent`
#'   counts months (5 to 11), so `n_ent_ok` is `NA` when either record of a
#'   pair is an ENOE-N phone record.
#' * 2023 Q1 onwards: INEGI states that phone interviews take place from the
#'   second interview within the usual rotation. These records are treated
#'   like any other and `n_ent_ok` is evaluated. This coding of `tipo` in 2023+
#'   is not detailed in the documents used; review the flags on real data.
#'
#' Use `fac_tri` (quarterly) or `fac_men` (monthly, with `mes_cal`) as weights
#' from 2020 Q3; `fac` before.
#'
#' The id follows the identification fields documented by INEGI. It does not
#' prove that the same person was matched, so person-level flags are returned
#' for review, not used to drop rows.
#'
#' @param enoe_list_output Either the output of [enoe_list()] (tables are
#'   joined internally with [enoe_join()]) or a **named list of [enoe_join()]
#'   results**, one per quarter, to build the panel from tables you joined
#'   yourself (for example SDEM + COE1T). Elements must be named
#'   `enoe_{year}_t{quarter}`. Pre-joined tables need the id columns of the
#'   chosen `level`; `filter_valid` must then be applied in [enoe_join()].
#' @param level `"person"` (alias `"personal"`) or `"household"`.
#' @param sample `"all"` (default), `"face_to_face"` (`tipo == 1`) or
#'   `"phone"` (`tipo == 2`). Quarters without a `tipo` column (before
#'   2020 Q3) are face-to-face and are dropped when `sample = "phone"`.
#' @param phone_month `"first"` (default) or `"last"`: which monthly record to
#'   keep when an id has several in one quarter.
#' @param min_waves Integer. Keep only ids observed at least this many times.
#'   Default `1`.
#' @param ... Passed to [enoe_join()] (e.g. `filter_valid = TRUE`).
#'
#' @return A `data.table` in long format (one row per id and quarter) with
#'   columns `panel_id`, `slot_id`, `spell`, `period`, `year`, `quarter`, `period_idx`
#'   (`year * 4 + quarter - 1`), `wave` (order of observation), `n_obs`,
#'   `gap` (calendar quarters since the previous observation) and, when
#'   `n_ent` exists, `n_ent_ok` (`n_ent` change equals `gap`). At person level
#'   with `eda` / `sex`, `age_ok` and `sex_ok` are added. The attribute
#'   `"enoe_checks"` is a list with `duplicates`, `phone_months_dropped`,
#'   `rows_by_period`,
#'   `n_obs_distribution`, `retention` and `flags`.
#'
#' @examples
#' \dontrun{
#' x <- enoe_list(2022, 2023)
#' p <- enoe_panel(x, level = "person")
#' h <- enoe_panel(x, level = "household", min_waves = 2)
#'
#' # From tables joined by hand: SDEM + COE1T of three quarters
#' q <- list(
#'   enoe_2024_t4 = enoe_join(enoe_load(2024, 4, c("sdem", "coe1t")), "person"),
#'   enoe_2025_t1 = enoe_join(enoe_load(2025, 1, c("sdem", "coe1t")), "person"),
#'   enoe_2025_t2 = enoe_join(enoe_load(2025, 2, c("sdem", "coe1t")), "person")
#' )
#' p <- enoe_panel(q, level = "person")
#' attr(p, "enoe_checks")$retention
#' }
#'
#' @seealso [enoe_join()], [enoe_list()]
#' @importFrom data.table rbindlist setorderv shift
#' @export
enoe_panel <- function(enoe_list_output, level = c("person", "household"),
                       sample = c("all", "face_to_face", "phone"),
                       phone_month = c("first", "last"),
                       min_waves = 1L, ...) {
  level       <- .enoe_level(level)
  sample      <- match.arg(sample)
  phone_month <- match.arg(phone_month)

  src <- Filter(Negate(is.null), enoe_list_output)
  is_joined <- is.list(src) && length(src) > 0L &&
    all(vapply(src, is.data.frame, logical(1L)))
  if (is_joined) {
    quarters <- src
    if (isTRUE(list(...)$filter_valid))
      warning("'filter_valid' is ignored for pre-joined tables; apply it in enoe_join().",
              call. = FALSE)
  } else {
    quarters <- Filter(.is_quarter, enoe_list_output)
    if (length(quarters) == 0L)
      stop("'enoe_list_output' must be the output of enoe_list() or a named ",
           "list of enoe_join() results.")
  }
  if (is.null(names(quarters)))
    stop("Elements must be named 'enoe_{year}_t{quarter}'.")
  nms <- names(quarters)
  per <- .enoe_parse_period(nms)

  pieces <- lapply(seq_along(quarters), function(i) {
    dt <- if (is_joined) .enoe_lower(quarters[[i]])
          else .enoe_join_quarter(quarters[[i]], level,
                                  filter_valid = isTRUE(list(...)$filter_valid),
                                  checks = FALSE)
    if (sample != "all") {
      want <- if (sample == "phone") 2L else 1L
      # no `tipo` column (before 2020 Q3) means face-to-face
      keep <- if ("tipo" %in% names(dt)) dt[["tipo"]] %in% want
              else rep(sample == "face_to_face", nrow(dt))
      dt <- dt[keep]
    }
    yr <- per$year[i]; qt <- per$quarter[i]
    data.table::set(dt, j = "period", value = nms[i])
    data.table::set(dt, j = "year", value = yr)
    data.table::set(dt, j = "quarter", value = qt)
    data.table::set(dt, j = "period_idx", value = yr * 4L + qt - 1L)
    dt
  })
  panel <- data.table::rbindlist(pieces, use.names = TRUE, fill = TRUE)

  id_cols <- .level_keys[[level]]
  miss <- setdiff(id_cols, names(panel))
  if (length(miss) > 0L)
    stop("Missing id column(s): ", paste(miss, collapse = ", "))
  id_parts <- lapply(id_cols, function(k) as.integer(panel[[k]]))
  # slot_id is the INEGI key. It is reused: after the 5th interview the same
  # key can come back with n_ent = 1 for a different household or person.
  data.table::set(panel, j = "slot_id",
                  value = do.call(paste, c(id_parts, sep = "-")))

  # Phone households can have up to three monthly records per quarter
  n_phone_multi <- 0L
  if (all(c("tipo", "mes_cal") %in% names(panel))) {
    data.table::setorderv(panel, c("slot_id", "period_idx", "mes_cal"),
                          order = c(1L, 1L, if (phone_month == "first") 1L else -1L),
                          na.last = TRUE)
    extra <- duplicated(panel, by = c("slot_id", "period_idx")) &
      panel[["tipo"]] %in% 2L
    n_phone_multi <- sum(extra)
    if (n_phone_multi > 0L) panel <- panel[!extra]
  }

  # Remaining duplicates on (slot, quarter)
  n_dup <- sum(duplicated(panel, by = c("slot_id", "period_idx")))
  if (n_dup > 0L) {
    warning(sprintf("%d duplicated (slot_id, period) row(s); keeping the first.",
                    n_dup), call. = FALSE)
    panel <- unique(panel, by = c("slot_id", "period_idx"))
  }

  data.table::setorderv(panel, c("slot_id", "period_idx"))

  flags <- list()
  has_nent <- "n_ent" %in% names(panel)
  if (has_nent) {
    # n_ent counts months for ENOE-N phone records (2020 Q3 - 2022 Q4):
    # those pairs cannot be judged and do not split spells.
    enoen_phone <- if ("tipo" %in% names(panel))
      panel[["tipo"]] %in% 2L & panel[["year"]] <= 2022L else rep(FALSE, nrow(panel))
    data.table::set(panel, j = ".enoen_phone", value = enoen_phone)
    # A new spell starts when n_ent does not advance by the calendar gap
    panel[, spell := {
      g   <- period_idx - data.table::shift(period_idx)
      brk <- (as.integer(n_ent) - data.table::shift(as.integer(n_ent))) != g
      brk[.enoen_phone | data.table::shift(.enoen_phone, fill = FALSE)] <- NA
      cumsum(brk %in% TRUE) + 1L
    }, by = slot_id]
    flags$n_ent_spell_breaks <- sum(panel$spell > 1L & !duplicated(panel, by = c("slot_id", "spell")))
  } else {
    data.table::set(panel, j = "spell", value = 1L)
    warning("No 'n_ent' column: reused slots cannot be split into spells.",
            call. = FALSE)
  }
  data.table::set(panel, j = "panel_id",
                  value = paste0(panel$slot_id, "#", panel$spell))
  panel[, `:=`(
    wave  = seq_len(.N),
    n_obs = .N,
    gap   = period_idx - data.table::shift(period_idx)
  ), by = panel_id]

  if (has_nent) {
    panel[, n_ent_ok := {
      ok <- (as.integer(n_ent) - data.table::shift(as.integer(n_ent))) == gap
      ok[.enoen_phone | data.table::shift(.enoen_phone, fill = FALSE)] <- NA
      ok
    }, by = panel_id]
    data.table::set(panel, j = ".enoen_phone", value = NULL)
    flags$n_ent_inconsistent <- sum(panel$n_ent_ok %in% FALSE)
  }
  if (level == "person" && "eda" %in% names(panel)) {
    panel[, age_ok := {
      d <- as.integer(eda) - data.table::shift(as.integer(eda))
      d >= 0L & d <= gap %/% 4L + 1L
    }, by = panel_id]
    flags$age_inconsistent <- sum(panel$age_ok %in% FALSE)
  }
  if (level == "person" && "sex" %in% names(panel)) {
    panel[, sex_ok := sex == data.table::shift(sex), by = panel_id]
    flags$sex_inconsistent <- sum(panel$sex_ok %in% FALSE)
  }

  if (min_waves > 1L) panel <- panel[n_obs >= min_waves]

  # Retention between consecutive quarters (ceiling is 4/5 by design)
  idx <- sort(unique(panel$period_idx))
  retention <- data.table::rbindlist(lapply(idx[-1L], function(p) {
    prev <- panel$panel_id[panel$period_idx == p - 1L]
    if (length(prev) == 0L) return(NULL)
    cur  <- panel$panel_id[panel$period_idx == p]
    data.table::data.table(
      period_idx = p, n_prev = length(prev),
      n_followed = sum(prev %in% cur),
      retention  = mean(prev %in% cur)
    )
  }))

  ids <- unique(panel, by = "panel_id")
  attr(panel, "enoe_checks") <- list(
    duplicates         = n_dup,
    phone_months_dropped = n_phone_multi,
    rows_by_period     = panel[, .N, by = period],
    n_obs_distribution = ids[, .N, by = n_obs][order(n_obs)],
    retention          = retention,
    flags              = flags
  )
  panel
}
