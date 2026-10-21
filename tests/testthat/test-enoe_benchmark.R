library(testthat)
library(data.table)

# Two adults in the PEA (one unemployed), one NEA, one minor; weights 100
mk_sdem <- function(wcol = "FAC") {
  d <- data.table(
    R_DEF = 0L, C_RES = 1L, EDA = c(30L, 40L, 50L, 10L),
    CLASE1 = c(1L, 1L, 2L, 0L), CLASE2 = c(1L, 2L, 3L, 0L)
  )
  d[[wcol]] <- 100L
  d
}

test_that("enoe_indicators applies INEGI criteria and weights", {
  x <- list(enoe_2019_t1 = list(sdem = mk_sdem()))
  ind <- enoe_indicators(x)
  v <- function(k) ind[indicator == k, value]
  expect_equal(v("pob_total"), 400)
  expect_equal(v("pob_15mas"), 300)
  expect_equal(v("pea"), 200)
  expect_equal(v("nea"), 100)
  expect_equal(v("ocupados"), 100)
  expect_equal(v("desocupados"), 100)
  expect_equal(v("tasa_desocupacion"), 50)
  expect_equal(v("tasa_participacion"), 200 / 300 * 100)
  expect_equal(unique(ind$weight), "fac")
  expect_equal(ind[indicator == "pea", n], 2L)
})

test_that("fac_tri is used when present and errors are explicit", {
  x <- list(enoe_2021_t1 = list(sdem = mk_sdem("FAC_TRI")))
  expect_equal(unique(enoe_indicators(x)$weight), "fac_tri")
  bad <- mk_sdem(); bad[, CLASE1 := NULL]
  expect_error(enoe_indicators(list(enoe_2019_t1 = list(sdem = bad))), "clase1")
  expect_error(enoe_indicators(list(a = 1)), "enoe_list")
})

test_that("enoe_benchmark flags counts and rates with their own tolerance", {
  x   <- list(enoe_2019_t1 = list(sdem = mk_sdem()))
  est <- enoe_indicators(x)
  ref <- data.table(
    year = 2019L, quarter = 1L,
    indicator = c("pea", "tasa_desocupacion", "ocupados"),
    value = c(200.5, 50.05, 130), source = "test"
  )
  b <- suppressWarnings(enoe_benchmark(est, ref))
  expect_true(b[indicator == "pea", within_tolerance])
  expect_true(b[indicator == "tasa_desocupacion", within_tolerance])
  expect_false(b[indicator == "ocupados", within_tolerance])
  expect_equal(b[indicator == "tasa_desocupacion", tolerance], 0.1)
  expect_warning(enoe_benchmark(est, ref), "not both")
})

test_that("enoe_benchmark validates the reference", {
  est <- enoe_indicators(list(enoe_2019_t1 = list(sdem = mk_sdem())))
  expect_error(enoe_benchmark(est, data.frame(year = 1)), "needs columns")
  dup <- data.table(year = 2019L, quarter = 1L, indicator = "pea", value = 1:2)
  expect_error(enoe_benchmark(est, dup), "duplicated")
})

json <- paste0(
  '{"Header":{"Name":"x","Email":"y"},"Series":[{"INDICADOR":"111",',
  '"FREQ":"Trimestral","UNIT":"Personas","UNIT_MULT":"0","OBSERVATIONS":[',
  '{"TIME_PERIOD":"2019/01","OBS_VALUE":"1000"},',
  '{"TIME_PERIOD":"2019/02","OBS_VALUE":"1100"}]}]}'
)

test_that("inegi_series parses the documented response structure", {
  s <- inegi_series("111", token = "T0K3N", fetch = function(url) {
    expect_match(url, "INDICATOR/111/es/00/false/BIE/2.0/T0K3N\\?type=json$")
    json
  })
  expect_equal(s$value, c(1000, 1100))
  expect_equal(s$time_period, c("2019/01", "2019/02"))
  expect_equal(unique(s$freq), "Trimestral")
})

test_that("token is required and redacted from errors", {
  expect_error(inegi_series("111", token = ""), "INEGI_TOKEN")
  err <- tryCatch(
    inegi_series("111", token = "T0K3N",
                 fetch = function(url) stop("failed: ", url)),
    error = function(e) conditionMessage(e)
  )
  expect_false(grepl("T0K3N", err))
  expect_match(err, "<token>")
})

test_that("enoe_reference returns quarterly rows named by indicator", {
  ref <- enoe_reference(c(pea = "111"), scale = 1, token = "T0K3N",
                        fetch = function(url) json)
  expect_equal(ref$year, c(2019L, 2019L))
  expect_equal(ref$quarter, 1:2)
  expect_equal(ref$indicator, c("pea", "pea"))
  expect_equal(ref$value, c(1000, 1100))
  ref2 <- enoe_reference(c(pea = "111"), scale = 1000, token = "T0K3N",
                         fetch = function(url) json)
  expect_equal(ref2$value, c(1e6, 1.1e6))
  expect_error(enoe_reference(c("111"), token = "T0K3N", fetch = function(u) json),
               "named")
})
