# Run from the project folder: Rscript 01_prepare_images.R <path-to-zip>
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L || !file.exists(args[1])) {
  stop("Supply the path to the flight image ZIP.")
}

archive <- normalizePath(args[1], winslash = "/", mustWork = TRUE)
entries <- unzip(archive, list = TRUE)
photos <- entries[grepl("\\.(jpg|jpeg)$", entries$Name, ignore.case = TRUE), ]
if (nrow(photos) == 0L) {
  stop("The ZIP does not contain JPEG flight images.")
}
if (anyDuplicated(tolower(basename(photos$Name)))) {
  stop("The ZIP contains JPEGs with duplicate filenames.")
}

photos <- photos[order(photos$Name), ]
image_dir <- file.path("data", "raw", tools::file_path_sans_ext(basename(archive)))
dir.create(image_dir, recursive = TRUE, showWarnings = FALSE)
image_paths <- file.path(image_dir, basename(photos$Name))

# Skip extraction if all expected files already match the archive's sizes.
if (!isTRUE(all(file.size(image_paths) == photos$Length))) {
  unzip(archive, files = photos$Name, exdir = image_dir, junkpaths = TRUE)
}
if (!isTRUE(all(file.size(image_paths) == photos$Length))) {
  stop("Extracted images do not match the archive's file sizes.")
}

manifest_path <- file.path("data", "raw", paste0(basename(image_dir), "_manifest.csv"))
write.csv(
  data.frame(image_path = image_paths, bytes = photos$Length),
  manifest_path,
  row.names = FALSE
)
message(nrow(photos), " images ready in ", image_dir)
message("Image inventory written to ", manifest_path)
