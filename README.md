# herbarium-data

Scripts for exporting herbarium data from FileMaker, transforming it to Darwin Core (DwC), and optionally loading it into PostgreSQL.

## Overview

- Fetch raw data from FileMaker API
- Transform to Darwin Core
- Export DwC CSV and QA tables
- Optionally load raw and DwC data into PostgreSQL


## Related repository

This repository handles data extraction and transformation.

The deployment environment (image server, web viewer, and PostgreSQL used for publishing) is managed separately in:

- https://github.com/herbarium-gb/herbarium-platform

Typical flow:

- `herbarium-data`: fetch + transform + export/load DwC
- `herbarium-platform`: serve images and publish data (e.g. via IPT)

## Requirements

```r
install.packages(c(
  "httr",
  "jsonlite",
  "data.table",
  "readxl",
  "sf",
  "readr",
  "writexl",
  "DBI",
  "RPostgres"
))
```

## Configuration

Create a `.Renviron` file:

```r
HBDB_API_PWD=your_password_here  
FM_BASE_URL=https://your-filemaker-server  

PGDATABASE=herbarium  
PGUSER=herbarium  
PGPASSWORD=your_password_here  
PGHOST=localhost  
PGPORT=5432  
```

Restart R after changes.

## Run

Run the full pipeline:

```r
source("scripts/run_pipeline.R", echo = FALSE)
```

### Settings in run_pipeline.R

```r
input_mode <- "file"   # "file" or "fetch"  
load_to_db <- FALSE    # TRUE to load into PostgreSQL  
```

## PostgreSQL

To enable database loading:

- A PostgreSQL instance must be running
- Tables `raw.fm_specimen` and `public.dwc_occurrence` must exist
- Connection is configured via `.Renviron`

### Connecting to PostgreSQL

If you run R on the same server as PostgreSQL, no additional setup is needed.

If you run R locally, you typically need an SSH tunnel:

```bash
ssh -L 5432:localhost:5432 user@your-server
```

This forwards your local port `5432` to the server’s PostgreSQL instance.

Then use in `.Renviron`:

```r
PGHOST=localhost  
PGPORT=5432  
```

The scripts assume that PostgreSQL is reachable via these settings.

## Outputs

- `data/dwc/occurrence_YYMMDD-HHMMSS.csv`
- `data/qc/qa_YYMMDD-HHMMSS.xlsx` (only if QA issues are found)

## Notes

- Coordinates derived from: decimal → DMS → SWEREF99 → RT90
- Invalid projected coordinates are excluded and reported
- Image links (`associatedMedia`) can be optionally checked
- Duplicate IDs are checked and reported
- Data loading replaces all rows in target tables