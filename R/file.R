get_file_name <- function(distribution_format, download_url) {
  
  if (distribution_format != "ZIP") {
    
    file_name <- basename(download_url)
    
  } else {
    
    file_name <- httr2::request(download_url) |> 
      httr2::req_method("HEAD") |>
      httr2::req_perform() |> 
      httr2::resp_header(header = "Content-Disposition") |> 
      # clean up file name
      stringr::str_remove("attachment; filename=\\\"") |> 
      stringr::str_sub(end = -2L)
    
  }
  
  return(file_name)
  
}

get_file_name_safely <- purrr::safely(get_file_name)



# See https://www.paws-r-sdk.com/examples/s3_multipart_upload/
upload <- function(client, file, bucket, key) {
  multipart <- client$create_multipart_upload(
    Bucket = bucket,
    Key = key
  )
  resp <- NULL
  on.exit({
    if (is.null(resp) || inherits(resp, "try-error")) {
      client$abort_multipart_upload(
        Bucket = bucket,
        Key = key,
        UploadId = multipart$UploadId
      )
    }
  })
  resp <- try({
    parts <- upload_multipart_parts(client, file, bucket, key, multipart$UploadId)
    client$complete_multipart_upload(
      Bucket = bucket,
      Key = key,
      MultipartUpload = list(Parts = parts),
      UploadId = multipart$UploadId
    )
  })
  return(resp)
}



upload_multipart_parts <- function(client, file, bucket, key, upload_id) {
  file_size <- file.size(file)
  megabyte <- 2^20
  part_size <- 5 * megabyte
  num_parts <- ceiling(file_size / part_size)
  
  con <- base::file(file, open = "rb")
  on.exit({
    close(con)
  })
  pb <- utils::txtProgressBar(min = 0, max = num_parts)
  parts <- list()
  for (i in 1:num_parts) {
    part <- readBin(con, what = "raw", n = part_size)
    part_resp <- client$upload_part(
      Body = part,
      Bucket = bucket,
      Key = key,
      PartNumber = i,
      UploadId = upload_id
    )
    parts <- c(parts, list(list(ETag = part_resp$ETag, PartNumber = i)))
    utils::setTxtProgressBar(pb, i)
  }
  close(pb)
  return(parts)
}
