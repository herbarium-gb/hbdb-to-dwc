# ------------------------------------------------------------
# IPT publish: QA gate -> publish new resource version
# ------------------------------------------------------------
# Reads QA objects from transform_to_dwc.R, warns interactively
# on issues, then publishes a new version of the IPT resource.
#
# The IPT has no REST API for publishing, so this mimics the
# web UI: obtain a CSRF token, log in (form + session cookie),
# POST manage/publish.do, then poll manage/report.do until the
# publication finishes. GBIF re-harvests the resource on its
# own schedule afterwards.
# ------------------------------------------------------------

library(httr)

# --- Credentials -----------------------------------------------------------

ipt_base_url <- Sys.getenv("IPT_BASE_URL")
if (!nzchar(ipt_base_url)) stop("Missing env var: IPT_BASE_URL")

ipt_resource <- Sys.getenv("IPT_RESOURCE")
if (!nzchar(ipt_resource)) stop("Missing env var: IPT_RESOURCE")

ipt_username <- Sys.getenv("IPT_USER")
if (!nzchar(ipt_username)) stop("Missing env var: IPT_USER")

ipt_password <- Sys.getenv("IPT_PASS")
if (!nzchar(ipt_password)) stop("Missing env var: IPT_PASS")

# --- Config ----------------------------------------------------------------

publish_timeout_min <- 20   # max minutes to wait for publication to finish
poll_interval_sec   <- 5

# --- Helpers -------------------------------------------------------------------

`%||%` <- function(x, y) if (!is.null(x) && length(x) > 0 && !is.na(x[1]) && nzchar(x[1])) x else y

ask_yes_no <- function(prompt, default = FALSE) {
  if (!interactive()) {
    message(prompt)
    message("Non-interactive session - defaulting to: ", if (default) "yes" else "no")
    return(default)
  }
  answer <- readline(paste0(prompt, " [y/N]: "))
  tolower(trimws(answer)) %in% c("y", "yes", "j", "ja")
}

abort_publish <- function(msg) {
  cat(msg, "\n")
  cat("Publishing cancelled.\n")
  ipt_published <<- FALSE
}

# --- QA gate -----------------------------------------------------------------

# An empty table must never be published - GBIF would drop every record.
if (exists("dwc", inherits = TRUE) && nrow(dwc) == 0) {
  cat("\nDwC table has 0 rows - refusing to publish an empty dataset.\n")
  ipt_published <- FALSE
  return(invisible(NULL))
}

qa_blockers <- character(0)

if (exists("n_dup_ids", inherits = TRUE) && !is.na(n_dup_ids) && n_dup_ids > 0) {
  n_rows_affected <- if (exists("n_dup_rows", inherits = TRUE) && !is.na(n_dup_rows)) n_dup_rows else NA_integer_
  qa_blockers <- c(qa_blockers,
                   sprintf("Duplicate occurrenceID: %d ids affecting %s rows",
                           n_dup_ids,
                           if (is.na(n_rows_affected)) "?" else as.character(n_rows_affected)))
}

if (exists("n_bad_sweref", inherits = TRUE) && !is.na(n_bad_sweref) && n_bad_sweref > 0)
  qa_blockers <- c(qa_blockers,
                   sprintf("Invalid SWEREF99 coordinates: %d rows", n_bad_sweref))

if (exists("n_bad_rt90", inherits = TRUE) && !is.na(n_bad_rt90) && n_bad_rt90 > 0)
  qa_blockers <- c(qa_blockers,
                   sprintf("Invalid RT90 coordinates: %d rows", n_bad_rt90))

if (exists("n_bad_media", inherits = TRUE) && !is.na(n_bad_media) && n_bad_media > 0)
  qa_blockers <- c(qa_blockers,
                   sprintf("Broken media links: %d rows", n_bad_media))

ipt_published <- FALSE

