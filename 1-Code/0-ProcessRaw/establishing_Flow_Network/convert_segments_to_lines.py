# Title: Convert Segments to Lines
# Author: Megan Harris
# Institution: Virginia Tech
# Copyright: 2025
# Developed with Python 3.x

import geopandas as gpd

# Load the polygon file
polygons = gpd.read_file("0-Data/1-RawData/0-GIS/QGIS/RiverSegments/RiverSegmentLayer.shp")
outletPoints = gpd.read_file("0-Data/1-RawData/0-GIS/QGIS/OutletPoints/outlet_points.shp")
streamLines = gpd.read_file("0-Data/1-RawData/0-GIS/QGIS/Streams/smooth_streams.zip")

# Print the current CRS
print("Current CRS:", polygons.crs)

# Ensure CRS is consistent
target_crs = "EPSG:5070"  # replace with the desired EPSG code
polygons = polygons.to_crs(target_crs)
print("Current CRS:", polygons.crs)

# Convert polygons to lines
polygon_lines = polygons.boundary

# Save to a new shapefile
polygon_lines.to_file("0-Data/1-RawData/0-GIS/QGIS/RiverSegmentLines/RiverSegmentLines.shp")
