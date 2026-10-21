# ============================================================
#  enoe_join.R
#  Join the ENOE tables of the same quarter
# ============================================================

# Identification keys (INEGI, "Seguimiento e identificacion de viviendas" and
# "Conociendo la base de datos", section 4).
#' @keywords internal
.level_keys <- list(
  dwelling  = c("ent", "con", "v_sel"),
  household = c("ent", "con", "v_sel", "n_hog", "h_mud"),
  person    = c("ent", "con", "v_sel", "n_hog", "h_mud", "n_ren")
)

# Grain of each table
#' @keywords internal
.tbl_level <- c(sdem = "person", coe1t = "person", coe2t = "person",
                hog = "household", viv = "dwelling")

# Extra key fields, used only when present in both tables being joined:
# `tipo` and `mes_cal` exist from 2020 Q3; `ca` in 2020 Q3 - 2021 Q2.
#' @keywords internal
.extra_keys <- c("cd_a", "tipo", "mes_cal", "ca")

#' @keywords internal
.enoe_level <- function(level) {
  level <- tolower(level[[1L]])
  if (level == "personal") level <- "person"
  if (!level %in% c("person", "household"))
    stop("'level' must be \"person\" (or \"personal\") or \"household\".")
  level
}

#' @keywords internal
.is_quarter <- function(x) {
  is.list(x) && !is.data.frame(x) && any(vapply(x, is.data.frame, logical(1L)))
}

#' @keywords internal
.enoe_lower <- function(dt) {
  dt <- data.table::copy(data.table::as.data.table(dt))
  data.table::setnames(dt, tolower(names(dt)))
  if ("cve_ent" %in% names(dt) && !"ent" %in% names(dt))
    data.table::setnames(dt, "cve_ent", "ent")
  dt
}

#' @keywords internal
.join_keys <- function(x_names, y_names, level, label) {
  base   <- .level_keys[[level]]
  common <- intersect(x_names, y_names)
  miss   <- setdiff(base, common)
  if (length(miss) > 0L)
    stop(sprintf("Key column(s) %s missing in table '%s' or in the base table.",
                 paste(miss, collapse = ", "), label), call. = FALSE)
  c(base, intersect(.extra_keys, common))
}

# Rows eligible for the questionnaire of occupation and employment:
# R_DEF = 00, C_RES in (1, 3), EDA in 12:98 (INEGI, section 5).
#' @keywords internal
.eligible_person <- function(dt) {
  need <- c("r_def", "c_res", "eda")
  if (!all(need %in% names(dt))) return(rep(TRUE, nrow(dt)))
  as.integer(dt[["r_def"]]) == 0L &
    as.integer(dt[["c_res"]]) %in% c(1L, 3L) &
    as.integer(dt[["eda"]]) %in% 12L:98L
}

