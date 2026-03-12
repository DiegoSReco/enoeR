library(testthat)
library(enoeR)

# ── Tests for .build_url() ────────────────────────────────────────────────────

test_that(".build_url returns correct pattern for 2005–2019", {
  url <- enoeR:::.build_url(
    "https://www.inegi.org.mx/contenidos/programas/enoe/15ymas/microdatos",
    2015L, 2L
  )
  expect_match(url, "2015trim2_csv\\.zip$")
})

test_that(".build_url returns ENOE-N pattern for 2021", {
  url <- enoeR:::.build_url(
    "https://www.inegi.org.mx/contenidos/programas/enoe/15ymas/microdatos",
    2021L, 3L
  )
  expect_match(url, "enoe_n_2021_trim3_csv\\.zip$")
})

test_that(".build_url returns new pattern for 2023+", {
  url <- enoeR:::.build_url(
    "https://www.inegi.org.mx/contenidos/programas/enoe/15ymas/microdatos",
    2023L, 1L
  )
  expect_match(url, "enoe_2023_trim1_csv\\.zip$")
})

# ── Input validation ──────────────────────────────────────────────────────────

test_that("enoe_load rejects year < 2005", {
  expect_error(enoe_load(2004, 1), "2005")
})

test_that("enoe_load rejects invalid quarter", {
  expect_error(enoe_load(2020, 5), "n_trim")
})

test_that("enoe_load raises informative error for ETOE 2020 Q2", {
  expect_error(enoe_load(2020, 2), "ETOE")
})

test_that("enoe_load rejects unknown table names", {
  expect_error(enoe_load(2023, 1, tables = "wrong_table"))
})

# ── enoe_list validation ──────────────────────────────────────────────────────

test_that("enoe_list rejects start_year > end_year", {
  expect_error(enoe_list(2024, 2022), "start_year")
})

test_that("enoe_list rejects start_q > end_q in same year", {
  expect_error(enoe_list(2023, 2023, start_q = 3, end_q = 1), "start_q")
})

# ── enoe_extract and enoe_stack ───────────────────────────────────────────────

test_that("enoe_extract returns empty list and warning for missing table", {
  fake_panel <- list(
    enoe_2023_t1 = list(sdem = data.table::data.table(x = 1:3)),
    enoe_2023_t2 = list(sdem = data.table::data.table(x = 4:6))
  )
  expect_warning(
    result <- enoe_extract(fake_panel, "coe1t"),
    "not found"
  )
  expect_equal(length(result), 0L)
})

test_that("enoe_stack returns a data.table with period column", {
  fake_panel <- list(
    enoe_2023_t1 = list(sdem = data.table::data.table(id = 1:3, wage = c(100, 200, 300))),
    enoe_2023_t2 = list(sdem = data.table::data.table(id = 4:6, wage = c(150, 250, 350)))
  )
  result <- enoe_stack(fake_panel, "sdem")
  expect_s3_class(result, "data.table")
  expect_true("period" %in% names(result))
  expect_equal(nrow(result), 6L)
  expect_equal(sort(unique(result$period)), c("enoe_2023_t1", "enoe_2023_t2"))
})

test_that("enoe_stack respects add_period = FALSE", {
  fake_panel <- list(
    enoe_2023_t1 = list(sdem = data.table::data.table(id = 1:3))
  )
  result <- enoe_stack(fake_panel, "sdem", add_period = FALSE)
  expect_false("period" %in% names(result))
})

test_that("enoe_stack fills missing columns with NA", {
  fake_panel <- list(
    enoe_2023_t1 = list(sdem = data.table::data.table(id = 1, wage = 100)),
    enoe_2023_t2 = list(sdem = data.table::data.table(id = 2, wage = 200, new_var = 99))
  )
  result <- enoe_stack(fake_panel, "sdem")
  expect_true("new_var" %in% names(result))
  expect_true(is.na(result[period == "enoe_2023_t1", new_var]))
})
