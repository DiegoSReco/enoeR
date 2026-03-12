# ============================================================
#  enoe_load.R
#  Core single-quarter download function
# ============================================================

#' Download and load ENOE microdata tables for a single quarter
#'
#' @description
#' Downloads the ZIP archive for a given year and quarter from INEGI's
#' official ENOE microdata repository and loads one or more of the five
#' questionnaire modules into memory as `data.table` objects.
#'
#' The function handles all naming conventions used by INEGI across the
#' three survey editions:
#'
#' | Period                  | Edition  | URL pattern                          |
#' |-------------------------|----------|--------------------------------------|
#' | 2005 Q1 – 2020 Q1       | ENOE     | `{year}trim{q}_csv.zip`              |
#' | 2020 Q3 – 2022 Q4       | ENOE-N   | `enoe_n_{year}_trim{q}_csv.zip`      |
#' | 2023 Q1 onwards         | ENOE     | `enoe_{year}_trim{q}_csv.zip`        |
#'
#' > **Note:** 2020 Q2 does not exist as ENOE — INEGI conducted the
#' > telephone survey ETOE instead. The function raises an informative
#' > error for that quarter.
#'
#' @param año  Integer. Survey year (2005 or later).
#' @param n_trim Integer. Survey quarter (1–4).
#' @param tables Character vector. One or more of `"sdem"`, `"coe1t"`,
#'   `"coe2t"`, `"hog"`, `"viv"`. Defaults to all five.
#' @param quiet Logical. If `TRUE`, suppresses all progress messages.
#'   Default `FALSE`.
#'
#' @return A named list of `data.table` objects, one element per requested
#'   table. Elements for tables not found in the ZIP are `NULL` (with a
#'   warning).
#'
#' @details
#' ## Table descriptions
#'
#' | Code   | Full name (Spanish)                        | Key content                     |
#' |--------|--------------------------------------------|---------------------------------|
#' | `sdem` | Características sociodemográficas (SDEM)   | Demographics, education, income |
#' | `coe1t`| Cuestionario de Ocupación y Empleo 1 (COE1)| Employment status, hours worked |
#' | `coe2t`| Cuestionario de Ocupación y Empleo 2 (COE2)| Secondary job, earnings detail  |
#' | `hog`  | Cuestionario de Hogar (HOG)                | Household composition           |
#' | `viv`  | Cuestionario de Vivienda (VIV)             | Dwelling characteristics        |
#'
#' All files use Latin-1 (ISO-8859-1) encoding as published by INEGI.
#' The function reads them with `data.table::fread()` and converts to UTF-8
#' in memory.
#'
#' ## Temporary files
#' The downloaded ZIP is written to `tempdir()` and deleted via `on.exit()`
#' regardless of whether the function succeeds or fails. Individual
#' decompressed CSVs are also removed immediately after loading.
#'
#' @references
#' INEGI (2024). *Encuesta Nacional de Ocupación y Empleo (ENOE)*.
#' <https://www.inegi.org.mx/programas/enoe/15ymas/>
#'
#' @examples
#' \dontrun{
#' # Load all five tables for Q1 2024
#' q1_2024 <- enoe_load(2024, 1)
#' q1_2024$sdem   # socio-demographic table
#' q1_2024$coe1t  # occupation module 1
#'
#' # Load only SDEM and COE1T (single ZIP download, two tables)
#' q1_2024 <- enoe_load(2024, 1, tables = c("sdem", "coe1t"))
#'
#' # Suppress messages
#' q1_2024 <- enoe_load(2024, 1, quiet = TRUE)
#' }
#'
#' @seealso [enoe_list()] for multi-period downloads,
#'   [enoe_stack()] for stacking tables across quarters.
#'
#' @importFrom data.table fread
#' @importFrom glue glue
#' @importFrom curl curl_download
#' @export
enoe_load <- function(
    año,
    n_trim,
    tables = c("sdem", "coe1t", "coe2t", "hog", "viv"),
    quiet  = FALSE
) {

  # ── 0. Input validation ──────────────────────────────────────
  año    <- as.integer(año)
  n_trim <- as.integer(n_trim)
  tables <- match.arg(
    tables,
    choices      = c("sdem", "coe1t", "coe2t", "hog", "viv"),
    several.ok   = TRUE
  )

  if (is.na(año) || año < 2005L)
    stop("'año' must be an integer >= 2005.")
  if (is.na(n_trim) || !n_trim %in% 1L:4L)
    stop("'n_trim' must be 1, 2, 3, or 4.")

  # 2020 Q2: ETOE telephone survey — no ENOE microdata
  if (año == 2020L && n_trim == 2L) {
    stop(paste0(
      "ENOE Q2-2020 was suspended due to COVID-19 and replaced by the\n",
      "Telephone Survey of Occupation and Employment (ETOE).\n",
      "ETOE data: https://www.inegi.org.mx/contenidos/investigacion/etoe"
    ))
  }

  # ── 1. Build ZIP URL ─────────────────────────────────────────
  base_url <- paste0(
    "https://www.inegi.org.mx/contenidos/programas/enoe/",
    "15ymas/microdatos"
  )

  url_zip <- .build_url(base_url, año, n_trim)
  if (!quiet) message(glue("[ ENOE {año} Q{n_trim} ]  {url_zip}"))

  # ── 2. Download to temp file ─────────────────────────────────
  td <- tempdir()
  tf <- tempfile(tmpdir = td, fileext = ".zip")

  on.exit({
    if (file.exists(tf)) unlink(tf)
    if (!quiet) message("  ✓ Temporary ZIP removed.")
  }, add = TRUE)

  dir.create(td, recursive = TRUE, showWarnings = FALSE)
  if (!quiet) message("  ↓ Downloading...")
  curl::curl_download(url_zip, tf, quiet = quiet, mode = "wb")

  # ── 3. ZIP inventory ─────────────────────────────────────────
  zip_contents <- unzip(tf, list = TRUE)[["Name"]]
  csv_files    <- zip_contents[grepl("\\.csv$", zip_contents,
                                     ignore.case = TRUE)]

  if (!quiet)
    message(glue("  ℹ  {length(csv_files)} CSV(s) found in ZIP."))

  # ── 4. Load each requested table ────────────────────────────
  loaded <- lapply(tables, function(tbl) {
    .load_single_table(tbl, csv_files, tf, td, año, n_trim, quiet)
  })
  names(loaded) <- tables

  # ── 5. Summary ───────────────────────────────────────────────
  if (!quiet) {
    ok <- Filter(Negate(is.null), loaded)
    message(glue("\n  ✓ {length(ok)}/{length(tables)} table(s) loaded:"))
    for (nm in names(ok))
      message(glue("     • {nm}: {format(nrow(ok[[nm]]), big.mark = ',')} rows"))
  }

  loaded
}


