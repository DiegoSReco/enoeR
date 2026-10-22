# ============================================================
#  enoe_panel_viz.R
#  Panel schema, flows (matches / attrition) and plots
# ============================================================

#' @keywords internal
.period_label <- function(period_idx) {
  sprintf("%d-Q%d", period_idx %/% 4L, period_idx %% 4L + 1L)
}

#' Matches and attrition of a panel
#'
#' @description
#' Summarises, for every quarter of an [enoe_panel()] result, how many units
#' were observed, how many are new, and what happens to them in the next
#' quarter:
#'
#' * `followed`: observed again in the next calendar quarter (a successful
#'   match);
#' * `design_exit`: leaving by design, because `n_ent == 5` (fifth interview);
#' * `attrition`: neither followed nor at their fifth interview, so lost.
#'
#' The last quarter has no next quarter, so its outcome is `NA`. `n_ent` is
#' needed to separate design exits from attrition; without it every unit that
#' is not followed is counted as `attrition`.
#'
#' @param panel Output of [enoe_panel()].
#'
#' @return A list with `flow` (one row per quarter: `n`, `n_new`,
#'   `n_continuing`, `n_followed`, `n_design_exit`, `n_attrition`,
#'   `match_rate` = followed / (n - design exits), `attrition_rate`) and
#'   `cohorts` (units by first quarter observed and quarter).
#'
#' @details
#' `n_new` in the first quarter of the panel is left-censored: those units may
#' have been interviewed before the panel starts.
#'
#' @seealso [enoe_panel()], [enoe_panel_plot()]
#' @export
enoe_panel_flow <- function(panel) {
  need <- c("panel_id", "period_idx", "wave")
  if (!all(need %in% names(panel)))
    stop("'panel' must come from enoe_panel(): missing ",
         paste(setdiff(need, names(panel)), collapse = ", "), ".")

  has_nent <- "n_ent" %in% names(panel)
  d <- panel[, c("panel_id", "period_idx", "wave",
                 if (has_nent) "n_ent"), with = FALSE]

  nxt <- d[, list(panel_id, period_idx = period_idx - 1L, .f = TRUE)]
  d <- merge(d, nxt, by = c("panel_id", "period_idx"), all.x = TRUE)
  last <- max(d$period_idx)
  d$followed <- ifelse(d$period_idx == last, NA, !is.na(d$.f))
  d$design_exit <- if (has_nent) d$followed %in% FALSE & as.integer(d$n_ent) == 5L
                   else FALSE
  d$attrition <- d$followed %in% FALSE & !d$design_exit

  flow <- d[, list(
    n             = .N,
    n_new         = sum(wave == 1L),
    n_continuing  = sum(wave > 1L),
    n_followed    = sum(followed, na.rm = TRUE),
    n_design_exit = sum(design_exit),
    n_attrition   = sum(attrition)
  ), by = period_idx]
  data.table::setorderv(flow, "period_idx")
  flow$period <- .period_label(flow$period_idx)
  flow$at_risk <- flow$n - flow$n_design_exit
  flow$match_rate <- ifelse(flow$period_idx == last, NA_real_,
                            flow$n_followed / flow$at_risk)
  flow$attrition_rate <- ifelse(flow$period_idx == last, NA_real_,
                                flow$n_attrition / flow$at_risk)
  flow[, at_risk := NULL]
  data.table::setcolorder(flow, c("period_idx", "period"))

  first <- d[, list(cohort = min(period_idx)), by = panel_id]
  coh <- merge(d[, list(panel_id, period_idx)], first, by = "panel_id")
  coh <- coh[, list(n = .N), by = list(cohort, period_idx)]
  data.table::setorderv(coh, c("cohort", "period_idx"))
  coh$cohort_label <- .period_label(coh$cohort)
  coh$period <- .period_label(coh$period_idx)

  list(flow = flow, cohorts = coh)
}