if (length(qa_blockers) > 0) {
  cat("\n--- QA warnings ------------------------------------------------------\n")
  for (issue in qa_blockers) cat("  !", issue, "\n")
  cat("\n")

  if (!ask_yes_no("Publish to IPT anyway?")) {
    abort_publish("Not proceeding past QA warnings.")
    rm(qa_blockers, ipt_base_url, ipt_resource, ipt_username, ipt_password,
       publish_timeout_min, poll_interval_sec, `%||%`, ask_yes_no, abort_publish)
    return(invisible(NULL))
  }

  cat("Proceeding despite QA warnings.\n\n")
} else {
  cat("\n--- QA gate: no issues found -----------------------------------------\n")
}

rm(qa_blockers)

# --- Version comment -------------------------------------------------------

ipt_comment <- paste0(
  "Pipeline publish ",
  format(Sys.time(), "%Y-%m-%d %H:%M"),
  if (exists("out_file", inherits = TRUE) && nzchar(out_file))
    paste0(" | DwC: ", basename(out_file))
  else
    ""
)

base_url    <- sub("/+$", "", ipt_base_url)
login_url   <- paste0(base_url, "/login.do")
publish_url <- paste0(base_url, "/manage/publish.do")
report_url  <- paste0(base_url, "/manage/report.do")
rss_url     <- paste0(base_url, "/rss.do")

# --- Final confirmation ---------------------------------------------------

cat("\n--- Ready to publish ----------------------------------------------------\n")
cat("IPT:              ", base_url,     "\n", sep = "")
cat("Resource:         ", ipt_resource, "\n", sep = "")
cat("User:             ", ipt_username, "\n", sep = "")
cat("Version comment:  ", ipt_comment,  "\n", sep = "")
cat("\n")

if (interactive() && !ask_yes_no("Publish a new version of this resource now?")) {
  abort_publish("Aborted at final confirmation.")
  rm(ipt_base_url, ipt_resource, ipt_username, ipt_password, ipt_comment,
     publish_timeout_min, poll_interval_sec, base_url, login_url, publish_url,
     report_url, rss_url, `%||%`, ask_yes_no, abort_publish)
  return(invisible(NULL))
}

# --- Version helper ------------------------------------------------------

read_ipt_version <- function(h, resource) {
  tryCatch({
    resp <- httr::GET(rss_url, handle = h, httr::timeout(60))
    if (httr::status_code(resp) >= 400) return(NA_character_)
    txt   <- httr::content(resp, as = "text", encoding = "UTF-8")
    items <- regmatches(txt, gregexpr("<item>.*?</item>", txt, perl = TRUE))[[1]]
    hit   <- items[grepl(sprintf("[?&]r=%s(&|<|\"|')", resource), items)]
    if (length(hit) == 0) return(NA_character_)
    v <- regmatches(hit[1], regexpr("[?&]v=([0-9.]+)", hit[1], perl = TRUE))
    if (length(v) == 0) return(NA_character_)
    sub(".*v=", "", v)
  }, error = function(e) NA_character_)
}

# --- Session: CSRF token + login ---------------------------------------

h <- httr::handle(base_url)

home_resp <- httr::GET(base_url, handle = h, httr::timeout(60))
if (httr::status_code(home_resp) >= 400) {
  stop(sprintf("Could not reach IPT at %s (HTTP %d).",
               base_url, httr::status_code(home_resp)))
}

ck   <- httr::cookies(home_resp)
csrf <- ck$value[ck$name == "CSRFtoken"]
if (length(csrf) == 0 || !nzchar(csrf[1])) {
  stop("No CSRFtoken cookie returned by the IPT - cannot log in.")
}
csrf <- csrf[1]

login_resp <- httr::POST(
  login_url,
  body = list(
    email     = ipt_username,
    password  = ipt_password,
    csrfToken = csrf,
    login     = "Login"
  ),
  encode = "form",
  handle = h,
  httr::timeout(60)
)

# On bad credentials the IPT re-renders the login form (INPUT); on success it
# redirects away from it. Confirm by requesting a manager-only page.
check_resp <- httr::GET(paste0(base_url, "/manage/resources.do"),
                        handle = h, httr::timeout(60))
check_body <- httr::content(check_resp, as = "text", encoding = "UTF-8")

