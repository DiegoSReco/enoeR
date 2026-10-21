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
- Loads any combination of the five questionnaire modules (.csv format) in a single
  ZIP download
- Supports multi-period batch downloads with retry logic
- Provides helpers to assemble long-format `data.table` panels across
  quarters
- Joins the five tables of a quarter with INEGI's identification keys, at
  person or household level, with built-in data-quality checks
- Builds an individual or household **rotating panel** across quarters,
  following INEGI's tracking rules

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
remotes::install_github("DiegoSReco/enoeR")
```
If error use `force = TRUE` to force installation.

---
## Quick start

### Single quarter

```r
library(enoeR)

# Load all five tables for Q1 2024
q1_2024 <- enoeR::enoe_load(2024, 1)

# Access tables
q1_2024$sdem    # socio-demographic
q1_2024$coe1t   # occupation module 1

# Load only selected tables
q1_2024 <- enoeR::enoe_load(2024, 1, tables = c("sdem", "coe1t"))
```

### Multiple quarters (In Progress)

```r
# All quarters 2022–2024
enoe_list_output <- enoeR::enoe_list(2022, 2024)

# Print download metadata
enoeR::enoe_meta(enoe_list_output)

# Access a specific quarter
sdem_2023q1 <- enoe_list_output$enoe_2023_t1$sdem
```

### Extract and stacked (In Progress)

```r
library(data.table)

# Extract SDEM from all quarters as a list
sdem_list <- enoeR::enoe_extract(enoe_list_output, "sdem")

# Stack into a single long data.table
sdem_all <- enoeR::enoe_stack(enoe_list_output, "sdem")
sdem_all[, .N, by = period]
```

### Join the tables of a quarter

```r
q <- enoeR::enoe_load(2019, 1)

# One row per resident: SDEM + COE1T + COE2T + HOG + VIV
persons    <- enoeR::enoe_join(q, level = "person")      # "personal" also works
# One row per household: HOG + VIV
households <- enoeR::enoe_join(q, level = "household")

# Only complete interviews of residents aged 12-98 (INEGI rules)
persons <- enoeR::enoe_join(q, level = "person", filter_valid = TRUE)

attr(persons, "enoe_checks")   # duplicated keys, unmatched rows, row counts
```

Keys follow INEGI: `ent, con, v_sel` (dwelling) + `n_hog, h_mud` (household)
+ `n_ren` (person). `cd_a`, `tipo`, `mes_cal` and `ca` are added when present
in both tables (2020 Q3 onwards). Column names are returned in lower case.
Duplicated keys raise a warning, and a join that changes the row count is an
error.

### Rotating panel

```r
x <- enoeR::enoe_list(2016, 2020, end_q = 1, tables = "sdem")

# Individual panel, complete interviews only
panel <- enoeR::enoe_panel(x, level = "person", filter_valid = TRUE)

# Household panel observed at least twice
hh <- enoeR::enoe_panel(x, level = "household", min_waves = 2)

# Restrict to one sample (2020 Q3 onwards)
enoeR::enoe_panel(x, sample = "face_to_face")   # tipo == 1
enoeR::enoe_panel(x, sample = "phone")          # tipo == 2

attr(panel, "enoe_checks")$retention
```

ENOE is a rotating panel: a dwelling is interviewed five times (`n_ent` 1-5),
so at most 4/5 of the sample can be followed between consecutive quarters.

- INEGI **reuses the dwelling key**: after the fifth interview it can come back
  with `n_ent = 1` for another household or person. `enoe_panel()` starts a
  new `spell` whenever `n_ent` does not advance by the calendar gap, and
  `panel_id` is `slot_id#spell`.
- By default the **complete sample** is used (face-to-face and phone). In
  2020 Q3-2022 Q4 (ENOE-N) phone households are interviewed monthly, so one
  record per id and quarter is kept (`phone_month = "first"` or `"last"`) and
  `n_ent` counts months for them. From 2023 phone interviews follow the usual
  rotation.