# ── Internal helpers (not exported) ──────────────────────────────────────────

#' @keywords internal
.build_url <- function(base_url, año, n_trim) {
  if (año >= 2005L && año <= 2019L) {
    glue::glue("{base_url}/{año}trim{n_trim}_csv.zip")
  } else if (año == 2020L && n_trim == 1L) {
    glue::glue("{base_url}/{año}trim{n_trim}_csv.zip")
  } else if ((año == 2020L && n_trim %in% 3L:4L) ||
             (año >= 2021L  && año <= 2022L)) {
    glue::glue("{base_url}/enoe_n_{año}_trim{n_trim}_csv.zip")
  } else if (año >= 2023L) {
    glue::glue("{base_url}/enoe_{año}_trim{n_trim}_csv.zip")
  } else {
    stop(glue::glue("No URL mapping defined for {año} Q{n_trim}."))
  }
}

#' @keywords internal
.tbl_patterns <- list(
  sdem  = "(?i)(^|[_/\\\\])sdem",
  coe1t = "(?i)(^|[_/\\\\])coe1t",
  coe2t = "(?i)(^|[_/\\\\])coe2t",
  hog   = "(?i)(^|[_/\\\\])hog[t_]?\\d",
  viv   = "(?i)(^|[_/\\\\])viv[t_]?\\d"
)

#' @keywords internal
.load_single_table <- function(tbl, csv_files, tf, td, año, n_trim, quiet) {

  pat     <- .tbl_patterns[[tbl]]
  matched <- csv_files[grepl(pat, csv_files, perl = TRUE)]

  # Fallback: loose search
  if (length(matched) == 0L)
    matched <- csv_files[grepl(glue::glue("(?i){tbl}"), csv_files, perl = TRUE)]

  if (length(matched) == 0L) {
    warning(glue::glue(
      "Table '{tbl}' not found in ZIP for {año} Q{n_trim}. Returning NULL."
    ))
    return(NULL)
  }

  if (length(matched) > 1L) {
    warning(glue::glue(
      "Multiple matches for '{tbl}': {paste(matched, collapse = ', ')}.",
      " Using first match."
    ))
    matched <- matched[[1L]]
  }

  if (!quiet) message(glue::glue("  → [{tbl}]  {matched}"))

  unzip(tf, files = matched, exdir = td, overwrite = TRUE)
  fpath <- file.path(td, matched)
  on.exit(if (file.exists(fpath)) unlink(fpath), add = TRUE)

  data.table::fread(
    fpath,
    encoding     = "Latin-1",
    showProgress = !quiet,
    data.table   = TRUE
  )
}
