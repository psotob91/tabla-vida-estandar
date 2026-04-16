library(data.table)

MONOTONE_STANDARD_VERSIONS <- c("2010", "GHE", "1990_no_weights_no_discount")

build_integer_knots <- function(dt_one) {
  x <- copy(as.data.table(dt_one))
  x <- x[abs(age_start - round(age_start)) < 1e-8]
  x[, age_start := as.integer(round(age_start))]
  x <- unique(x[, .(age_start, ex)], by = "age_start")
  setorder(x, age_start)
  x
}

expand_segmented_between_knots <- function(dt_knots, age_max, k = 0.25, add_terminal_zero = FALSE) {
  knots <- copy(as.data.table(dt_knots))
  setorder(knots, age_start)

  if (add_terminal_zero && !(age_max %in% knots$age_start)) {
    knots <- rbind(knots, data.table(age_start = age_max, ex = 0), use.names = TRUE)
    setorder(knots, age_start)
  }

  knots <- knots[age_start <= age_max]
  if (!(age_max %in% knots$age_start)) {
    stop("No existe knot en la edad maxima solicitada: ", age_max)
  }

  parts <- vector("list", max(0L, nrow(knots) - 1L))
  for (i in seq_len(nrow(knots) - 1L)) {
    a <- knots$age_start[i]
    b <- knots$age_start[i + 1L]
    ex_a <- knots$ex[i]
    ex_b <- knots$ex[i + 1L]
    n_steps <- as.integer(b - a)
    if (n_steps <= 0L) stop("Los knots no estan estrictamente ordenados.")

    delta <- ex_a - ex_b
    if (n_steps == 1L) {
      dec <- delta
    } else {
      t_rel <- seq(0, 1, length.out = n_steps)
      w <- exp(k * t_rel)
      dec <- delta * (w / sum(w))
    }

    ex_vals <- numeric(n_steps + 1L)
    ex_vals[1] <- ex_a
    for (j in seq_len(n_steps)) ex_vals[j + 1L] <- ex_vals[j] - dec[j]
    ex_vals[length(ex_vals)] <- ex_b

    ages <- a:(b - 1L)
    parts[[i]] <- data.table(exact_age = ages, ex = ex_vals[seq_along(ages)])
  }

  out <- rbindlist(c(parts, list(data.table(exact_age = age_max, ex = knots[age_start == age_max, ex][1]))), use.names = TRUE)
  setorder(out, exact_age)
  out[, ex := pmax(0, ex)]
  out[]
}

infer_latent_q_from_ex <- function(dt_exact, min_age = 70L, max_age = 84L, ax = 0.5) {
  x <- copy(dt_exact[exact_age >= min_age & exact_age <= max_age + 1L, .(exact_age, ex)])
  setorder(x, exact_age)
  x[, ex_next := shift(ex, type = "lead")]
  x <- x[exact_age <= max_age]
  x[, p_latent := (ex - ax) / (ex_next + (1 - ax))]
  x[, p_latent := pmin(pmax(p_latent, 1e-8), 0.999999)]
  x[, q_latent := 1 - p_latent]
  x[, m_latent := q_latent / pmax(1 - ax * q_latent, 1e-8)]
  x[, logit_q := qlogis(pmin(pmax(q_latent, 1e-8), 1 - 1e-8))]
  x[, log_m := log(pmax(m_latent, 1e-8))]
  x[]
}

fit_linear_slope <- function(x, y) {
  if (length(x) < 2L || all(is.na(y))) return(0.08)
  fit <- tryCatch(stats::lm(y ~ x), error = function(e) NULL)
  if (is.null(fit)) return(0.08)
  slope <- as.numeric(stats::coef(fit)[2])
  if (!is.finite(slope) || slope <= 0) slope <- 0.08
  slope
}

compute_ex_from_q_schedule <- function(q_tail, start_age, support_age_max, ax = 0.5) {
  ages <- start_age:support_age_max
  q_tail <- pmin(pmax(q_tail, 1e-8), 0.999999)
  m_tail <- q_tail / pmax(1 - ax * q_tail, 1e-8)
  ex_vals <- numeric(length(ages))
  ex_vals[length(ages)] <- max(0, (1 / m_tail[length(ages)]) - ax)
  if (length(ages) > 1L) {
    for (i in seq(length(ages) - 1L, 1L)) {
      p <- 1 - q_tail[i]
      ex_vals[i] <- ax + p * (ex_vals[i + 1L] + (1 - ax))
    }
  }
  data.table(exact_age = ages, ex = pmax(0, ex_vals), q_latent = q_tail, m_latent = m_tail)
}

