# enoeR <img src="man/figures/logo.png" align="right" height="139" alt="" />

<!-- badges: start -->
[![R-CMD-check](https://github.com/your-username/enoeR/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/your-username/enoeR/actions/workflows/R-CMD-check.yaml)
[![Codecov test coverage](https://codecov.io/gh/your-username/enoeR/branch/main/graph/badge.svg)](https://app.codecov.io/gh/your-username/enoeR?branch=main)
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
<!-- badges: end -->

> **Download and process Mexico's National Survey of Occupation and Employment (ENOE) microdata directly from INEGI.**

---

## Overview

`enoeR` provides a clean, reproducible R interface for working with the
**ENOE** (*Encuesta Nacional de Ocupación y Empleo*) microdata, Mexico's
primary household labour force survey published quarterly by
[INEGI](https://www.inegi.org.mx/programas/enoe/15ymas/).

The package:

- Automatically resolves the correct download URL for all survey
  editions (2005 – present), including the post-COVID **ENOE-N** redesign
- Loads any combination of the five questionnaire modules in a single
  ZIP download
- Supports multi-period batch downloads with retry logic
- Provides helpers to assemble long-format `data.table` panels across
  quarters

---

## Survey editions covered

| Period                   | Edition  | URL pattern                          |
|--------------------------|----------|--------------------------------------|
| 2005 Q1 – 2020 Q1        | ENOE     | `{year}trim{q}_csv.zip`              |
| 2020 Q2                  | ETOE ⚠  | _Not available — telephone survey_   |
| 2020 Q3 – 2022 Q4        | ENOE-N   | `enoe_n_{year}_trim{q}_csv.zip`      |
| 2023 Q1 onwards          | ENOE     | `enoe_{year}_trim{q}_csv.zip`        |

---

## Tables available

| Code   | Module (Spanish)                                | Key content                     |
|--------|-------------------------------------------------|---------------------------------|
| `sdem` | Características sociodemográficas (SDEM)        | Demographics, education, wages  |
| `coe1t`| Cuestionario de Ocupación y Empleo 1 (COE1)     | Employment status, hours        |
| `coe2t`| Cuestionario de Ocupación y Empleo 2 (COE2)     | Secondary job, earnings detail  |
| `hog`  | Cuestionario de Hogar (HOG)                     | Household composition           |
| `viv`  | Cuestionario de Vivienda (VIV)                  | Dwelling characteristics        |

---

## Installation

```r
# Development version from GitHub
# install.packages("remotes")
remotes::install_github("your-username/enoeR")
```

---

## Quick start

### Single quarter

```r
library(enoeR)

# Load all five tables for Q1 2024
q1_2024 <- enoe_load(2024, 1)

# Access tables
q1_2024$sdem    # socio-demographic
q1_2024$coe1t   # occupation module 1

# Load only selected tables
q1_2024 <- enoe_load(2024, 1, tables = c("sdem", "coe1t"))
```

### Multiple quarters

```r
# All quarters 2022–2024
panel <- enoe_list(2022, 2024)

# Print download metadata
enoe_meta(panel)

# Access a specific quarter
sdem_2023q1 <- panel$enoe_2023_t1$sdem
```

### Panel assembly

```r
library(data.table)

# Extract SDEM from all quarters as a list
sdem_list <- enoe_extract(panel, "sdem")

# Stack into a single long data.table
sdem_all <- enoe_stack(panel, "sdem")
sdem_all[, .N, by = period]
```

### Wage-gap analysis workflow

```r
# 1. Download two years of SDEM
panel <- enoe_list(2023, 2024, tables = c("sdem", "coe1t"))
sdem  <- enoe_stack(panel, "sdem")

# 2. Prime-age full-time workers
sdem_pw <- sdem[
  eda      %between% c(25L, 54L) &
  emp_ppal == 1L                 &
  hrsocup  %between% c(35L, 48L)
]

# 3. Log hourly wage
sdem_pw[, log_wage := log(ing_x_hrs)]

# 4. Raw gender gap
sdem_pw[, .(mean_log_wage = mean(log_wage, na.rm = TRUE)), by = .(sex, period)]
```

---

## Function reference

| Function | Description |
|---|---|
| `enoe_load(año, n_trim, tables, quiet)` | Download a single quarter |
| `enoe_list(start_year, end_year, ...)` | Batch download across multiple quarters |
| `enoe_extract(panel, table_name)` | Extract one table from all quarters |
| `enoe_stack(panel, table_name)` | Stack table into one long `data.table` |
| `enoe_meta(panel)` | Print download metadata |

---

## Development roadmap

- [x] `enoe_load()` — single quarter, all tables
- [x] `enoe_list()` — multi-period batch with retries
- [x] `enoe_stack()` / `enoe_extract()` — panel assembly helpers
- [ ] `enoe_codebook()` — variable labels from INEGI dictionaries
- [ ] Heckman selection correction helper for wage-gap analysis
- [ ] Oaxaca-Blinder and Słoczyński decomposition wrappers
- [ ] Chernozhukov–Fernández-Val–Melly unconditional quantile decomposition

---

## Citation

```
@software{enoeR2025,
  author  = {Your Name},
  title   = {{enoeR}: Download and Process Mexico's ENOE Labour Force Survey Microdata},
  year    = {2025},
  url     = {https://github.com/your-username/enoeR}
}
```

---

## Data source

INEGI (2024). *Encuesta Nacional de Ocupación y Empleo (ENOE), población
de 15 años y más de edad*. Instituto Nacional de Estadística y Geografía.
<https://www.inegi.org.mx/programas/enoe/15ymas/>
