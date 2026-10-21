library(testthat)
library(data.table)

# Synthetic quarter: 3 dwellings; person 2 of dwelling 100 is a minor (no COE)
make_quarter <- function(con = c(100L, 100L, 200L), n_ren = c(1L, 2L, 1L),
                         extra = list()) {
  sdem <- data.table(
    CD_A = 1L, ENT = 9L, CON = con, V_SEL = 1L, N_HOG = 1L, H_MUD = 0L,
    N_REN = n_ren, R_DEF = 0L, C_RES = 1L, EDA = c(30L, 8L, 45L),
    SEX = c(1L, 2L, 2L), N_ENT = 1L, FAC = 10L
  )
  coe1t <- data.table(
    CD_A = 1L, ENT = 9L, CON = c(100L, 200L), V_SEL = 1L, N_HOG = 1L,
    H_MUD = 0L, N_REN = 1L, P1 = 1L, FAC = 10L
  )
  hog <- data.table(
    CD_A = 1L, ENT = 9L, CON = c(100L, 200L), V_SEL = 1L, N_HOG = 1L,
    H_MUD = 0L, R_DEF = 0L, FAC = 10L
  )
  viv <- data.table(
    CD_A = 1L, ENT = 9L, CON = c(100L, 200L), V_SEL = 1L, P1_1 = 1L, FAC = 10L
  )
  c(list(sdem = sdem, coe1t = coe1t, hog = hog, viv = viv), extra)
}

test_that("person level keeps one row per resident and adds COE/HOG/VIV", {
  q <- make_quarter()
  out <- enoe_join(q, level = "person")
  expect_equal(nrow(out), 3L)
  expect_true(all(c("p1", "p1_1") %in% names(out)))
  expect_equal(sum(out$fac), 30L)            # base weights kept, no fan-out
  expect_true("enoe_checks" %in% names(attributes(out)))
})

test_that("'personal' is an alias of 'person'", {
  q <- make_quarter()
  expect_equal(nrow(enoe_join(q, level = "personal")), 3L)
})

test_that("household level is HOG + VIV", {
  out <- enoe_join(make_quarter(), level = "household")
  expect_equal(nrow(out), 2L)
  expect_true("p1_1" %in% names(out))
  expect_false("p1" %in% names(out))
})

test_that("inputs are not modified", {
  q <- make_quarter()
  enoe_join(q)
  expect_true("CON" %in% names(q$sdem))
  expect_false(".in_coe1t" %in% names(q$coe1t))
})

test_that("checks count only eligible persons as unmatched COE", {
  chk <- attr(enoe_join(make_quarter(), "person"), "enoe_checks")
  # the 8-year-old has no COE row but is not eligible
  expect_equal(chk[check == "unmatched_rows" & table == "coe1t", n], 0L)

  q <- make_quarter()
  q$coe1t <- q$coe1t[CON == 100L]            # adult of dwelling 200 loses COE
  chk <- attr(enoe_join(q, "person"), "enoe_checks")
  expect_equal(chk[check == "unmatched_rows" & table == "coe1t", n], 1L)
})

test_that("filter_valid drops minors at person level", {
  out <- enoe_join(make_quarter(), "person", filter_valid = TRUE)
  expect_equal(nrow(out), 2L)
})

test_that("duplicated keys warn and are dropped", {
  q <- make_quarter()
  q$coe1t <- rbind(q$coe1t, q$coe1t[1])
  expect_warning(out <- enoe_join(q, "person"), "duplicated key")
  expect_equal(nrow(out), 3L)
})

test_that("tipo and mes_cal join as keys when present", {
  q <- make_quarter()
  for (nm in names(q)) {
    q[[nm]][, `:=`(TIPO = 1L, MES_CAL = 1L)]
  }
  q$coe1t <- rbind(q$coe1t, copy(q$coe1t)[, MES_CAL := 2L][, P1 := 2L])
  out <- enoe_join(q, "person")
  expect_equal(nrow(out), 3L)
  expect_equal(out[con == 100L & n_ren == 1L, p1], 1L)
})

test_that("missing base table or key errors", {
  q <- make_quarter()
  q$sdem <- NULL
  expect_error(enoe_join(q, "person"), "sdem")
  q <- make_quarter()
  q$coe1t[, N_REN := NULL]
  expect_error(enoe_join(q, "person"), "n_ren")
})

test_that("a list of quarters returns a list of joined tables", {
  x <- list(enoe_2023_t1 = make_quarter(), enoe_2023_t2 = make_quarter())
  out <- enoe_join(x, "household")
  expect_named(out, c("enoe_2023_t1", "enoe_2023_t2"))
})
