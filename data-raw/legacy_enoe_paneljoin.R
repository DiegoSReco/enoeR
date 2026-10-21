

########################## ENOER ###########################
######## Process quarter, anual and total panel database ###
###############  first version #############################
############## Autor: Saul Noguez @adonix95 ################
######## Repo name: enoeR. #################################
############################################################

# ============================================
# LIBRARIES
# ============================================
library(data.table)
library(haven)
library(stringr)

# ============================================
# HELPER: CLEAN DUPLICATE COLUMNS
# ============================================
clean_for_merge <- function(x, y, by) {
  
  dup_cols <- intersect(names(x), names(y))
  dup_cols <- setdiff(dup_cols, by)
  
  if (length(dup_cols) > 0) {
    y[, (dup_cols) := NULL]
  }
  
  return(y)
}

# ============================================
# CORE: READ ONE QUARTER
# ============================================
read_enoe_quarter <- function(path_quarter) {
  
  files <- list.files(path_quarter, full.names = TRUE)
  files_low <- tolower(basename(files))
  
  sdem <- files[str_detect(files_low, "sdem")]
  coe1 <- files[str_detect(files_low, "coe1")]
  coe2 <- files[str_detect(files_low, "coe2")]
  hogar <- files[str_detect(files_low, "hog")]
  viv <- files[str_detect(files_low, "viv")]
  
  if (length(sdem) == 0) stop("Missing SDEM in: ", path_quarter)
  if (length(coe1) == 0) stop("Missing COE1 in: ", path_quarter)
  if (length(coe2) == 0) stop("Missing COE2 in: ", path_quarter)
  if (length(hogar) == 0) stop("Missing HOG in: ", path_quarter)
  if (length(viv) == 0) stop("Missing VIV in: ", path_quarter)
  
  sdem <- as.data.table(read_dta(sdem))
  coe1 <- as.data.table(read_dta(coe1))
  coe2 <- as.data.table(read_dta(coe2))
  hogar <- as.data.table(read_dta(hogar))
  viv <- as.data.table(read_dta(viv))
  
  setnames(sdem, tolower(names(sdem)))
  setnames(coe1, tolower(names(coe1)))
  setnames(coe2, tolower(names(coe2)))
  setnames(hogar, tolower(names(hogar)))
  setnames(viv, tolower(names(viv)))
  
  normalize_ent <- function(dt) {
    if ("cve_ent" %in% names(dt) & !"ent" %in% names(dt)) {
      setnames(dt, "cve_ent", "ent")
    }
  }
  
  normalize_ent(sdem)
  normalize_ent(coe1)
  normalize_ent(coe2)
  normalize_ent(hogar)
  normalize_ent(viv)
  
  key_per <- c("cd_a","ent","con","v_sel","n_hog","h_mud","n_ren")
  key_hog <- key_per[1:6]
  key_viv <- key_per[1:4]
  
  sdem <- unique(sdem, by = key_per)
  coe1 <- unique(coe1, by = key_per)
  coe2 <- unique(coe2, by = key_per)
  hogar <- unique(hogar, by = key_hog)
  viv <- unique(viv, by = key_viv)
  
  coe1 <- clean_for_merge(sdem, coe1, key_per)
  base <- merge(sdem, coe1, by = key_per, all.x = TRUE)
  
  coe2 <- clean_for_merge(base, coe2, key_per)
  base <- merge(base, coe2, by = key_per, all.x = TRUE)
  
  hogar <- clean_for_merge(base, hogar, key_hog)
  base <- merge(base, hogar, by = key_hog, all.x = TRUE)
  
  viv <- clean_for_merge(base, viv, key_viv)
  base <- merge(base, viv, by = key_viv, all.x = TRUE)
  
  return(base)
}

# ============================================
# FOLDER NAME BUILDER
# ============================================
get_folder_name <- function(year, quarter) {
  
  if (year < 2020 | (year == 2020 & quarter <= 2)) {
    paste0(year, "trim", quarter, "_dta")
    
  } else if (year <= 2022) {
    paste0("enoe_n_", year, "_trim", quarter, "_dta")
    
  } else {
    paste0("enoe_", year, "_trim", quarter, "_dta")
  }
}

# ============================================
# PROCESS ONE QUARTER
# ============================================
panel_trimestre <- function(base_path, year, quarter) {
  
  folder <- file.path(base_path, get_folder_name(year, quarter))
  
  if (!dir.exists(folder)) {
    stop("Folder not found: ", folder)
  }
  
  dt <- read_enoe_quarter(folder)
  
  dt[, year := year]
  dt[, quarter := quarter]
  
  return(dt)
}

# ============================================
# PROCESS ONE YEAR (SAFE MEMORY VERSION)
# ============================================
panel_anual <- function(base_path, year, output_dir = NULL) {
  
  if (!is.null(output_dir)) {
    if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)
  }
  
  base_final <- NULL
  
  for (q in 1:4) {
    
    cat("Processing:", year, "Q", q, "\n")
    
    temp <- panel_trimestre(base_path, year, q)
    
    temp[, (names(temp)) := lapply(.SD, as.character)]
    
    if (!is.null(output_dir)) {
      saveRDS(temp, file.path(output_dir, paste0("enoe_", year, "_Q", q, ".rds")))
    }
    
    if (is.null(base_final)) {
      base_final <- temp
    } else {
      base_final <- rbindlist(list(base_final, temp), fill = TRUE)
    }
    
    rm(temp)
    gc()
  }
  
  return(base_final)
}

# ============================================
# PROCESS FULL RANGE (SAVE ONLY, NO RAM)
# ============================================
panel_completo <- function(base_path, start_year, end_year, output_dir) {
  
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }
  
  for (y in start_year:end_year) {
    for (q in 1:4) {
      
      cat("Processing:", y, "Q", q, "\n")
      
      temp <- panel_trimestre(base_path, y, q)
      
      saveRDS(
        temp,
        file.path(output_dir, paste0("enoe_", y, "_Q", q, ".rds"))
      )
      
      rm(temp)
      gc()
    }
  }
  
  cat("✔ Full dataset saved in:", output_dir, "\n")
}

# ============================================
# EXECUTION 
# ============================================

# --- Single quarter (EXAMPLE)
t4_2009 <- panel_trimestre("E:/ENOEr/ENOE 2005-2025", 2009(), 4) # (2009 =YEAR, 4=QUARTER)
#PLASE ONLY CHANCE THE OBJECT NAME ##
