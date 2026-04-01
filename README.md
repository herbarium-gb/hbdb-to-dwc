# hbdb-to-dwc

Pipeline for exporting herbarium data from FileMaker and transforming it to Darwin Core (DwC).

## What the pipeline does

1. Fetches raw export data from the FileMaker Data API
2. Saves raw data as an Excel file in data/raw/
3. Transforms raw data to Darwin Core format
4. Saves DwC output as CSV in data/output/
5. Writes QA tables for invalid projected coordinates when needed

## Requirements

R packages used:

- httr
- jsonlite
- data.table
- readxl
- sf
- readr
- writexl

Install if needed:

install.packages(c(
  "httr",
  "jsonlite",
  "data.table",
  "readxl",
  "sf",
  "readr",
  "writexl"
))

## Configuration

Create a `.Renviron` file in your home directory or in the project root with:

HBDB_API_PWD=your_password_here
FM_BASE_URL=your_base_url_here

These variables are used by the pipeline:

- HBDB_API_PWD: password for the FileMaker Data API
- FM_BASE_URL: base URL for the FileMaker database API

After creating or modifying `.Renviron`, restart your R session.

## Input files

Column mapping file:

config/col-map.xlsx

Raw data:

Stored in data/raw/ with filenames like:

fm_raw_YYMMDD-HHMMSS.xlsx

## Running the pipeline

Open the project in RStudio and run:

source("scripts/run_pipeline.R", echo = FALSE)

### Choose input mode

In scripts/run_pipeline.R:

input_mode <- "file"

Options:

- "file"  = use latest raw export
- "fetch" = fetch fresh data from FileMaker

## Outputs

Darwin Core CSV:

data/output/occurrence_YYMMDD-HHMMSS.csv

QA file (only if needed):

data/output/bad_projected_coordinates.xlsx

## Coordinate handling

Coordinates are derived in this order:

1. direct decimal degrees
2. DMS
3. SWEREF99 TM
4. RT90

Invalid projected coordinates are excluded and reported.

## QA summary

The script reports:

- input source used
- output file written
- number of rows
- invalid SWEREF rows
- invalid RT90 rows
- duplicate ids (if any)

## Notes

- Raw and output data are ignored by Git
- config/col-map.xlsx is versioned
- .Renviron must never be committed