calibrate_tail_by_law <- function(dt_exact,
                                  law = c("kannisto", "coale_kisker_like"),
                                  tail_start_age = 85L,
                                  support_age_max = 125L) {
  law <- match.arg(law)
  latent <- infer_latent_q_from_ex(dt_exact, max_age = tail_start_age - 1L)
  ex_target <- dt_exact[exact_age == tail_start_age, ex][1]
  ages_tail <- tail_start_age:support_age_max
  slope <- if (law == "kannisto") fit_linear_slope(latent$exact_age, latent$logit_q) else fit_linear_slope(latent$exact_age, latent$log_m)

  eval_ex <- function(intercept) {
    if (law == "kannisto") {
      q_tail <- plogis(intercept + slope * ages_tail)
    } else {
      m_tail <- exp(intercept + slope * ages_tail)
      q_tail <- m_tail / (1 + 0.5 * m_tail)
    }
    compute_ex_from_q_schedule(q_tail, tail_start_age, support_age_max)$ex[1]
  }

  objective <- function(intercept) eval_ex(intercept) - ex_target
  grid <- seq(-20, 10, by = 0.25)
  vals <- vapply(grid, objective, numeric(1))
  bracket_idx <- which(vals[-length(vals)] * vals[-1L] <= 0)
  intercept <- if (length(bracket_idx) > 0L) {
    stats::uniroot(objective, lower = grid[bracket_idx[1]], upper = grid[bracket_idx[1] + 1L], tol = 1e-12)$root
  } else {
    grid[which.min(abs(vals))]
  }

  if (law == "kannisto") {
    q_tail <- plogis(intercept + slope * ages_tail)
  } else {
    m_tail <- exp(intercept + slope * ages_tail)
    q_tail <- m_tail / (1 + 0.5 * m_tail)
  }

  tail <- compute_ex_from_q_schedule(q_tail, tail_start_age, support_age_max)
  tail[, `:=`(law = law, slope_param = slope, intercept_param = intercept)]
  tail[]
}

blend_law_tail_with_hermite <- function(base_exact,
                                        law_tail,
                                        tail_start_age = 85L,
                                        blend_end_age = 95L) {
  law_tail <- copy(as.data.table(law_tail))
  setorder(law_tail, exact_age)
  blend_end_age <- min(as.integer(blend_end_age), max(law_tail$exact_age))
  if (blend_end_age <= tail_start_age + 1L) return(law_tail)

  y0 <- base_exact[exact_age == tail_start_age, ex][1]
  y_prev <- base_exact[exact_age == (tail_start_age - 1L), ex][1]
  if (!is.finite(y0) || !is.finite(y_prev)) return(law_tail)
  first_drop <- y_prev - y0

  y1 <- law_tail[exact_age == blend_end_age, ex][1]
  if (!is.finite(y1)) return(law_tail)

  n <- blend_end_age - tail_start_age
  total_drop <- y0 - y1
  if (!is.finite(total_drop) || total_drop <= 0 || !is.finite(first_drop) || first_drop <= 0) return(law_tail)

  solve_lambda <- function(first_drop, total_drop, n) {
    if (abs(total_drop - n * first_drop) < 1e-8) return(0)
    f <- function(lambda) sum(first_drop * exp(-lambda * (0:(n - 1L)))) - total_drop
    if (f(0) < 0) return(0)
    upper <- 0.25
    while (f(upper) > 0 && upper < 100) upper <- upper * 2
    if (upper >= 100 && f(upper) > 0) return(0)
    uniroot(f, lower = 0, upper = upper, tol = 1e-12)$root
  }

  lambda <- solve_lambda(first_drop, total_drop, n)
  dec <- first_drop * exp(-lambda * (0:(n - 1L)))
  bridge_ages <- tail_start_age:blend_end_age
  bridge_ex <- c(y0, y0 - cumsum(dec))
  bridge_ex[length(bridge_ex)] <- y1
  bridge_dt <- data.table(exact_age = bridge_ages, ex = bridge_ex)

  out <- rbind(
    bridge_dt,
    law_tail[exact_age > blend_end_age],
    use.names = TRUE,
    fill = TRUE
  )
  setorder(out, exact_age)
  if ("law" %in% names(law_tail)) out <- merge(out, law_tail[, setdiff(names(law_tail), "ex"), with = FALSE], by = "exact_age", all.x = TRUE)
  out[]
}

