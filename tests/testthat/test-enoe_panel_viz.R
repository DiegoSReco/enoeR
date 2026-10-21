library(testthat)
library(data.table)

mk_q <- function(con, n_ent, tipo = NULL) {
  sdem <- data.table(
    CD_A = 1L, ENT = 9L, CON = con, V_SEL = 1L, N_HOG = 1L, H_MUD = 0L,
    N_REN = 1L, R_DEF = 0L, C_RES = 1L, EDA = 30L, SEX = 1L, N_ENT = n_ent
  )
  list(sdem = sdem)
}

# Units: A (n_ent 3,4,5 -> exits by design in t3), B (1,2 then lost), C new in t2
x <- list(
  enoe_2019_t1 = mk_q(c(1L, 2L), n_ent = c(3L, 1L)),
  enoe_2019_t2 = mk_q(c(1L, 3L), n_ent = c(4L, 1L)),
  enoe_2019_t3 = mk_q(c(1L, 3L), n_ent = c(5L, 2L))
)

test_that("enoe_panel accepts a named list of enoe_join() results", {
  joined <- lapply(x, enoe_join, level = "person")
  from_joined <- enoe_panel(joined, level = "person")
  from_raw    <- enoe_panel(x, level = "person")
  expect_equal(from_joined[, .(panel_id, period_idx, n_obs, gap)],
               from_raw[, .(panel_id, period_idx, n_obs, gap)])
  expect_equal(nrow(from_joined), 6L)
})

test_that("pre-joined input needs names and ignores filter_valid with a warning", {
  joined <- lapply(x, enoe_join, level = "person")
  unnamed <- unname(joined)
  expect_error(enoe_panel(unnamed, "person"), "named")
  expect_warning(enoe_panel(joined, "person", filter_valid = TRUE), "ignored")
  # inputs untouched
  expect_false("period" %in% names(joined[[1]]))
})

test_that("any 'YYYY_tQ' name is accepted", {
  joined <- lapply(x, enoe_join, level = "person")
  names(joined) <- c("2019_t1", "2019_t2", "2019_t3")
  expect_equal(nrow(enoe_panel(joined, "person")), 6L)
})

test_that("enoe_panel_flow separates followed, design exit and attrition", {
  p  <- enoe_panel(x, "person")
  fl <- enoe_panel_flow(p)$flow
  # t1: A (n_ent 3) followed, B lost -> attrition 1
  expect_equal(fl[period == "2019-Q1", c(n, n_followed, n_attrition, n_design_exit)],
               c(2L, 1L, 1L, 0L))
  # t2: A (n_ent 4) followed, C followed
  expect_equal(fl[period == "2019-Q2", c(n_followed, n_attrition)], c(2L, 0L))
  expect_equal(fl[period == "2019-Q2", match_rate], 1)
  # last quarter: outcome unknown
  expect_true(is.na(fl[period == "2019-Q3", match_rate]))
  expect_equal(fl[period == "2019-Q3", n_new], 0L)
  expect_equal(fl[period == "2019-Q2", n_new], 1L)
})

test_that("design exit is not counted as attrition", {
  y <- list(
    enoe_2019_t1 = mk_q(1L, 5L),
    enoe_2019_t2 = mk_q(2L, 1L)
  )
  fl <- enoe_panel_flow(enoe_panel(y, "person"))$flow
  expect_equal(fl[period == "2019-Q1", c(n_design_exit, n_attrition)], c(1L, 0L))
  expect_equal(fl[period == "2019-Q1", match_rate], NaN)   # nobody at risk
})

test_that("cohort table counts units by first quarter and quarter", {
  coh <- enoe_panel_flow(enoe_panel(x, "person"))$cohorts
  expect_equal(coh[cohort_label == "2019-Q1" & period == "2019-Q2", n], 1L)
  expect_equal(coh[cohort_label == "2019-Q2" & period == "2019-Q3", n], 1L)
})

test_that("enoe_panel_flow rejects non-panel input", {
  expect_error(enoe_panel_flow(data.table(a = 1)), "enoe_panel")
})

test_that("plots return ggplot objects", {
  skip_if_not_installed("ggplot2")
  p <- enoe_panel(x, "person")
  for (tp in c("cohorts", "match", "outcome"))
    expect_s3_class(enoe_panel_plot(p, tp), "ggplot")
})

test_that("enoe_schema describes the tables, keys and panel unit", {
  s <- enoe_schema()
  expect_s3_class(s, "enoe_schema")
  expect_match(s, "erDiagram")
  expect_match(s, "VIV  \\|\\|--o\\{ HOG")
  expect_match(s, "PANEL_UNIT")
  expect_false(grepl("PANEL_UNIT", enoe_schema(include_panel = FALSE)))
  expect_output(print(s), "```mermaid")
})

test_that("enoe_panel_diagram shows followed counts between consecutive quarters", {
  d <- enoe_panel_diagram(enoe_panel(x, "person"))
  ln <- strsplit(unclass(d), "\n", fixed = TRUE)[[1]]
  expect_s3_class(d, "enoe_schema")
  expect_equal(ln[1], "flowchart LR")
  expect_true('  Q1 -->|"followed 1"| Q2' %in% ln)           # A followed, B lost
  expect_true('  Q1 -.->|"attrition 1"| A1(["lost"])' %in% ln)
  expect_true('  Q2 -->|"followed 2"| Q3' %in% ln)
  expect_false(any(grepl("  Q2 -.->", ln, fixed = TRUE)))                 # no losses in t2
  expect_true(any(grepl('Q1["2019-Q1<br/>2 units<br/>(2 new)"]', ln, fixed = TRUE)))
  expect_output(print(d), "```mermaid", fixed = TRUE)
})

test_that("diagram does not link non-consecutive quarters", {
  y <- list(
    enoe_2019_t1 = mk_q(1L, 1L),
    enoe_2019_t3 = mk_q(1L, 3L)
  )
  d <- enoe_panel_diagram(enoe_panel(y, "person"))
  expect_false(grepl("-->", d, fixed = TRUE))
})
