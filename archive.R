library(paws)
library(jsonlite)
library(httr2)
library(dplyr)
library(tidyr)
library(purrr)

source("R/file.R")
options(timeout = 300)   # 5 minutes max wait for downloads (instead of 1 min)


# Determine Data to be Archived -------------------------------------------

# Read the HUD data dictionary
hud_data_dictionary <- jsonlite::fromJSON(
  "https://data.hud.gov/data.json",
  simplifyDataFrame = TRUE,
  flatten = TRUE
) |>
  purrr::pluck("dataset")

# Unnest the "distribution" list column into many columns prefixed by
# "distribution_"
data <- hud_data_dictionary |>
  tidyr::unnest(
    cols = distribution,
    names_sep = "_"
  ) |> 
  dplyr::slice(-1)   # remove the data dictionary itself

# Take a look at the different distribution formats
data |> dplyr::distinct(distribution_format)

# Take a look at the different file extensions for available downloads;
## Ignore:
## - "Web Page" (out of scope; assume/hope these are backed by other raw datasets)
## - "html" (the only html file is a summary table)
## - "API" (out of scope)
data |> 
  dplyr::filter(
    distribution_format %in% c("ZIP", "xlsx", "xls")
  ) |> 
  dplyr::mutate(
    downloadURL_ext = tools::file_ext(distribution_downloadURL)
  ) |> 
  dplyr::distinct(downloadURL_ext)

# Why don't we see an ZIP file extensions...?
## ...Turns out these are all gdb.zip files; the downloadURL will work
data |> 
  dplyr::filter(
    distribution_format == "ZIP"
  ) |>
  dplyr::pull(distribution_downloadURL) |> 
  head()

# How many datasets are we downloading?
data_for_download <- data |> 
  dplyr::filter(
    distribution_format %in% c("ZIP", "xlsx", "xls"),
    !is.na(distribution_downloadURL)
  )

## Answer: 215
data_for_download |> nrow()

# Clean up the other list columns so we can write to CSV
data_for_download <- data_for_download |> 
  dplyr::mutate(
    dplyr::across(
      .cols = c(keyword, bureauCode, programCode),
      .fns = \(x) purrr::map_chr(.x = x, .f = ~ paste(.x, collapse = " | "))
    )
  )



# Archive Data in S3 Storage ----------------------------------------------

# Initialize the s3 connection
s3 <- paws::s3()

# Get a list of the unique "identifier" column values that we can loop through
ids <- unique(data_for_download$identifier)

# For each unique identifier...
for (i in ids) {
  
  cli::cli_h1("ID: {i}")
  cli::cli_alert_info("Creating local folder...")
  
  # Create a directory to download related files to (locally)
  fs::dir_create(i)
  
  # Determine the set of files we are downloading related to this identifier
  files <- data_for_download |> 
    dplyr::filter(identifier == i)
  
  cli::cli_alert_info("Identified {nrow(files)} files.")
  
  # If we have more than 1 file & one of them is a gdb.zip file, only download
  # (and upload to s3) the gdb.zip file (i.e., ignore the .zip file);
  ## This will save us a lot of storage space, and we assume it's the same data,
  ## just in two different file formats
  if (nrow(files) > 1L) {
    
    file_types <- files |> 
      dplyr::pull(distribution_mediaType) |> 
      unique()
    
    cli::cli_alert_info(
      "Found the following file types: {paste(file_types, collapse = ', ')}."
    )
    
    if ("GeoDatabase/ZIP" %in% file_types) {
      
      cli::cli_alert_info("Only keeping the GeoDatabase/ZIP file.")
      
      files <- files |> 
        dplyr::filter(distribution_mediaType == "GeoDatabase/ZIP")
      
    }
    
  }
  
  # For each of the related files...
  for (j in 1:nrow(files)) {
    
    # ...get the download URL
    download_url <- files$distribution_downloadURL[j]
    
    # and the file name
    file_name <- get_file_name_safely(
      distribution_format = files$distribution_format[j],
      download_url = download_url
    )
    
    # Some of the URLs point to missing files; ensure we handle this gracefully
    if (is.null(file_name$result) & !is.null(file_name$error)) {
      
      cli::cli_alert_warning("No file found; Skipped!")
      
      next
      
    }
    
    # Define the full path to the file ("<identifier>/<file_name>")
    full_path <- fs::path(i, file_name$result)
    
    # Download the file locally
    download.file(
      url = download_url,
      destfile = full_path,
      mode = "wb"
    )
    
    cli::cli_alert_info("Copying to S3...")
    
    # Upload the file to S3 bucket
    upload(
      client = s3,
      file = full_path,
      bucket = "hud-data-archive",
      key = full_path
    )
    
  }
  
  cli::cli_alert_info("Removing local folder...")

  # Remove the directory after it made it to S3
  fs::dir_delete(i)
  
}

# Get a list of the s3 directories (representing the identifiers)
successful_ids <- s3$list_objects(Bucket = "hud-data-archive") |> 
  purrr::pluck("Contents") |> 
  purrr::map(
    .f = \(x) x$Key
  ) |> 
  purrr::list_c() |> 
  dirname()

# Create a .csv containing metadata for the files we are going to download
data_for_download |> 
  # add a new column based upon if the data made it to s3
  dplyr::mutate(
    successfully_archived = identifier %in% successful_ids
  ) |>
  write.csv(
    file = "metadata.csv",
    quote = TRUE,
    row.names = FALSE
  )





obj <- s3$get_object(
  Bucket = "hud-data-archive",
  Key = "02646919444d4fddbc477987ef0ec1e1/Community_Development_Block_Grant_Grantee_Areas.gdb.zip"
)

obj$Body |> rawConnection() |> gzcon(text = TRUE) |> sf::read_sf()



writeBin(obj$Body, con = "Community_Development_Block_Grant_Grantee_Areas.gdb.zip")


library(sf)


file <- "ACS_5YR_CHAS_Estimate_Data_by_County.gdb.zip"
layers <- sf::st_layers(file)





