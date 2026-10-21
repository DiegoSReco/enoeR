# ============================================================
#  data-raw/replicate_alvarado_panel.R
#  Rebuild the individual panel of Alvarado, Orraca and
#  Cabrera-Hernandez (2023), "El efecto de duplicar el salario
#  minimo...", El Trimestre Economico 90(4), 961-999, using enoeR.
#
#  Only the panel is replicated (sample, unit, periods), not the
#  estimates. Paper (section III.1, ENOE):
#    - ENOE 2016 Q1 - 2020 Q1 (17 quarters)
#    - persons aged 15-65 living in the northern border states:
#      Baja California, Sonora, Chihuahua, Coahuila, Nuevo Leon, Tamaulipas
#    - unbalanced panel: 274,613 individuals, 882,652 observations
#      (34% living in the ZLFN; not reproduced here because the list of
#      the 43 municipalities is not in the documents used)
#
#  Run from the package root:  Rscript data-raw/replicate_alvarado_panel.R
#  Set ENOER_CACHE to a folder to keep the downloaded tables between runs.
# ============================================================

pkgload::load_all(".", quiet = TRUE)
library(data.table)

# INEGI state codes of the six northern border states
border_states <- c(BC = 2L, CHIH = 8L, COAH = 5L, NL = 19L, SON = 26L, TAMPS = 28L)
paper <- list(individuals = 274613L, observations = 882652L)

# ── 1. Download (cached) ─────────────────────────────────────
cache_dir  <- Sys.getenv("ENOER_CACHE", tempdir())
cache_file <- file.path(cache_dir, "enoe_2016q1_2020q1_sdem.rds")

if (file.exists(cache_file)) {
  x <- readRDS(cache_file)
} else {
  x <- enoe_list(2016, 2020, start_q = 1, end_q = 1, tables = "sdem",
                 quiet = FALSE)
  saveRDS(x, cache_file)
}
cat("Download date:", format(attr(x, "enoe_meta")$timestamp), "\n")

# ── 2. Panel at person level, complete interviews only ───────
# filter_valid keeps r_def == 0, c_res in (1, 3), eda 12-98 (INEGI sec. 5)
panel <- enoe_panel(x, level = "person", sample = "all", filter_valid = TRUE)

# ── 3. Paper's sample: ages 15-65, border states ─────────────
panel <- panel[as.integer(eda) %in% 15L:65L & as.integer(ent) %in% border_states]
panel[, `:=`(n_obs = .N, wave = seq_len(.N)), by = panel_id]

# ── 4. Compare with the paper ────────────────────────────────
n_ind <- uniqueN(panel$panel_id)
n_obs <- nrow(panel)
cmp <- data.table(
  item   = c("individuals", "observations", "obs per individual"),
  enoeR  = c(n_ind, n_obs, round(n_obs / n_ind, 3)),
  paper  = c(paper$individuals, paper$observations,
             round(paper$observations / paper$individuals, 3))
)
cmp[, ratio := round(enoeR / paper, 4)]
print(cmp)

cat("\nQuarters:", uniqueN(panel$period), "(paper: 17)\n")
cat("\nObservations per individual (n_obs):\n")
print(panel[, .N, by = .(panel_id, n_obs)][, .(individuals = .N), by = n_obs][order(n_obs)])
cat("\nRows per quarter:\n"); print(panel[, .N, by = .(year, quarter)][order(year, quarter)])

# ── 5. Data-quality checks from enoe_panel() ─────────────────
chk <- attr(enoe_panel(x, level = "person", filter_valid = TRUE), "enoe_checks")
cat("\nDuplicates (id, quarter):", chk$duplicates, "\n")
cat("Flags (unrestricted sample):\n"); print(unlist(chk$flags))
cat("Retention between consecutive quarters (design ceiling 0.8):\n")
print(chk$retention[, retention := round(retention, 3)])

invisible(panel)
