#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(data.table)
  library(here)
})

source(here("R", "io_utils.R"))
source(here("R", "catalog_utils.R"))
source(here("R", "spec_utils.R"))
source(here("R", "standard_life_table_tail_utils.R"))

DATASET_ID <- "life_table_standard_reference_single_age"
VERSION <- "v2.0.0"
TABLE_NAME <- "life_table_standard_single_age_result"
TERMINAL_AGE <- 110L
SUPPORT_AGE_MAX <- 125L
TAIL_START_AGE <- 85L

run_id <- paste0("build_single_age_", format(Sys.time(), "%Y%m%d_%H%M%S"))
register_run_start(run_id = run_id, dataset_id = DATASET_ID, version = VERSION)

fail_run <- function(e) {
  register_run_finish(run_id, status = "failed", message = conditionMessage(e))
  stop(e)
}

tryCatch({
  p <- ensure_standard_life_table_dirs()
  spec <- read_spec(file.path(p$CONFIG_DIR, "spec_life_table_standard_single_age.yml"))
  in_csv <- file.path(p$STAGING_DIR, "life_table_standard_abridged.csv")
  if (!file.exists(in_csv)) stop("No se encontro el staging abridged en: ", in_csv)

  abridged <- fread(in_csv, encoding = "UTF-8")
  setDT(abridged)
  abridged[, `:=`(
    standard_source = trimws(as.character(standard_source)),
    standard_version = trimws(as.character(standard_version)),
    sex_id = as.integer(sex_id),
    sex_source_value = trimws(as.character(sex_source_value)),
    age_start = as.numeric(age_start),
    age_end = as.numeric(age_end),
    age_interval_width = as.numeric(age_interval_width),
    age_interval_open = as.logical(age_interval_open),
    age_group_label = trimws(as.character(age_group_label)),
    ex = as.numeric(ex),
    units = trimws(as.character(units))
  )]

  group_cols <- c("standard_source", "standard_version", "sex_id", "sex_source_value")
  strata <- unique(abridged[, ..group_cols])
  setorderv(strata, group_cols)

  contract_parts <- vector("list", nrow(strata))
  exspace_parts <- vector("list", nrow(strata))
  law_support_parts <- vector("list", nrow(strata))
  method_metrics_parts <- vector("list", nrow(strata))
  selected_parts <- vector("list", nrow(strata))
  comparison_parts <- vector("list", nrow(strata))

  for (i in seq_len(nrow(strata))) {
    ss <- strata$standard_source[i]
    sv <- strata$standard_version[i]
    sid <- strata$sex_id[i]
    ssv <- strata$sex_source_value[i]
    monotone_expected <- sv %in% MONOTONE_STANDARD_VERSIONS

    abr_one <- abridged[
      standard_source == ss &
        standard_version == sv &
        sex_id == sid &
        sex_source_value == ssv
    ]

    knots <- build_integer_knots(abr_one)
    if (!(0L %in% knots$age_start)) stop("No existe knot en edad 0 para ", ss, " / ", sv, " / ", ssv)
    if (!(1L %in% knots$age_start)) stop("No existe knot en edad 1 para ", ss, " / ", sv, " / ", ssv)
    if (!(TAIL_START_AGE %in% knots$age_start)) stop("No existe knot abierto en edad 85 para ", ss, " / ", sv, " / ", ssv)

    base_exact <- expand_segmented_between_knots(knots[age_start <= TAIL_START_AGE], age_max = TAIL_START_AGE, add_terminal_zero = FALSE)
    first_dec <- base_exact[exact_age == 84L, ex][1] - base_exact[exact_age == TAIL_START_AGE, ex][1]

    ex_candidates <- list(
      baseline_repo = build_repo_tail(ex_85 = base_exact[exact_age == TAIL_START_AGE, ex][1], tail_start_age = TAIL_START_AGE, support_age_max = SUPPORT_AGE_MAX),
      polynomial_delta = build_polynomial_delta_tail(ex_85 = base_exact[exact_age == TAIL_START_AGE, ex][1], first_dec = first_dec, tail_start_age = TAIL_START_AGE, support_age_max = SUPPORT_AGE_MAX)
    )

    kannisto_tail <- calibrate_tail_by_law(base_exact, law = "kannisto", tail_start_age = TAIL_START_AGE, support_age_max = SUPPORT_AGE_MAX)[, .(exact_age, ex, law, slope_param, intercept_param)]
    ck_tail <- calibrate_tail_by_law(base_exact, law = "coale_kisker_like", tail_start_age = TAIL_START_AGE, support_age_max = SUPPORT_AGE_MAX)[, .(exact_age, ex, law, slope_param, intercept_param)]
    law_candidates <- list(
      kannisto = kannisto_tail,
      kannisto_blend95 = blend_law_tail_with_hermite(base_exact, kannisto_tail, tail_start_age = TAIL_START_AGE, blend_end_age = 95L),
      kannisto_anchor_bridge = merge(
        build_decay_bridge_tail(
          ex_85 = base_exact[exact_age == TAIL_START_AGE, ex][1],
          first_drop = first_dec,
          ex_terminal_target = build_export_from_internal(base_exact, kannisto_tail[, .(exact_age, ex)], terminal_age = TERMINAL_AGE)[exact_age == TERMINAL_AGE, ex][1],
          ex_support_target = kannisto_tail[exact_age == SUPPORT_AGE_MAX, ex][1],
          tail_start_age = TAIL_START_AGE,
          terminal_age = TERMINAL_AGE,
          support_age_max = SUPPORT_AGE_MAX
        ),
        kannisto_tail[, .(exact_age, law, slope_param, intercept_param)],
        by = "exact_age",
        all.x = TRUE
      ),
      coale_kisker_like = ck_tail,
      coale_kisker_like_blend95 = blend_law_tail_with_hermite(base_exact, ck_tail, tail_start_age = TAIL_START_AGE, blend_end_age = 95L),
      coale_kisker_like_anchor_bridge = merge(
        build_decay_bridge_tail(
          ex_85 = base_exact[exact_age == TAIL_START_AGE, ex][1],
          first_drop = first_dec,
          ex_terminal_target = build_export_from_internal(base_exact, ck_tail[, .(exact_age, ex)], terminal_age = TERMINAL_AGE)[exact_age == TERMINAL_AGE, ex][1],
          ex_support_target = ck_tail[exact_age == SUPPORT_AGE_MAX, ex][1],
          tail_start_age = TAIL_START_AGE,
          terminal_age = TERMINAL_AGE,
          support_age_max = SUPPORT_AGE_MAX
        ),
        ck_tail[, .(exact_age, law, slope_param, intercept_param)],
        by = "exact_age",
        all.x = TRUE
      )
    )

    ex_metrics <- rbindlist(lapply(names(ex_candidates), function(method) {
      export <- build_export_from_internal(base_exact, ex_candidates[[method]], terminal_age = TERMINAL_AGE)
      summarise_tail_metrics(ex_candidates[[method]], export, base_exact, family = "ex_space", method = method, monotone_expected = monotone_expected)
    }), fill = TRUE)

    law_metrics <- rbindlist(lapply(names(law_candidates), function(method) {
      export <- build_export_from_internal(base_exact, law_candidates[[method]][, .(exact_age, ex)], terminal_age = TERMINAL_AGE)
      summarise_tail_metrics(law_candidates[[method]][, .(exact_age, ex)], export, base_exact, family = "law_based", method = method, monotone_expected = monotone_expected)
    }), fill = TRUE)

    metrics <- rbind(ex_metrics, law_metrics, fill = TRUE)
    metrics[, `:=`(standard_source = ss, standard_version = sv, sex_id = sid, sex_source_value = ssv, monotone_expected = monotone_expected)]

    ex_winner <- metrics[family == "ex_space"][order(score, jump_84_85, curvature_84_95)][1]
    law_winner <- metrics[family == "law_based"][order(score, jump_84_85, curvature_84_95)][1]

    ex_internal <- ex_candidates[[ex_winner$method]]
    law_internal <- law_candidates[[law_winner$method]][, .(exact_age, ex)]
    ex_export <- build_export_from_internal(base_exact, ex_internal, terminal_age = TERMINAL_AGE)
    final_export <- build_export_from_internal(base_exact, law_internal, terminal_age = TERMINAL_AGE)

    final_with_keys <- cbind(data.table(
      standard_source = ss,
      standard_version = sv,
      sex_id = sid,
      sex_source_value = ssv
    )[rep(1L, nrow(final_export))], final_export)

    ex_with_keys <- cbind(data.table(
      standard_source = ss,
      standard_version = sv,
      sex_id = sid,
      sex_source_value = ssv,
      family = "ex_space",
      selected_method = ex_winner$method
    )[rep(1L, nrow(ex_internal))], ex_internal)

    law_with_keys <- cbind(data.table(
      standard_source = ss,
      standard_version = sv,
      sex_id = sid,
      sex_source_value = ssv,
      family = "law_based",
      selected_method = law_winner$method
    )[rep(1L, nrow(law_candidates[[law_winner$method]]))], law_candidates[[law_winner$method]])

    comp <- merge(
      final_export[, .(exact_age, ex_final = ex)],
      ex_export[, .(exact_age, ex_ex_space = ex)],
      by = "exact_age",
      all = TRUE
    )
    comp[, `:=`(
      standard_source = ss,
      standard_version = sv,
      sex_id = sid,
      sex_source_value = ssv,
      final_minus_ex_space = ex_final - ex_ex_space
    )]

    selected_parts[[i]] <- rbind(
      data.table(
        standard_source = ss,
        standard_version = sv,
        sex_id = sid,
        sex_source_value = ssv,
        family = "ex_space",
        selected_method = ex_winner$method,
        ex_110plus = ex_winner$ex_110plus,
        jump_84_85 = ex_winner$jump_84_85,
        rebound_ratio_95 = ex_winner$rebound_ratio_95,
        delta_pattern = ex_winner$delta_pattern,
        score = ex_winner$score
      ),
      data.table(
        standard_source = ss,
        standard_version = sv,
        sex_id = sid,
        sex_source_value = ssv,
        family = "law_based",
        selected_method = law_winner$method,
        ex_110plus = law_winner$ex_110plus,
        jump_84_85 = law_winner$jump_84_85,
        rebound_ratio_95 = law_winner$rebound_ratio_95,
        delta_pattern = law_winner$delta_pattern,
        score = law_winner$score
      ),
      fill = TRUE
    )

    contract_parts[[i]] <- final_with_keys
    exspace_parts[[i]] <- ex_with_keys
    law_support_parts[[i]] <- law_with_keys
    method_metrics_parts[[i]] <- metrics
    comparison_parts[[i]] <- comp
  }

  contract_dt <- rbindlist(contract_parts, use.names = TRUE, fill = TRUE)
  exspace_support <- rbindlist(exspace_parts, use.names = TRUE, fill = TRUE)
  law_support <- rbindlist(law_support_parts, use.names = TRUE, fill = TRUE)
  method_metrics <- rbindlist(method_metrics_parts, use.names = TRUE, fill = TRUE)
  selected_methods <- rbindlist(selected_parts, use.names = TRUE, fill = TRUE)
  compare_dt <- rbindlist(comparison_parts, use.names = TRUE, fill = TRUE)

  setorderv(contract_dt, c("standard_source", "standard_version", "sex_id", "exact_age"))
  validate_by_spec(contract_dt, spec)

  chk_n <- contract_dt[, .N, by = group_cols]
  if (chk_n[, any(N != (TERMINAL_AGE + 1L))]) stop("Cada estrato debe tener exactamente 111 registros exportados.")
  chk_open <- contract_dt[, .(n_open = sum(age_interval_open, na.rm = TRUE)), by = group_cols]
  if (chk_open[, any(n_open != 1L)]) stop("Cada estrato debe tener exactamente un intervalo abierto final.")
  chk_positive_open <- contract_dt[exact_age == TERMINAL_AGE, any(ex <= 1e-8)]
  if (isTRUE(chk_positive_open)) stop("El nuevo contrato exige ex(110+) positivo.")

  chk_monotone <- contract_dt[
    standard_version %in% MONOTONE_STANDARD_VERSIONS,
    .(ok = all(diff(ex) <= 1e-8)),
    by = group_cols
  ]
  if (nrow(chk_monotone) > 0L && chk_monotone[, any(!ok)]) {
    print(chk_monotone[ok == FALSE])
    stop("La salida final no es monotona donde conceptualmente deberia serlo.")
  }

  out_csv <- file.path(p$STAGING_DIR, "life_table_standard_single_age.csv")
  fwrite(contract_dt, out_csv, na = "")
  register_artifact(
    dataset_id = DATASET_ID,
    table_name = TABLE_NAME,
    version = VERSION,
    run_id = run_id,
    artifact_type = "staging",
    artifact_path = out_csv,
    n_rows = nrow(contract_dt),
    n_cols = ncol(contract_dt),
    notes = "Tabla de vida estandar single-age final con 110+ abierto y ex(110+) derivado desde cola interna hasta 125."
  )

  write_qc <- function(dt, name) {
    fp <- file.path(p$QC_DIR, name)
    fwrite(dt, fp)
    register_artifact(
      dataset_id = DATASET_ID,
      table_name = TABLE_NAME,
      version = VERSION,
      run_id = run_id,
      artifact_type = "qc",
      artifact_path = fp,
      n_rows = nrow(dt),
      n_cols = ncol(dt),
      notes = "Artefacto QC/metodologico de comparacion de cola terminal."
    )
  }

  qc_behavior <- qc_tail_behavior(method_metrics)
  write_qc(method_metrics, "single_age_tail_method_detail.csv")
  write_qc(selected_methods, "single_age_tail_selected_methods.csv")
  write_qc(compare_dt, "single_age_tail_final_vs_exspace.csv")
  write_qc(exspace_support, "single_age_tail_support_ex_space_to_125.csv")
  write_qc(law_support, "single_age_tail_support_law_to_125.csv")
  decision_matrix <- selected_methods[, .(
    standard_source, standard_version, sex_id, sex_source_value, family,
    selected_method, ex_110plus, jump_84_85, rebound_ratio_95, delta_pattern, score
  )]
  method_summary <- method_metrics[, .(
    n_strata = .N,
    median_jump_84_85 = median(jump_84_85, na.rm = TRUE),
    median_curvature_84_95 = median(curvature_84_95, na.rm = TRUE),
    median_rebound_ratio_95 = median(rebound_ratio_95, na.rm = TRUE),
    median_ex_110plus = median(ex_110plus, na.rm = TRUE)
  ), by = .(family, method)]

  write_qc(decision_matrix, "single_age_tail_decision_matrix.csv")
  write_qc(method_summary, "single_age_tail_method_summary.csv")
  for (nm in names(qc_behavior)) write_qc(qc_behavior[[nm]], paste0("qc_single_age_tail_", nm, ".csv"))

  # Compatibilidad con lectores previos del portal durante la migracion a la version final limpia.
  write_qc(method_metrics, "tail_smoothing_method_summary.csv")
  write_qc(method_summary, "tail_smoothing_method_comparison_summary.csv")
  write_qc(selected_methods, "tail_smoothing_selected_parameters.csv")

  register_run_finish(run_id, status = "success")
  message("Single-age final construida: ", out_csv)
}, error = fail_run)
