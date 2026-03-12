# ============================================================
#  enoeR-package.R
#  Package-level documentation and imports
# ============================================================

#' enoeR: Download and Process Mexico's ENOE Labour Force Survey Microdata
#'
#' @description
#' `enoeR` provides a clean, reproducible interface to Mexico's National
#' Survey of Occupation and Employment (**ENOE** — *Encuesta Nacional de
#' Ocupación y Empleo*) published by INEGI.
#'
#' ## Main functions
#'
#' | Function | Description |
#' |---|---|
#' | [enoe_load()] | Download a single quarter (all or selected tables) |
#' | [enoe_list()] | Batch download across a range of quarters |
#' | [enoe_extract()] | Pull one table from every quarter in a panel |
#' | [enoe_stack()] | Stack a table across all quarters into one `data.table` |
#' | [enoe_meta()] | Print download metadata from a panel object |
#'
#' ## Survey editions covered
#'
#' - **ENOE** (2005 Q1 – 2020 Q1)
#' - **ENOE-N** (2020 Q3 – 2022 Q4, post-COVID redesign)
#' - **ENOE** (2023 Q1 onwards, reverted naming)
#' - *2020 Q2 is excluded* (telephone ETOE survey, different instrument)
#'
#' ## Tables available
#'
#' `sdem` · `coe1t` · `coe2t` · `hog` · `viv`
#'
#' @references
#' INEGI (2024). *Encuesta Nacional de Ocupación y Empleo*.
#' <https://www.inegi.org.mx/programas/enoe/15ymas/>
#'
#' @keywords internal
"_PACKAGE"

## Suppress R CMD CHECK notes for data.table's non-standard evaluation
## and for the 'period' column added in enoe_stack()
utils::globalVariables(c("period", "."))