solve_poly_gamma <- function(sum_target, first_dec, n_steps) {
  first_dec <- max(first_dec, 1e-8)
  if (n_steps <= 1L) return(1)
  grid <- seq(0.05, 20, by = 0.01)
  sums <- vapply(grid, function(g) sum(first_dec * ((n_steps:1) / n_steps)^g), numeric(1))
  grid[which.min(abs(sums - sum_target))]
}

build_polynomial_delta_tail <- function(ex_85, first_dec, tail_start_age = 85L, support_age_max = 125L) {
  n_steps <- as.integer(support_age_max - tail_start_age)
  ages <- tail_start_age:support_age_max
  if (n_steps <= 0L) return(data.table(exact_age = ages, ex = ex_85))
  gamma <- solve_poly_gamma(ex_85, first_dec, n_steps)
  dec <- first_dec * ((n_steps:1) / n_steps)^gamma
  ex_vals <- c(ex_85, ex_85 - cumsum(dec))
  ex_vals[length(ex_vals)] <- 0
  data.table(exact_age = ages, ex = pmax(0, ex_vals))
}

build_repo_tail <- function(ex_85, tail_start_age = 85L, support_age_max = 125L, k = 0.25) {
  n_steps <- as.integer(support_age_max - tail_start_age)
  ages <- tail_start_age:support_age_max
  if (n_steps <= 0L) return(data.table(exact_age = ages, ex = ex_85))
  w <- exp(k * seq(0, 1, length.out = n_steps))
  dec <- ex_85 * (w / sum(w))
  ex_vals <- c(ex_85, ex_85 - cumsum(dec))
  ex_vals[length(ex_vals)] <- 0
  data.table(exact_age = ages, ex = pmax(0, ex_vals))
}

build_decay_bridge_tail <- function(ex_85,
                                    first_drop,
                                    ex_terminal_target,
                                    ex_support_target,
                                    tail_start_age = 85L,
                                    terminal_age = 110L,
                                    support_age_max = 125L) {
  solve_lambda <- function(first_drop, total_drop, n) {
    if (n <= 0L) return(0)
    first_drop <- max(first_drop, 1e-8)
    total_drop <- max(total_drop, first_drop + 1e-8)
    f <- function(lambda) sum(first_drop * exp(-lambda * (0:(n - 1L)))) - total_drop
    if (f(0) < 0) return(0)
    if (abs(f(0)) < 1e-10) return(0)
    upper <- 0.25
    while (f(upper) > 0 && upper < 100) upper <- upper * 2
    if (upper >= 100 && f(upper) > 0) return(0)
    uniroot(f, lower = 0, upper = upper, tol = 1e-12)$root
  }

  n1 <- terminal_age - tail_start_age
  total_drop1 <- ex_85 - ex_terminal_target
  lambda1 <- solve_lambda(first_drop, total_drop1, n1)
  dec1 <- first_drop * exp(-lambda1 * (0:(n1 - 1L)))
  ages1 <- tail_start_age:terminal_age
  ex1 <- c(ex_85, ex_85 - cumsum(dec1))
  ex1[length(ex1)] <- ex_terminal_target

  last_drop <- dec1[length(dec1)]
  n2 <- support_age_max - terminal_age
  if (n2 <= 0L) return(data.table(exact_age = ages1, ex = pmax(0, ex1)))

  total_drop2 <- max(ex_terminal_target - ex_support_target, 1e-8)
  first_drop2 <- min(last_drop, total_drop2)
  lambda2 <- solve_lambda(first_drop2, total_drop2, n2)
  dec2 <- first_drop2 * exp(-lambda2 * (0:(n2 - 1L)))
  ages2 <- (terminal_age + 1L):support_age_max
  ex2 <- ex_terminal_target - cumsum(dec2)
  ex2[length(ex2)] <- ex_support_target

  data.table(
    exact_age = c(ages1, ages2),
    ex = pmax(0, c(ex1, ex2))
  )
}

