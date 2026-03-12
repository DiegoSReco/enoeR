# ============================================================
#  enoe_utils.R
#  Panel assembly helpers
# ============================================================

#' Extract one table from all quarters in a panel list
#'
#' @description
#' Given a panel object returned by [enoe_list()], extracts the same
#' table from every quarter and returns it as a named list.
#' Quarters where the table is `NULL` are silently dropped.
#'
#' @param panel Named list as returned by [enoe_list()].
#' @param table_name Character scalar. Name of the table to extract
#'   (e.g. `"sdem"`, `"coe1t"`).
#'
#' @return Named list of `data.table` objects, one per quarter that
#'   successfully loaded `table_name`.
#'
#' @examples
#' \dontrun{
#' panel     <- enoe_list(2022, 2023)
#' sdem_list <- enoe_extract(panel, "sdem")
#' }
#'
#' @seealso [enoe_stack()]
#' @export
enoe_extract <- function(panel, table_name) {
  if (!is.character(table_name) || length(table_name) != 1L)
    stop("'table_name' must be a single character string.")

  out <- lapply(panel, function(q) {
    if (is.null(q)) return(NULL)
    q[[table_name]]
  })
  out <- Filter(Negate(is.null), out)

  if (length(out) == 0L)
    warning(glue::glue(
      "Table '{table_name}' was not found in any quarter of the panel."
    ))

  out
}


#' Stack one table across all quarters into a single data.table
#'
#' @description
#' Calls [enoe_extract()] and then row-binds all quarters with
#' `data.table::rbindlist()`.  A `period` column is appended to identify
#' the source quarter (e.g. `"enoe_2023_t1"`).  Columns that differ
#' across quarters (e.g. new variables introduced by INEGI) are filled
#' with `NA` for quarters where they are absent (`fill = TRUE`).
#'
#' @param panel Named list as returned by [enoe_list()].
#' @param table_name Character scalar. Name of the table to stack.
#' @param add_period Logical. If `TRUE` (default), adds a `period` column.
#'
#' @return A single `data.table` with all quarters stacked and an optional
#'   `period` identifier column.
#'
#' @examples
#' \dontrun{
#' panel    <- enoe_list(2022, 2024)
#' sdem_all <- enoe_stack(panel, "sdem")
#' sdem_all[, .N, by = period]   # rows per quarter
#' }
#'
#' @seealso [enoe_extract()]
#' @importFrom data.table rbindlist
#' @export
enoe_stack <- function(panel, table_name, add_period = TRUE) {
  tbls <- enoe_extract(panel, table_name)
  if (length(tbls) == 0L) return(data.table::data.table())

  if (add_period) {
    tbls <- lapply(names(tbls), function(nm) {
      dt <- data.table::copy(tbls[[nm]])
      dt[, period := nm]
      dt
    })
  }

  data.table::rbindlist(tbls, use.names = TRUE, fill = TRUE)
}


#' Print metadata from an enoe_list panel
#'
#' @description
#' Convenience function to display the `enoe_meta` attribute attached by
#' [enoe_list()].
#'
#' @param panel Named list as returned by [enoe_list()].
#'
#' @return Invisibly returns the metadata list.
#'
#' @examples
#' \dontrun{
#' panel <- enoe_list(2023, 2024)
#' enoe_meta(panel)
#' }
#'
#' @export
enoe_meta <- function(panel) {
  meta <- attr(panel, "enoe_meta")
  if (is.null(meta)) {
    message("No 'enoe_meta' attribute found. Was this created by enoe_list()?")
    return(invisible(NULL))
  }

  cat(glue::glue("
── enoe_meta ─────────────────────────────────────
  Period    : {meta$start_year} Q{meta$start_q} → {meta$end_year} Q{meta$end_q}
  Tables    : {paste(meta$tables, collapse = ', ')}
  Quarters  : {meta$n_quarters} total  |  {meta$n_ok} OK  |  {meta$n_failed} failed
  Timestamp : {format(meta$timestamp, '%Y-%m-%d %H:%M:%S')}
"), "\n")

  if (length(meta$failed_keys) > 0L)
    cat("  Failed    :", paste(meta$failed_keys, collapse = ", "), "\n")

  invisible(meta)
}
