library(data.table)

qc_standard_life_table_abridged <- function(dt) {
  x <- as.data.table(copy(dt))
  out <- list()
  
  out$ex_negative <- x[ex < 0]
  out$bad_age_order <- x[age_end <= age_start]
  out$bad_age_width <- x[age_interval_width <= 0]
  out$units_not_years <- x[units != "years"]
  
  # Monotonicidad solo en versiones donde corresponde
  monotone_versions <- c("2010", "GHE", "1990_no_weights_no_discount")
  
  out$ex_not_monotone_expected <- x[
    standard_version %in% monotone_versions
  ][
    order(age_start),
    .(age_start, age_end, ex, ex_prev = shift(ex), flag = ex > shift(ex)),
    by = .(standard_source, standard_version, sex_id)
  ][flag == TRUE]
  
  out$duplicate_pk <- unique(
    x[, .N, by = .(standard_source, standard_version, sex_id, age_start)][N > 1]
  )
  
  out
}

qc_standard_life_table_single_age <- function(dt,
                                              terminal_age = 110L,
                                              terminal_ex_tol = 1e-8,
                                              monotone_versions = c("2010", "GHE", "1990_no_weights_no_discount")) {
  x <- as.data.table(copy(dt))
  out <- list()
  
  out$ex_negative <- x[ex < 0]
  out$bad_age_order <- x[age_end <= age_start]
  out$bad_age_width <- x[age_interval_width != 1L]
  out$units_not_years <- x[units != "years"]
  
  out$duplicate_pk <- unique(
    x[, .N, by = .(standard_source, standard_version, sex_id, exact_age)][N > 1]
  )
  
  out$open_interval_count_bad <- x[
    ,
    .(n_open = sum(age_interval_open, na.rm = TRUE)),
    by = .(standard_source, standard_version, sex_id)
  ][n_open != 1L]
  
  out$open_interval_bad_age <- x[age_interval_open == TRUE & exact_age != terminal_age]
  
  out$terminal_label_bad <- x[
    exact_age == terminal_age & age_group_label != paste0(terminal_age, "+")
  ]
  
  out$age_start_not_exact_age <- x[age_start != exact_age]
  out$age_end_not_plus_one <- x[exact_age < terminal_age & age_end != exact_age + 1L]
  out$open_age_end_bad <- x[exact_age == terminal_age & age_end != terminal_age + 1L]
  
  # Monotonicidad solo donde corresponde
  out$ex_not_monotone_expected <- x[
    standard_version %in% monotone_versions
  ][
    order(exact_age),
    .(exact_age, ex, ex_prev = shift(ex), flag = ex > shift(ex)),
    by = .(standard_source, standard_version, sex_id)
  ][flag == TRUE]
  
  out$terminal_ex_nonpositive <- x[
    standard_version %in% monotone_versions &
      exact_age == terminal_age &
      ex <= terminal_ex_tol
  ]
  
  out
}

qc_standard_knot_preservation_single_age <- function(dt_single, dt_abridged) {
  x <- as.data.table(copy(dt_single))
  a <- as.data.table(copy(dt_abridged))
  
  a <- a[
    abs(age_start - round(age_start)) < 1e-8,
    .(
      standard_source,
      standard_version,
      sex_id,
      sex_source_value,
      exact_age = as.integer(round(age_start)),
      ex_abridged = ex
    )
  ]
  
  x2 <- x[, .(
    standard_source,
    standard_version,
    sex_id,
    sex_source_value,
    exact_age,
    ex_expanded = ex
  )]
  
  out <- merge(
    a,
    x2,
    by = c("standard_source", "standard_version", "sex_id", "sex_source_value", "exact_age"),
    all.x = TRUE
  )
  
  out[
    is.na(ex_expanded) | abs(ex_abridged - ex_expanded) > 1e-8
  ]
}