build_export_from_internal <- function(base_exact, internal_tail, terminal_age = 110L) {
  out <- rbind(
    copy(base_exact[exact_age < min(internal_tail$exact_age)]),
    copy(internal_tail[exact_age <= terminal_age, .(exact_age, ex)]),
    use.names = TRUE
  )
  setorder(out, exact_age)
  out[, `:=`(
    age_start = exact_age,
    age_end = exact_age + 1L,
    age_interval_width = 1L,
    age_interval_open = FALSE,
    age_group_label = paste0(exact_age, "-", exact_age + 1L),
    units = "years"
  )]
  out[exact_age == terminal_age, `:=`(
    age_interval_open = TRUE,
    age_group_label = paste0(terminal_age, "+"),
    age_end = terminal_age + 1L
  )]
  setcolorder(out, c("exact_age", "age_start", "age_end", "age_interval_width", "age_interval_open", "age_group_label", "ex", "units"))
  out[]
}

summarise_tail_metrics <- function(internal, export, base_exact, family, method, monotone_expected) {
  x <- copy(internal)
  setorder(x, exact_age)
  x[, delta := c(NA_real_, diff(ex))]
  x[, second_diff := c(NA_real_, diff(delta))]
  delta_84_85 <- base_exact[exact_age == 85L, ex][1] - base_exact[exact_age == 84L, ex][1]
  delta_85_86 <- x[exact_age == 86L, ex][1] - x[exact_age == 85L, ex][1]
  jump_84_85 <- abs(delta_85_86 - delta_84_85)
  curvature_84_95 <- x[exact_age %in% 84:95, max(abs(second_diff), na.rm = TRUE)]
  if (!is.finite(curvature_84_95)) curvature_84_95 <- 0
  delta_min <- x[exact_age %in% 85:max(export$exact_age), min(delta, na.rm = TRUE)]
  delta_95 <- x[exact_age == 95L, delta][1]
  rebound_ratio_95 <- if (is.na(delta_min) || abs(delta_min) < 1e-10 || is.na(delta_95)) NA_real_ else abs(delta_95 / delta_min)
  monotone_viol <- export[, sum(diff(ex) > 1e-8)]
  delta_pattern <- if (jump_84_85 > 0.35 || (!is.na(rebound_ratio_95) && rebound_ratio_95 < 0.3)) "closure-driven" else "stable"
  score <- jump_84_85 * 30 +
    curvature_84_95 * 10 +
    ifelse(is.na(rebound_ratio_95), 0, pmax(0, 0.45 - rebound_ratio_95) * 24) +
    monotone_viol * ifelse(monotone_expected, 600, 120) +
    ifelse(export[exact_age == max(exact_age), ex][1] <= 1e-8, 240, 0)

  data.table(
    family = family,
    method = method,
    ex_85 = x[exact_age == 85L, ex][1],
    ex_109 = export[exact_age == 109L, ex][1],
    ex_110plus = export[exact_age == 110L, ex][1],
    ex_120_internal = x[exact_age == 120L, ex][1],
    ex_125_internal = x[exact_age == max(x$exact_age), ex][1],
    delta_84_85 = delta_84_85,
    delta_85_86 = delta_85_86,
    jump_84_85 = jump_84_85,
    curvature_84_95 = curvature_84_95,
    rebound_ratio_95 = rebound_ratio_95,
    monotone_violation_n = monotone_viol,
    delta_pattern = delta_pattern,
    score = score
  )
}

qc_tail_behavior <- function(metrics_dt) {
  x <- copy(as.data.table(metrics_dt))
  list(
    delta_jump_84_85_86_excessive = x[jump_84_85 > 0.35],
    tail_delta_rebound_too_fast = x[!is.na(rebound_ratio_95) & rebound_ratio_95 < 0.30],
    terminal_open_ex_nonpositive = x[ex_110plus <= 1e-8],
    law_fit_vs_ex_fit_divergence = x[family == "law_based" & delta_pattern == "closure-driven"]
  )
}