if (httr::status_code(check_resp) >= 400 ||
    grepl('name="password"', check_body, fixed = TRUE)) {
  stop("IPT login failed - check IPT_USER / IPT_PASS and that the account ",
       "has manager rights on the installation.")
}

cat("IPT login: OK\n")

# --- Verify resource + current version --------------------------------

# The resource must appear in this account's manage list. If it does not,
# IPT_RESOURCE / IPT_BASE_URL are almost certainly wrong - stop rather than
# fire a publish at whatever else answers to that name.
if (!grepl(sprintf("[?&]r=%s(&|<|\"|')", ipt_resource), check_body) &&
    !grepl(ipt_resource, check_body, fixed = TRUE)) {
  stop(sprintf(paste0(
    "Resource '%s' is not in your manage list on %s. Refusing to publish. ",
    "Check IPT_RESOURCE and IPT_BASE_URL in .Renviron."),
    ipt_resource, base_url))
}

current_version <- read_ipt_version(h, ipt_resource)
cat("Current IPT version: ", current_version %||% "unknown", "\n", sep = "")

# --- Publish -------------------------------------------------------------

pub_resp <- httr::POST(
  paste0(publish_url, "?r=", utils::URLencode(ipt_resource, reserved = TRUE)),
  body = list(r = ipt_resource, summary = ipt_comment, publish = "Publish"),
  encode = "form",
  handle = h,
  httr::timeout(120)
)

if (httr::status_code(pub_resp) >= 400) {
  stop(sprintf("IPT publish request failed (HTTP %d): %s",
               httr::status_code(pub_resp),
               substr(httr::content(pub_resp, as = "text", encoding = "UTF-8"), 1, 500)))
}

# --- Poll the publication report -------------------------------------

cat("Publication started - polling report (timeout ",
    publish_timeout_min, " min)...\n", sep = "")

deadline <- Sys.time() + publish_timeout_min * 60
status   <- "timeout"

repeat {
  Sys.sleep(poll_interval_sec)

  rep_resp <- httr::GET(paste0(report_url, "?r=", utils::URLencode(ipt_resource, reserved = TRUE)),
                        handle = h, httr::timeout(60))
  rep_body <- httr::content(rep_resp, as = "text", encoding = "UTF-8")

  if (grepl('class="completed"', rep_body, fixed = TRUE)) {
    status <- if (grepl("alert-danger", rep_body, fixed = TRUE) ||
                  grepl("text-gbif-danger", rep_body, fixed = TRUE)) "failed" else "completed"
    break
  }

  if (Sys.time() > deadline) break
  cat("  ... still publishing\n")
}

# --- Report --------------------------------------------------------------

new_version <- read_ipt_version(h, ipt_resource)

cat("\n--- IPT publish ", toupper(status), " ",
    strrep("-", max(0, 45 - nchar(status))), "\n", sep = "")
cat("Resource:         ", ipt_resource,                      "\n", sep = "")
cat("Previous version: ", current_version %||% "unknown",    "\n", sep = "")
cat("Current version:  ", new_version     %||% "unknown",    "\n", sep = "")

if (identical(status, "completed")) {
  cat("\nGBIF will re-harvest ", ipt_resource,
      " on its next crawl.\n", sep = "")
  ipt_published <- TRUE
} else if (identical(status, "failed")) {
  ipt_published <- FALSE
  stop("IPT reported a failed publication - check the resource's log in the IPT UI.")
} else {
  ipt_published <- FALSE
  warning(sprintf(
    "Publication did not finish within %d min. It may still complete on the IPT; check the UI.",
    publish_timeout_min))
}

# --- Cleanup -----------------------------------------------------------------
# Keeps: ipt_published (pipeline output)
# Keeps: pipeline flags and outputs from earlier steps

rm(`%||%`, ask_yes_no, abort_publish, read_ipt_version,
   ipt_base_url, ipt_resource, ipt_username, ipt_password, ipt_comment,
   publish_timeout_min, poll_interval_sec,
   base_url, login_url, publish_url, report_url, rss_url,
   h, home_resp, ck, csrf, login_resp, check_resp, check_body,
   current_version, pub_resp, deadline, status, rep_resp, rep_body, new_version)