#' @keywords internal
.enoe_join_quarter <- function(q, level, filter_valid, checks) {
  tbl <- lapply(Filter(is.data.frame, q), .enoe_lower)

  if (level == "person") {
    base_nm <- "sdem"
    others  <- intersect(c("coe1t", "coe2t", "hog", "viv"), names(tbl))
  } else {
    base_nm <- "hog"
    others  <- intersect("viv", names(tbl))
  }
  if (!base_nm %in% names(tbl))
    stop(sprintf("Table '%s' is required for level = \"%s\".", base_nm, level),
         call. = FALSE)

  qc <- list()
  add_check <- function(check, table, n, detail = "") {
    qc[[length(qc) + 1L]] <<- data.table::data.table(
      check = check, table = table, n = as.integer(n), detail = detail
    )
  }

  dedupe <- function(dt, keys, label) {
    n_dup <- sum(duplicated(dt, by = keys))
    add_check("duplicated_keys", label, n_dup,
              paste(keys, collapse = "+"))
    if (n_dup > 0L) {
      warning(sprintf("'%s': %d duplicated key row(s) on (%s); keeping the first.",
                      label, n_dup, paste(keys, collapse = ", ")),
              call. = FALSE)
      dt <- unique(dt, by = keys)
    }
    dt
  }

  base <- tbl[[base_nm]]
  keys_base <- .join_keys(names(base), names(base), .tbl_level[[base_nm]], base_nm)
  base <- dedupe(base, keys_base, base_nm)

  if (filter_valid) {
    need <- if (level == "person") c("r_def", "c_res", "eda") else "r_def"
    if (!all(need %in% names(base)))
      stop(sprintf("filter_valid = TRUE needs column(s): %s.",
                   paste(need, collapse = ", ")), call. = FALSE)
    keep <- if (level == "person") .eligible_person(base)
            else as.integer(base[["r_def"]]) == 0L
    add_check("filter_valid_dropped", base_nm, sum(!keep))
    base <- base[keep]
  }
  n0 <- nrow(base)
  elig <- if (level == "person") .eligible_person(base) else rep(TRUE, n0)

  for (nm in others) {
    y    <- tbl[[nm]]
    keys <- .join_keys(names(base), names(y), .tbl_level[[nm]], nm)
    y    <- dedupe(y, keys, nm)

    dup_cols <- setdiff(intersect(names(base), names(y)), keys)
    if (length(dup_cols) > 0L) data.table::set(y, j = dup_cols, value = NULL)

    flag <- paste0(".in_", nm)
    data.table::set(y, j = flag, value = TRUE)
    base <- merge(base, y, by = keys, all.x = TRUE, sort = FALSE)

    if (checks) {
      expected <- if (nm %in% c("coe1t", "coe2t")) elig else rep(TRUE, n0)
      add_check("unmatched_rows", nm, sum(expected & is.na(base[[flag]])),
                if (nm %in% c("coe1t", "coe2t")) "eligible persons without COE row"
                else "rows without a match")
    }
    data.table::set(base, j = flag, value = NULL)
  }

  if (nrow(base) != n0)
    stop(sprintf("Join changed the row count (%d -> %d); check the keys.",
                 n0, nrow(base)), call. = FALSE)

  if (checks) {
    add_check("n_rows", base_nm, n0)
    if ("eda" %in% names(base))
      add_check("eda_out_of_range", base_nm,
                sum(!as.integer(base[["eda"]]) %in% 0L:99L, na.rm = TRUE),
                "eda outside 0-99")
    attr(base, "enoe_checks") <- data.table::rbindlist(qc)
  }
  base
}


#' Join the ENOE tables of the same quarter
#'
#' @description
#' Joins the tables of one quarter (as returned by [enoe_load()]) using the
#' identification keys documented by INEGI. Column names are lower-cased and
#' the inputs are not modified.
#'
#' * `level = "person"`: SDEM is the base; COE1T, COE2T, HOG and VIV are
#'   left-joined to it. One row per resident.
#' * `level = "household"`: HOG is the base and VIV is left-joined to it.
#'   One row per household.
#'
#' Keys are `ent, con, v_sel` (dwelling), plus `n_hog, h_mud` (household),
#' plus `n_ren` (person). `cd_a`, `tipo`, `mes_cal` and `ca` are added
#' automatically when present in both tables being joined (2020 Q3 onwards),
#' since a phone-sample household can appear up to three times in a quarter.
#'
#' Columns present in the base table and in a joined table (for example the
#' weights) are kept from the base table only.
#'
#' @param x A list of tables from [enoe_load()], or a list of such lists from
#'   [enoe_list()] (then a named list of joined tables is returned).
#' @param level `"person"` (alias `"personal"`) or `"household"`.
#' @param filter_valid Logical. If `TRUE`, keeps only complete interviews
#'   (`r_def == 0`) and, for `level = "person"`, residents with `c_res` in
#'   1 or 3 and `eda` 12-98 (INEGI, "Conociendo la base de datos", sec. 5).
#'   Default `FALSE`.
#' @param checks Logical. If `TRUE` (default), attaches a data-quality table
#'   as attribute `"enoe_checks"` (duplicated keys, unmatched rows, row counts,
#'   age range).
#'
#' @return A `data.table` (or a named list of them). Duplicated keys raise a
#'   warning and the first row is kept. A join that changes the row count of
#'   the base table is an error.
#'
#' @examples
#' \dontrun{
#' q <- enoe_load(2023, 1)
#' persons    <- enoe_join(q, level = "person")
#' households <- enoe_join(q, level = "household")
#' attr(persons, "enoe_checks")
#' }
#'
#' @seealso [enoe_panel()]
#' @importFrom data.table as.data.table copy setnames set rbindlist data.table
#' @export
enoe_join <- function(x, level = c("person", "household"),
                      filter_valid = FALSE, checks = TRUE) {
  level <- .enoe_level(level)

  if (.is_quarter(x))
    return(.enoe_join_quarter(x, level, filter_valid, checks))

  if (!is.list(x) || !any(vapply(x, .is_quarter, logical(1L))))
    stop("'x' must be the output of enoe_load() or enoe_list().")

  lapply(x, function(q) {
    if (is.null(q)) NULL else .enoe_join_quarter(q, level, filter_valid, checks)
  })
}
