# herbarium-data

Scripts for exporting herbarium data from FileMaker, transforming it to Darwin Core (DwC), and optionally loading it into PostgreSQL.

## Overview

- Fetch raw data from FileMaker API
- Transform to Darwin Core
- Export DwC CSV and QA tables
- Optionally load raw and DwC data into PostgreSQL
- Optionally publish a new resource version to an IPT (harvested by GBIF)


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
HBDB_API_PWD=your_filemaker_password  
FM_BASE_URL=https://your-filemaker-server  

PGDATABASE=herbarium  
PGUSER=herbarium  
PGPASSWORD=your_postgres_password  
PGHOST=localhost  
PGPORT=5433  

IPT_BASE_URL=https://test.gbif.se/ipt  
IPT_RESOURCE=gb_herbarium  
IPT_USER=you@example.org  
IPT_PASS=your_ipt_password  
```

Restart R after changes.

This file holds passwords. It is ignored by git (`.gitignore`); also restrict access with
`chmod 600 .Renviron`.

## Run

Run the full pipeline:

```r
source("scripts/run_pipeline.R", echo = FALSE)
```

### Settings in run_pipeline.R

```r
input_mode <- "file"   # "file" or "fetch"  
load_to_db <- FALSE    # TRUE to load into PostgreSQL  
check_media <- FALSE   # TRUE to validate associatedMedia links (slow)  
publish_ipt <- FALSE   # TRUE to publish a new IPT resource version
```

## PostgreSQL

To enable database loading:

- A PostgreSQL instance must be running
- Tables `raw.fm_specimen` and `public.dwc_occurrence` must exist
- Connection is configured via `.Renviron`

### Connecting to PostgreSQL

If you run R on the database server itself, no tunnel is needed (set `PGPORT=5432`).

If you run R on your own machine, the database is reached over an SSH tunnel that
forwards local port `5433` to port `5432` on the database server. Local port `5433`
avoids clashing with a PostgreSQL that may already be running locally on `5432`.

Run the tunnel in its own terminal and leave it open:

```bash
ssh -N -L 5433:localhost:5432 user@your-server
```

As an alternative, add a `~/.ssh/config` entry (ask the maintainer for host and user)
and start the tunnel by name:

```
Host herbarium-db
  HostName <database server>
  User <your user>
  IdentityFile ~/.ssh/<your key>
  LocalForward 5433 localhost:5432
```

```bash
ssh -N herbarium-db
```

Either way, set in `.Renviron`:

```r
PGHOST=localhost  
PGPORT=5433  
```

## Outputs

- `data/dwc/occurrence_YYMMDD-HHMMSS.csv`
- `data/qc/qa_YYMMDD-HHMMSS.xlsx` (only if QA issues are found)

## Notes

- Coordinates derived from: decimal → DMS → SWEREF99 → RT90
- Invalid projected coordinates are excluded and reported
- Image links (`associatedMedia`) can be optionally checked
- Duplicate IDs are checked and reported
- Data loading replaces all rows in target tables
- IPT publishing logs in via the web form, publishes a new version, and waits for it to finish
- The pipeline refuses to continue on an empty dataset (0 rows)