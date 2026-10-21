library(testthat)
library(data.table)

# One dwelling-household-person per id; `n_ent` rises with the calendar quarter
mk_q <- function(con, n_ent, eda, sex = 1L, tipo = NULL) {
  sdem <- data.table(
    CD_A = 1L, ENT = 9L, CON = con, V_SEL = 1L, N_HOG = 1L, H_MUD = 0L,
    N_REN = 1L, R_DEF = 0L, C_RES = 1L, EDA = eda, SEX = sex, N_ENT = n_ent
  )
  hog <- data.table(
    CD_A = 1L, ENT = 9L, CON = con, V_SEL = 1L, N_HOG = 1L, H_MUD = 0L,
    R_DEF = 0L, N_ENT = n_ent
  )
  if (!is.null(tipo)) {
    sdem[, TIPO := tipo]
    hog[, TIPO := tipo]
  }
  list(sdem = sdem, hog = hog)
}

test_that("person panel follows ids and checks n_ent against calendar gap", {
  x <- list(
    enoe_2019_t1 = mk_q(c(1L, 2L), n_ent = c(1L, 2L), eda = c(30L, 40L)),
    enoe_2019_t2 = mk_q(c(1L, 3L), n_ent = c(2L, 1L), eda = c(30L, 22L))
  )
  p <- enoe_panel(x, level = "person")
  expect_equal(nrow(p), 4L)
  expect_equal(p[panel_id == "9-1-1-1-0-1#1", n_obs], c(2L, 2L))
  expect_equal(p[panel_id == "9-1-1-1-0-1#1", gap], c(NA, 1L))
  expect_true(all(p$n_ent_ok %in% c(NA, TRUE)))
  ret <- attr(p, "enoe_checks")$retention
  expect_equal(ret$retention, 0.5)           # 1 of 2 followed
})

test_that("'personal' alias and household level work", {
  x <- list(
    enoe_2019_t1 = mk_q(1L, 1L, 30L),
    enoe_2019_t2 = mk_q(1L, 2L, 30L)
  )
  expect_equal(nrow(enoe_panel(x, "personal")), 2L)
  h <- enoe_panel(x, level = "household")
  expect_equal(nrow(h), 2L)
  expect_false("age_ok" %in% names(h))
  expect_equal(h$panel_id[1], "9-1-1-1-0#1")
})

test_that("2020 Q1 -> Q3 gap is two calendar quarters", {
  x <- list(
    enoe_2020_t1 = mk_q(1L, 3L, 30L),
    enoe_2020_t3 = mk_q(1L, 5L, 30L, tipo = 1L)
  )
  p <- enoe_panel(x, "person")
  expect_equal(p$gap, c(NA, 2L))
  expect_true(p$n_ent_ok[2])
})

test_that("sample selects face-to-face, phone or the complete sample", {
  x <- list(
    enoe_2021_t1 = mk_q(c(1L, 2L), 1L, c(30L, 31L), tipo = c(1L, 2L))
  )
  expect_equal(nrow(enoe_panel(x, "person")), 2L)                       # all
  expect_equal(nrow(enoe_panel(x, "person", sample = "face_to_face")), 1L)
  expect_equal(nrow(enoe_panel(x, "person", sample = "phone")), 1L)
})

test_that("quarters without tipo count as face-to-face", {
  x <- list(enoe_2019_t1 = mk_q(1L, 1L, 30L))
  expect_equal(nrow(enoe_panel(x, "person", sample = "face_to_face")), 1L)
  expect_equal(nrow(enoe_panel(x, "person", sample = "phone")), 0L)
})

test_that("monthly phone records keep one row per id and quarter", {
  q <- mk_q(c(1L, 1L, 1L), n_ent = c(5L, 6L, 7L), eda = 30L, tipo = 2L)
  q$sdem[, MES_CAL := c(7L, 8L, 9L)]
  q$hog[,  MES_CAL := c(7L, 8L, 9L)]
  x <- list(enoe_2020_t3 = q)
  first <- enoe_panel(x, "person")
  expect_equal(nrow(first), 1L)
  expect_equal(first$mes_cal, 7L)
  expect_equal(attr(first, "enoe_checks")$phone_months_dropped, 2L)
  last <- enoe_panel(x, "person", phone_month = "last")
  expect_equal(last$mes_cal, 9L)
})

test_that("n_ent_ok is NA for ENOE-N phone records and evaluated from 2023", {
  mk <- function(n_ent, tipo) mk_q(1L, n_ent, 30L, tipo = tipo)
  old <- list(enoe_2021_t1 = mk(5L, 2L), enoe_2021_t2 = mk(9L, 2L))
  p <- enoe_panel(old, "person")
  expect_true(is.na(p$n_ent_ok[2]))
  new <- list(enoe_2023_t1 = mk(1L, 1L), enoe_2023_t2 = mk(2L, 2L),
              enoe_2023_t3 = mk(5L, 2L))
  p <- enoe_panel(new, "person")
  expect_equal(p$n_ent_ok, c(NA, TRUE, NA))   # 3rd record starts a new spell
  expect_equal(p$spell, c(1L, 1L, 2L))
})

test_that("reused slot after the 5th interview starts a new spell", {
  x <- list(
    enoe_2019_t1 = mk_q(1L, 5L, 30L, sex = 1L),
    enoe_2019_t2 = mk_q(1L, 1L, 20L, sex = 2L)   # n_ent resets: other person
  )
  p <- enoe_panel(x, "person")
  expect_equal(p$spell, c(1L, 2L))
  expect_equal(length(unique(p$panel_id)), 2L)
  expect_equal(p$n_obs, c(1L, 1L))
  expect_equal(attr(p, "enoe_checks")$flags$n_ent_spell_breaks, 1L)
  expect_equal(attr(p, "enoe_checks")$flags$sex_inconsistent, 0L)
})

test_that("flags report inconsistent age and sex within a spell", {
  x <- list(
    enoe_2019_t1 = mk_q(1L, 1L, 30L, sex = 1L),
    enoe_2019_t2 = mk_q(1L, 2L, 20L, sex = 2L)
  )
  fl <- attr(enoe_panel(x, "person"), "enoe_checks")$flags
  expect_equal(fl$n_ent_inconsistent, 0L)
  expect_equal(fl$age_inconsistent, 1L)
  expect_equal(fl$sex_inconsistent, 1L)
})

test_that("min_waves filters ids and bad names error", {
  x <- list(
    enoe_2019_t1 = mk_q(c(1L, 2L), 1L, c(30L, 40L)),
    enoe_2019_t2 = mk_q(1L, 2L, 30L)
  )
  expect_equal(length(unique(enoe_panel(x, "person", min_waves = 2L)$panel_id)), 1L)
  names(x) <- c("a", "b")
  expect_error(enoe_panel(x, "person"), "enoe_")
})

test_that("duplicated (id, quarter) warns", {
  q <- mk_q(c(1L, 1L), 1L, c(30L, 30L))
  x <- list(enoe_2019_t1 = q)
  expect_warning(enoe_panel(x, "person"), "duplicated")
})
