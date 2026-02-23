# Title: Rename Land-River Segments
# Author: Megan Harris
# Institution: Virginia Tech
# Copyright: 2025
# Developed with Python 3.x

import geopandas as gpd

# Define paths
riverSegmentPath = "0-Data/1-RawData/0-GIS/QGIS/RenamedPointsPolygons/RenamedPolygons/RenamedPolygons.shp"
landRiverSegmentPath = "0-Data/1-RawData/0-GIS/QGIS/P6Beta_v3_LRSegs_081516.zip"
updatedLandRiverSegmentPath = "0-Data/1-RawData/0-GIS/QGIS/RenamedPointsPolygons/RenamedLRSegments/RenamedLRSegments.shp"

# Load shapefiles
print("Loading renamed river segment polygons...")
river_segments = gpd.read_file(riverSegmentPath)

print("Loading land-river segment polygons...")
land_river_segments = gpd.read_file(landRiverSegmentPath)

# Ensure CRS is consistent
target_crs = river_segments.crs
land_river_segments = land_river_segments.to_crs(target_crs)

# Spatial join to associate land-river segments with renamed river segments
print("Performing spatial join...")
land_river_segments_with_rivers = gpd.sjoin(
    land_river_segments,
    river_segments[['geometry', 'RiverSeg']],  # Keep only relevant columns from river_segments
    how="left",
    predicate="intersects"  # Use spatial intersection to match polygons
)

# Rename the RiverSeg column to RiverSegN
print("Renaming RiverSeg to RiverSegN...")
land_river_segments_with_rivers['RiverSegN'] = land_river_segments_with_rivers['RiverSeg_right']

# Handle any cases where no match was found
unmatched = land_river_segments_with_rivers[land_river_segments_with_rivers['RiverSegN'].isnull()]
if not unmatched.empty:
    print(f"Warning: {len(unmatched)} land-river segments could not be matched to a renamed river segment.")
    unmatched.to_file("UnmatchedLandRiverSegments.shp")  # Save unmatched segments for review

# Create the LndRvrSegN attribute by concatenating FIPS_NHL and RiverSegN
print("Creating LndRvrSegN attribute...")
land_river_segments_with_rivers['LndRvrSegN'] = (
    land_river_segments_with_rivers['FIPS_NHL'] + land_river_segments_with_rivers['RiverSegN']
)

# Count the number of renamed segments
renamed_count = land_river_segments_with_rivers['RiverSegN'].notnull().sum()
print(f"{renamed_count} land-river segments had their RiverSeg renamed.")

# Drop unnecessary columns and keep the updated RiverSeg and LndRvrSegN
final_land_river_segments = land_river_segments_with_rivers.drop(columns=['RiverSeg_right'])

# Save updated shapefile
print("Saving updated land-river segments...")# Title: Rename Land-River Segments
# Author: Megan Harris
# Institution: Virginia Tech
# Copyright: 2025
# Developed with Python 3.x

import geopandas as gpd

# Define paths
riverSegmentPath = "0-Data/1-RawData/0-GIS/QGIS/RenamedPointsPolygons/RenamedPolygons/RenamedPolygons.shp"
landRiverSegmentPath = "0-Data/1-RawData/0-GIS/QGIS/P6Beta_v3_LRSegs_081516.zip"
updatedLandRiverSegmentPath = "0-Data/1-RawData/0-GIS/QGIS/RenamedPointsPolygons/RenamedLRSegments/RenamedLRSegments.shp"

# Load shapefiles
print("Loading renamed river segment polygons...")
river_segments = gpd.read_file(riverSegmentPath)

print("Loading land-river segment polygons...")
land_river_segments = gpd.read_file(landRiverSegmentPath)

# Ensure CRS is consistent
target_crs = river_segments.crs
land_river_segments = land_river_segments.to_crs(target_crs)

# Spatial join to associate land-river segments with renamed river segments
print("Performing spatial join...")
land_river_segments_with_rivers = gpd.sjoin(
    land_river_segments,
    river_segments[['geometry', 'RiverSeg']],  # Keep only relevant columns from river_segments
    how="left",
    predicate="intersects"  # Use spatial intersection to match polygons
)

# Rename the RiverSeg column to RiverSegN
print("Renaming RiverSeg to RiverSegN...")
land_river_segments_with_rivers['RiverSegN'] = land_river_segments_with_rivers['RiverSeg_right']

# Handle any cases where no match was found
unmatched = land_river_segments_with_rivers[land_river_segments_with_rivers['RiverSegN'].isnull()]
if not unmatched.empty:
    print(f"Warning: {len(unmatched)} land-river segments could not be matched to a renamed river segment.")
    unmatched.to_file("UnmatchedLandRiverSegments.shp")  # Save unmatched segments for review

# Create the LndRvrSegN attribute by concatenating FIPS_NHL and RiverSegN
print("Creating LndRvrSegN attribute...")
land_river_segments_with_rivers['LndRvrSegN'] = (
    land_river_segments_with_rivers['FIPS_NHL'] + land_river_segments_with_rivers['RiverSegN']
)

# Count the number of renamed segments
renamed_count = land_river_segments_with_rivers['RiverSegN'].notnull().sum()
print(f"{renamed_count} land-river segments had their RiverSeg renamed.")

# Drop unnecessary columns and keep the updated RiverSeg and LndRvrSegN
final_land_river_segments = land_river_segments_with_rivers.drop(columns=['RiverSeg_right'])

# Save updated shapefile
print("Saving updated land-river segments...")
final_land_river_segments.to_file(updatedLandRiverSegmentPath)
print("Updated land-river segments saved successfully.")
final_land_river_segments.to_file(updatedLandRiverSegmentPath)
print("Updated land-river segments saved successfully.")