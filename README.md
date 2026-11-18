# Automated UAV Mapping and Landing-Zone Selection Using R

Build a reproducible workflow for AAV's SUAS 2027 mapping task. R prepares flight photos, coordinates WebODM processing, and turns the resulting orthophoto and a supplied mannequin location into an annotated map and ranked landing-zone candidates.

## Project status

- Prepared 372 Gremsy VIO JPEGs and an image inventory. [01_prepare_images.R](01_prepare_images.R) extracts JPEGs from a flight ZIP and writes the manifest. Run `Rscript 01_prepare_images.R <flight-zip>` from the project root.
- Selected [SIFT Low settings](config/webodm-sift-low.json) for incremental SfM with Fast Orthophoto enabled. The selected run used ODM 3.8.2, took 232.68 seconds in WebODM, registered 346 of 372 frames, and mapped 44,425 m². The settings file records the key options from that run for manual WebODM setup and future automation.
- Verified read access to local NodeODX job status and settings. The optional `Connect-NodeODX.ps1` and `Connect-WebODM.ps1` scripts assist with checking local services on Windows. Their setup stores credentials under the user's local app-data directory.

The SIFT benchmark used the same 372 images. Each row represents one run, and the footprint measures pixels mapped across the whole orthophoto.

| SIFT feature quality | WebODM time | Registered photos | Mapped footprint |
| --- | ---: | ---: | ---: |
| Lowest | 4:17 | 346 / 372 | 43,934 m² |
| Low (selected) | 3:53 | 346 / 372 | 44,425 m² |

## Reproduce the mannequin map

Install the R package with `install.packages("terra")`. The first script uses base R and the second uses `terra`. The map was verified with R 4.6.1 and terra 1.9-50.

- **Flight imagery** comes from AAV's 372-image Gremsy VIO flight ZIP. The project copy is `drive-download-20261118T015500Z-1-001.zip`. The image-preparation script takes the path to the ZIP as its only argument.
- **Orthophoto** comes from AAV OneDrive under `SUAS MAPPING/WebODM Test Results`. Use the **Incremental – sift – Low quality – 3m 53s processing** run and its `odm_orthophoto/odm_orthophoto.tif` file. It has 6,237 by 3,447 pixels in WGS 84 / UTM Zone 17N (EPSG:32617). AAV OneDrive access is required for the test data. Before submitting, provide the instructor with an accessible copy or download links.

Run from the project root, replacing the path and coordinate placeholders with your inputs. Supply longitude first and latitude second, in WGS 84 decimal degrees. Choose a point inside the mapped footprint.

```sh
Rscript 02_plot_mannequin.R "path/to/odm_orthophoto.tif" LONGITUDE LATITUDE "outputs/mannequin-map.png"
```

The script projects the input into the map CRS, checks for mapped pixels at the point, and writes a PNG with the point labeled as synthetic. The demo run was verified against the selected SIFT Low GeoTIFF, including rejection of points in an unmapped gap or outside the image.

## Class project milestones

1. **Complete.** Load the SIFT Low GeoTIFF in R, project a synthetic mannequin point, and export the annotated map.
2. Screen potentially suitable surfaces for a configurable landing footprint and clearance from mapped obstacles. Rank qualifying candidates by distance to the mannequin. Document the limits of RGB imagery and add a slope check if suitable elevation data become available.
3. Connect image preparation, WebODM submission and retrieval, spatial analysis, and exports. Produce an annotated map and a ranked candidate report with coordinates. Reproduce one complete run and record time to export and coverage within the test boundary.
4. Package the R scripts, figures, and presentation. Document the package setup and provide instructor-accessible download instructions for the flight ZIP and any required large data.

Real mannequin detection and an A8 Mini/HM30 field rehearsal are subsequent AAV milestones.

## Class deliverables

- **Complete organized `.R` scripts** covering data processing, analysis, and figure generation. Include required packages, data sources, and download or access information for large datasets.
- **Approximately 10-minute presentation** covering project motivation and why R, study area and data, methods, results and discussion with figures and tables, and conclusions including what you learned. The Dec 1 and Dec 3 live sessions require advance signup. The recorded option is uploaded to Canvas.
- **Approximately two minutes within the presentation for an R code walkthrough.** Show one meaningful section, explain what it does, why you wrote it that way, and how it supports the results. Describe one programming challenge or decision. The landing-zone screening and ranking code is a candidate for this segment.

## GitHub workflow

Track the R scripts, WebODM preset, setup and data access instructions, small figures and result tables, and presentation in the project repository. Keep local raw imagery, full-resolution GeoTIFFs, and machine-specific configuration out of version control. Record a shareable data source and exact input names here before submission.