#' Plot the matches and attrition of a panel
#'
#' @description
#' * `"cohorts"`: heatmap of units by first quarter observed (rows) and
#'   quarter (columns), the rotation triangle of the survey.
#' * `"match"`: share of units that could be followed and were (`match_rate`)
#'   per quarter. Without losses it is 1.
#' * `"outcome"`: units of each quarter split by what happens next quarter:
#'   followed, design exit (fifth interview) or attrition.
#' * `"flow"`: flowchart drawn in R (no Mermaid needed): one box per quarter,
#'   arrows with the units followed, and boxes below with design exits and
#'   attrition. Same content as [enoe_panel_diagram()].
#'
#' Requires the suggested package `ggplot2`.
#'
#' @param panel Output of [enoe_panel()].
#' @param type `"cohorts"`, `"match"`, `"outcome"` or `"flow"`.
#'
#' @return A `ggplot` object.
#'
#' @examples
#' \dontrun{
#' p <- enoe_panel(enoe_list(2022, 2023, tables = "sdem"), "person")
#' enoe_panel_plot(p, "cohorts")
#' enoe_panel_plot(p, "outcome")
#' }
#'
#' @seealso [enoe_panel_flow()], [enoe_schema()]
#' @export
enoe_panel_plot <- function(panel, type = c("cohorts", "match", "outcome", "flow")) {
  type <- match.arg(type)
  if (!requireNamespace("ggplot2", quietly = TRUE))
    stop("Package 'ggplot2' is needed for plots: install.packages(\"ggplot2\").")
  fl <- enoe_panel_flow(panel)
  lv <- .period_label(sort(unique(panel$period_idx)))
  gg <- ggplot2::ggplot
  aes <- ggplot2::aes

  if (type == "cohorts") {
    d <- fl$cohorts
    d$period       <- factor(d$period, levels = lv)
    d$cohort_label <- factor(d$cohort_label, levels = rev(lv))
    return(
      gg(d, aes(period, cohort_label, fill = n)) +
        ggplot2::geom_tile(colour = "white") +
        ggplot2::geom_text(aes(label = format(n, big.mark = ",")), size = 2.5) +
        ggplot2::scale_fill_gradient(low = "#e8f1fa", high = "#1f5f99") +
        ggplot2::labs(title = "Panel cohorts", x = "Quarter",
                      y = "First quarter observed", fill = "Units") +
        ggplot2::theme_minimal() +
        ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))
    )
  }

  f <- fl$flow
  f$period <- factor(f$period, levels = lv)
  if (type == "match") {
    return(
      gg(f[!is.na(f$match_rate), ], aes(period, match_rate, group = 1)) +
        ggplot2::geom_line(colour = "#1f5f99") + ggplot2::geom_point(colour = "#1f5f99") +
        ggplot2::geom_text(aes(label = sprintf("%s of %s",
                                format(n_followed, big.mark = ","),
                                format(n - n_design_exit, big.mark = ","))),
                           vjust = -0.8, size = 2.6) +
        ggplot2::geom_hline(yintercept = 1, linetype = "dashed", colour = "grey40") +
        ggplot2::labs(title = "Share of followable units matched next quarter",
                      x = "Quarter", y = "Match rate") +
        ggplot2::theme_minimal() +
        ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))
    )
  }

  if (type == "flow") {
    fmt <- function(x) format(x, big.mark = ",", trim = TRUE)
    f$x <- seq_len(nrow(f))
    nodes <- data.frame(
      x = f$x, y = 0,
      label = sprintf("%s\n%s units\n(%s new)", f$period, fmt(f$n), fmt(f$n_new))
    )
    link <- which(diff(f$period_idx) == 1L)
    arr <- data.frame(x = f$x[link] + 0.36, xend = f$x[link + 1L] - 0.36, y = 0,
                      label = sprintf("followed\n%s", fmt(f$n_followed[link])))
    de <- f[f$x %in% link & f$n_design_exit > 0L, ]
    at <- f[f$x %in% link & f$n_attrition > 0L, ]
    p <- gg() +
      ggplot2::geom_segment(data = arr, aes(x = x, xend = xend, y = y, yend = y),
                            colour = "#1f5f99", linewidth = 0.8,
                            arrow = ggplot2::arrow(length = grid::unit(0.18, "cm"))) +
      ggplot2::geom_text(data = arr, aes(x = (x + xend) / 2, y = y + 0.28, label = label),
                         size = 2.6, colour = "#1f5f99", lineheight = 0.9) +
      ggplot2::geom_label(data = nodes, aes(x = x, y = y, label = label),
                          size = 2.8, fill = "#e8f1fa", lineheight = 0.95)
    if (nrow(de) > 0L)
      p <- p +
        ggplot2::geom_segment(data = de, aes(x = x, xend = x, y = -0.2, yend = -0.4),
                              linetype = "dotted", colour = "grey40") +
        ggplot2::geom_label(data = de, aes(x = x, y = -0.6,
                            label = paste0("design exit\n", fmt(n_design_exit))),
                            size = 2.5, fill = "#eceff1", lineheight = 0.95)
    if (nrow(at) > 0L)
      p <- p +
        ggplot2::geom_segment(data = at, aes(x = x, xend = x, y = -0.82, yend = -1.0),
                              linetype = "dotted", colour = "#c0392b") +
        ggplot2::geom_label(data = at, aes(x = x, y = -1.22,
                            label = paste0("attrition\n", fmt(n_attrition))),
                            size = 2.5, fill = "#fdecea", colour = "#c0392b",
                            lineheight = 0.95)
    return(
      p + ggplot2::scale_x_continuous(expand = ggplot2::expansion(add = 0.7)) +
        ggplot2::scale_y_continuous(expand = ggplot2::expansion(add = 0.4)) +
        ggplot2::labs(title = "Units followed between quarters",
                      subtitle = "Last quarter has no next quarter observed") +
        ggplot2::theme_void() +
        ggplot2::theme(plot.title = ggplot2::element_text(face = "bold"))
    )
  }

  long <- data.table::melt(
    f[, c("period", "n_followed", "n_design_exit", "n_attrition"), with = FALSE],
    id.vars = "period", variable.name = "outcome", value.name = "units"
  )
  long$outcome <- factor(
    long$outcome,
    levels = c("n_attrition", "n_design_exit", "n_followed"),
    labels = c("Attrition", "Design exit (n_ent = 5)", "Followed")
  )
  last <- levels(f$period)[nlevels(f$period)]
  long <- long[long$period != last, ]
  gg(long, aes(period, units, fill = outcome)) +
    ggplot2::geom_col() +
    ggplot2::geom_text(aes(label = ifelse(units > 0, format(units, big.mark = ","), "")),
                       position = ggplot2::position_stack(vjust = 0.5),
                       size = 2.6, colour = "white") +
    ggplot2::scale_fill_manual(values = c(Attrition = "#c0392b",
      `Design exit (n_ent = 5)` = "#b0b7c0", Followed = "#1f5f99")) +
    ggplot2::labs(title = "What happens to each quarter's units next quarter",
                  subtitle = "Last quarter omitted: no next quarter observed",
                  x = "Quarter", y = "Units", fill = NULL) +
    ggplot2::theme_minimal() +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))
}


