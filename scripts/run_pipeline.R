# ------------------------------------------------------------
# Run pipeline: FileMaker → Darwin Core (DwC)
# ------------------------------------------------------------
# - Chooses whether to read latest raw export file or fetch new data
# - Runs full transformation pipeline
# ------------------------------------------------------------

rm(list = ls())

# --- Settings ----------------------------------------------------------------

# input_mode <- "file"   # "file" or "fetch"
input_mode <- "fetch"


if (!input_mode %in% c("file", "fetch")) {
  stop("Invalid input_mode. Use 'file' or 'fetch'.")
}


# --- Run ---------------------------------------------------------------------

cat("Starting pipeline...\n\n")
cat("Input mode: ", input_mode, "\n\n", sep = "")

if (input_mode == "fetch") {
  source("scripts/fetch_fm_data.R", echo = FALSE)
  
  if (!exists("fm_raw", inherits = FALSE)) {
    stop("scripts/fetch_fm_data.R did not create object 'fm_raw'.")
  }
}

source("scripts/transform_to_dwc.R", echo = FALSE)

cat("\nPipeline finished\n")