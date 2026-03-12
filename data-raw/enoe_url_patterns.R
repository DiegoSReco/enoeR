# ============================================================
#  data-raw/enoe_url_patterns.R
#  Documents all known INEGI URL conventions for ENOE ZIPs
#  Run this script to regenerate internal reference data (future use)
# ============================================================

# URL base
BASE <- "https://www.inegi.org.mx/contenidos/programas/enoe/15ymas/microdatos"

# Known editions and their URL patterns
enoe_url_patterns <- data.frame(
  edition      = c("ENOE",   "ENOE (COVID Q1)", "ETOE",    "ENOE-N",          "ENOE (2023+)"),
  period_start = c("2005 Q1", "2020 Q1",         "2020 Q2", "2020 Q3",         "2023 Q1"),
  period_end   = c("2019 Q4", "2020 Q1",         "2020 Q2", "2022 Q4",         "present"),
  url_pattern  = c(
    "{BASE}/{year}trim{q}_csv.zip",
    "{BASE}/{year}trim{q}_csv.zip",
    "https://www.inegi.org.mx/contenidos/investigacion/etoe (telephone only)",
    "{BASE}/enoe_n_{year}_trim{q}_csv.zip",
    "{BASE}/enoe_{year}_trim{q}_csv.zip"
  ),
  stringsAsFactors = FALSE
)

print(enoe_url_patterns)

# INEGI changed internal file naming conventions multiple times.
# Key irregularity: 2020 Q4 uses lowercase in the ZIP internal filename
# (enoen_sdemt4XX.csv) while other ENOE-N quarters use uppercase (ENOEN_SDEM...).
# This is handled by case-insensitive regex matching in .load_single_table().