#' Diagram of the units followed between quarters
#'
#' @description
#' Mermaid flowchart with one node per quarter (units observed, of which new)
#' and the number of units **followed** to the next quarter on the arrows.
#' Dotted arrows show units that left by design (`n_ent == 5`) and units lost
#' to attrition, as in [enoe_panel_flow()]. Quarters that are not consecutive
#' (for example after 2020 Q2) are not linked. The last quarter has no
#' outgoing arrows.
#'
#' @param panel Output of [enoe_panel()].
#'
#' @return A character string of class `enoe_schema`; `print()` shows it as a
#'   fenced Mermaid block that GitHub, Quarto and R Markdown render. With many
#'   quarters the diagram gets long; subset the panel first.
#'
#' @examples
#' \dontrun{
#' p <- enoe_panel(enoe_list(2023, 2024, tables = "sdem"), "person")
#' enoe_panel_diagram(p)
#' }
#'
#' @seealso [enoe_panel_flow()], [enoe_panel_plot()]
#' @export
enoe_panel_diagram <- function(panel) {
  f   <- enoe_panel_flow(panel)$flow
  fmt <- function(x) format(x, big.mark = ",", trim = TRUE)
  k   <- nrow(f)
  node <- sprintf('  Q%d["%s<br/>%s units<br/>(%s new)"]', seq_len(k), f$period,
                  fmt(f$n), fmt(f$n_new))
  edges <- character()
  for (i in seq_len(k - 1L)) {
    if (f$period_idx[i + 1L] != f$period_idx[i] + 1L) next
    edges <- c(edges, sprintf('  Q%d -->|"followed %s"| Q%d', i, fmt(f$n_followed[i]), i + 1L))
    if (f$n_design_exit[i] > 0L)
      edges <- c(edges, sprintf('  Q%d -.->|"design exit %s"| D%d(["n_ent = 5"])',
                                i, fmt(f$n_design_exit[i]), i))
    if (f$n_attrition[i] > 0L)
      edges <- c(edges, sprintf('  Q%d -.->|"attrition %s"| A%d(["lost"])',
                                i, fmt(f$n_attrition[i]), i))
  }
  structure(paste(c("flowchart LR", node, edges), collapse = "
"),
            class = c("enoe_schema", "character"))
}


#' Database schema of the ENOE tables and the panel
#'
#' @description
#' Returns a Mermaid `erDiagram` showing how the five tables relate through
#' INEGI's identification keys (INEGI, "Conociendo la base de datos", sec. 4),
#' optionally with the panel unit built by [enoe_panel()]. GitHub, Quarto and
#' R Markdown render Mermaid code blocks.
#'
#' Cardinalities: a dwelling has one or more households; a household one or
#' more residents; a COE record exists only for residents with `r_def = 00`,
#' `c_res` 1 or 3 and `eda` 12-98.
#'
#' @param include_panel Logical. Add the panel unit (`panel_id` = `slot_id#spell`)
#'   and its quarterly observations. Default `TRUE`.
#'
#' @return A character string of class `enoe_schema`; `print()` shows it as a
#'   fenced Mermaid block.
#'
#' @examples
#' enoe_schema()
#' enoe_schema(include_panel = FALSE)
#'
#' @seealso [enoe_join()], [enoe_panel()]
#' @export
enoe_schema <- function(include_panel = TRUE) {
  lines <- c(
    "erDiagram",
    "  VIV  ||--o{ HOG   : \"ent, con, v_sel\"",
    "  HOG  ||--o{ SDEM  : \"+ n_hog, h_mud\"",
    "  SDEM ||--o| COE1T : \"+ n_ren\"",
    "  SDEM ||--o| COE2T : \"+ n_ren\"",
    "  VIV {",
    "    int ent PK",
    "    int con PK",
    "    int v_sel PK",
    "  }",
    "  HOG {",
    "    int ent PK",
    "    int con PK",
    "    int v_sel PK",
    "    int n_hog PK",
    "    int h_mud PK",
    "    int r_def",
    "  }",
    "  SDEM {",
    "    int ent PK",
    "    int con PK",
    "    int v_sel PK",
    "    int n_hog PK",
    "    int h_mud PK",
    "    int n_ren PK",
    "    int n_ent",
    "    int c_res",
    "    int eda",
    "  }",
    "  COE1T {",
    "    int n_ren PK",
    "  }",
    "  COE2T {",
    "    int n_ren PK",
    "  }"
  )
  if (include_panel) {
    lines <- c(lines,
      "  PANEL_UNIT ||--o{ SDEM : \"observed each quarter\"",
      "  PANEL_UNIT {",
      "    string panel_id PK \"slot_id#spell\"",
      "    string slot_id \"ent-con-v_sel-n_hog-h_mud-n_ren\"",
      "    int spell \"new when n_ent breaks\"",
      "    int n_obs",
      "  }")
  }
  structure(paste(lines, collapse = "\n"), class = c("enoe_schema", "character"))
}

#' @export
print.enoe_schema <- function(x, ...) {
  cat("```mermaid\n", unclass(x), "\n```\n", sep = "")
  invisible(x)
}