- 2020 Q2 has no ENOE data, so the 2020 Q1 to Q3 gap is two calendar quarters.
- Output columns: `panel_id`, `slot_id`, `spell`, `period`, `year`, `quarter`,
  `period_idx`, `wave`, `n_obs`, `gap`, plus `n_ent_ok`, `age_ok` and `sex_ok`
  flags. Flags are for review; rows are never dropped because of them.
- `enoe_checks` holds duplicates, phone months dropped, rows per period, the
  distribution of observations per unit, retention between quarters and flag
  counts.

Use `fac_tri` (quarterly) or `fac_men` (monthly, with `mes_cal`) as weights
from 2020 Q3, and `fac` before.

**Validation.** [`data-raw/replicate_alvarado_panel.R`](data-raw/replicate_alvarado_panel.R)
rebuilds the panel of Alvarado, Orraca and Cabrera-Hernández (2023, *El
Trimestre Económico* 90(4)): ENOE 2016 Q1-2020 Q1, ages 15-65, northern border
states. It gives 274,693 individuals and 882,866 observations against 274,613
and 882,652 in the paper (within 0.03%).

---

## Function reference

| Function | Description |
|---|---|
| `enoe_load(año, n_trim, tables, quiet)` | Download a single quarter |
| `enoe_list(start_year, end_year, ...)` | Batch download across multiple quarters |
| `enoe_extract(enoe_list_output, table_name)` | Extract one table from all quarters |
| `enoe_stack(enoe_list_output, table_name)` | Stack table into one long `data.table` |
| `enoe_meta(enoe_list_output)` | Print download metadata |
| `enoe_join(x, level, filter_valid, checks)` | Join the tables of a quarter at `"person"` or `"household"` level, with data-quality checks |
| `enoe_panel(enoe_list_output, level, sample, phone_month, min_waves, ...)` | Long rotating panel at `"person"` or `"household"` level, with spells, rotation checks and quality flags |

### Examples by function

```r
library(enoeR)

# enoe_load(): one quarter, selected tables
q <- enoe_load(2019, 1, tables = c("sdem", "coe1t"), quiet = TRUE)

# enoe_list(): several quarters (2020 Q2 is skipped: ETOE)
x <- enoe_list(2019, 2020, end_q = 3, tables = c("sdem", "hog"))

# enoe_meta(): what was downloaded, and what failed
enoe_meta(x)

# enoe_extract(): one table per quarter, as a named list
sdem_list <- enoe_extract(x, "sdem")
names(sdem_list)

# enoe_stack(): one long table with a `period` column
sdem_all <- enoe_stack(x, "sdem")
sdem_all[, .N, by = period]

# enoe_join(): a quarter, or every quarter of an enoe_list() result
persons_q  <- enoe_join(q, level = "person")
households <- enoe_join(x, level = "household")   # named list, one per quarter
attr(persons_q, "enoe_checks")

# enoe_panel(): individuals followed across quarters
panel <- enoe_panel(x, level = "person", filter_valid = TRUE)
panel[, .N, by = n_obs]                  # units by number of observations
attr(panel, "enoe_checks")$flags         # n_ent / age / sex consistency

# Households seen in at least three quarters
hh3 <- enoe_panel(x, level = "household", min_waves = 3)
```

---

## Development roadmap

- [x] `enoe_load()` — single quarter, all tables - March 11, 2026
- [x] `enoe_list()` — multi-period batch with retries - March 19, 2026
- [x] `enoe_meta()` — print meta data of the download
- [x] `enoe_stack()` / `enoe_extract()` — cross-sectional assembly helpers
- [x] `enoe_join()` — join the tables of a quarter (person / household)
- [x] `enoe_panel()` — rotating panel (person / household), validated against Alvarado et al. (2023)
- [ ] `enoe_codebook()` — variable labels from INEGI dictionaries

---

## Citation

```
@software{enoeR2025,
  author  = {DiegoSReco},
  title   = {{enoeR}: Download and Process Mexico's ENOE Labour Force Survey Microdata},
  year    = {2025},
  url     = {https://github.com/your-username/enoeR}
}
```

---

## Data source

INEGI. *Encuesta Nacional de Ocupación y Empleo (ENOE), población
de 15 años y más de edad*. Instituto Nacional de Estadística y Geografía.
<https://www.inegi.org.mx/programas/enoe/15ymas/>
