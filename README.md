## Housing & Urban Development ("HUD") Data Archive: 2025-02-10

This repository contains utilities & metadata related to the archive performed by Ketchbrook Analytics on 2025-02-10 of HUD datasets.

Ketchbrook Analytics set up a public AWS S3 bucket containing the HUD datasets.

HUD made it much easier to do this programmatically by providing a JSON-format Data Dictionary: https://data.hud.gov/data.json.

## Example

The following code serves as an example on how to find, download, and read a dataset from the AWS S3 bucket.  

```r
library(aws.s3)
library(glue)
library(sf)

bucket <- "hud-data-archive"
region <- "us-east-1"

# Get the id you want from the 'identifier' column of `metadata.csv`
dataset_id <- "02646919444d4fddbc477987ef0ec1e1"

# Get the path in S3 to the dataset that belongs to that identifier
s3_obj <- aws.s3::get_bucket(
  bucket = bucket,
  prefix = dataset_id
)$Contents$Key

# Define URL of file for download
url <- glue::glue("https://{bucket}.s3.{region}.amazonaws.com/{s3_obj}")

# Grab the filename
file_name <- basename(s3_obj)

# Download the file locally
download.file(
  url = url,
  destfile = basename(s3_obj),
  mode = "wb"
)

# Read it with {sf}
sf::read_sf(file_name)
```

## Structure

- [archive.R](archive.R) contains the script used by Ketchbrook Analytics to programmatically downlod the files from HUD and upload them to the AWS S3 bucket
- [metadata.csv](metadata.csv) contains the metadata for each dataset; note that not all datasets in this file (which mirrors the [data dictionary](https://data.hud.gov/data.json)) were able to be downloaded successfully; see the final column of this CSV to identify whether or not a particular dataset was able to be successfully "archived" (i.e., uploaded to S3)
- [R](R/) contains custom functions developed for archiving the datasets

## Requirements

In order to run the [archive.R](archive.R) script, you must have the following environment variables set:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION`