write_qc_list <- function(qc_list, qc_dir, prefix = "qc") {
  dir.create(qc_dir, recursive = TRUE, showWarnings = FALSE)
  files <- character()
  
  for (nm in names(qc_list)) {
    fp <- file.path(qc_dir, paste0(prefix, "_", nm, ".csv"))
    fwrite(as.data.table(qc_list[[nm]]), fp)
    files <- c(files, fp)
  }
  
  invisible(files)
}

summarise_standard_terminal_interval <- function(dt_single,
                                                 dt_abridged,
                                                 terminal_age = 110L,
                                                 support_age_max = NA_integer_,
                                                 monotone_versions = c("2010", "GHE", "1990_no_weights_no_discount")) {
  x <- as.data.table(copy(dt_single))
  a <- as.data.table(copy(dt_abridged))

  abr_open <- a[
    age_interval_open == TRUE,
    .(
      standard_source,
      standard_version,
      sex_id,
      sex_source_value,
      open_age_source = as.numeric(age_start),
      open_age_end_source = as.numeric(age_end),
      open_age_label_source = as.character(age_group_label),
      ex_open_source = as.numeric(ex)
    )
  ]

  single_summary <- x[
    ,
    .(
      min_exact_age = min(exact_age, na.rm = TRUE),
      max_exact_age = max(exact_age, na.rm = TRUE),
      n_open = sum(age_interval_open, na.rm = TRUE),
      terminal_age_export = terminal_age,
      terminal_open_flag = age_interval_open[exact_age == terminal_age][1],
      terminal_label_export = age_group_label[exact_age == terminal_age][1],
      ex_85 = ex[exact_age == 85L][1],
      ex_109 = ex[exact_age == (terminal_age - 1L)][1],
      ex_110plus = ex[exact_age == terminal_age][1],
      monotone_full = all(diff(ex) <= 1e-8),
      monotone_expected = standard_version[1] %in% monotone_versions,
      terminal_policy_current = fifelse(ex[exact_age == terminal_age][1] > 1e-8, "positive_open_ex", "nonpositive_open_ex")
    ),
    by = .(standard_source, standard_version, sex_id, sex_source_value)
  ]

  out <- merge(
    single_summary,
    abr_open,
    by = c("standard_source", "standard_version", "sex_id", "sex_source_value"),
    all.x = TRUE
  )

  out[, contract_v2_impact := fifelse(
    terminal_policy_current == "positive_open_ex",
    "current_contract_positive_open_ex",
    "terminal_policy_incoherent"
  )]

  if (!is.na(support_age_max)) {
    out[, support_age_max := as.integer(support_age_max)]
  }

  out[]
}

qc_standard_terminal_interval <- function(summary_dt,
                                          terminal_age = 110L,
                                          expect_positive_open_ex = TRUE) {
  x <- as.data.table(copy(summary_dt))

  out <- list()

  out$open_interval_count_bad <- x[n_open != 1L]

  out$terminal_structure_bad <- x[
    max_exact_age != terminal_age |
      is.na(terminal_open_flag) |
      terminal_open_flag != TRUE |
      is.na(terminal_label_export) |
      terminal_label_export != paste0(terminal_age, "+")
  ]

  out$source_open_interval_missing <- x[is.na(open_age_source)]

  out$source_open_age_not_before_terminal <- x[
    !is.na(open_age_source) & open_age_source >= terminal_age
  ]

  out$monotone_expected_bad <- x[
    monotone_expected == TRUE & monotone_full == FALSE
  ]

  out$terminal_open_ex_nonpositive <- x[ex_110plus <= 1e-8]
  out$terminal_policy_mismatch <- if (expect_positive_open_ex) x[terminal_policy_current != "positive_open_ex"] else x[0]

  out$terminal_value_incoherent <- x[
    ex_109 < 0 |
      ex_110plus < 0 |
      (!is.na(ex_109) & !is.na(ex_110plus) & ex_110plus > ex_109 + 1e-8)
  ]

  out
}
