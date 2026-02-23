# Title: Rename Outlets Adjacent to Estuary
# Author: Megan Harris
# Institution: Virginia Tech
# Copyright: 2025
# Developed with Python 3.x

import geopandas as gpd

# File paths
outlet_points_path = "0-Data/1-RawData/0-GIS/QGIS/OutletPointSnapping/SnappedToDownstreamIntersection/SnappedToDownstreamIntersection.shp"
polygons_path = "0-Data/1-RawData/0-GIS/QGIS/RiverSegments/RiverSegmentLayer.shp"
estuary_path = "0-Data/1-RawData/0-GIS/QGIS/Coastline/Chesapeake_Bay_Shoreline_High_Resolution.zip"
output_points_path = "0-Data/1-RawData/0-GIS/QGIS/RenamedPointsPolygons/RenamedPoints/RenamedPoints.shp"
output_polygons_path = "0-Data/1-RawData/0-GIS/QGIS/RenamedPointsPolygons/RenamedPolygons/RenamedPolygons.shp"

# Load shapefiles
print("Loading shapefiles...")
outlet_points = gpd.read_file(outlet_points_path)
polygons = gpd.read_file(polygons_path)
estuary = gpd.read_file(estuary_path)

# Ensure CRS matches
print("Checking and aligning CRS...")
polygons = polygons.to_crs(estuary.crs)
outlet_points = outlet_points.to_crs(estuary.crs)

# Identify polygons adjacent to the estuary
print("Identifying polygons adjacent to the estuary...")
polygons_adjacent_to_estuary = polygons[polygons.geometry.intersects(estuary.unary_union)]
print(f"Found {len(polygons_adjacent_to_estuary)} polygons adjacent to the estuary.")

# Rename RiverSeg values that do not end with 0000 and ensure outlet points touch estuary
print("Validating and renaming RiverSeg values for polygons and outlet points...")
renamed_count = 0
non_touching_points = []

for index, poly in polygons_adjacent_to_estuary.iterrows():
    old_riverseg = poly["RiverSeg"]
    if not old_riverseg.endswith("0000"):
        # Ensure there is a touching outlet point
        matching_points = outlet_points[outlet_points["RiverSeg"] == old_riverseg]
        touching_points = matching_points[matching_points.geometry.touches(estuary.unary_union)]

        if not touching_points.empty:
            new_riverseg = old_riverseg[:-4] + "0000"
            print(f"Renaming {old_riverseg} to {new_riverseg}")

            # Update the polygon's RiverSeg
            polygons.loc[polygons.index == index, "RiverSeg"] = new_riverseg

            # Update the corresponding outlet point's RiverSeg
            outlet_points.loc[touching_points.index, "RiverSeg"] = new_riverseg
            renamed_count += len(touching_points)
        else:
            # Log points that do not touch the estuary
            non_touching_points.append(old_riverseg)

print(f"Renamed {renamed_count} polygons and their outlet points.")
if non_touching_points:
    print("The following RiverSeg values do not have outlet points touching the estuary:")
    for seg in non_touching_points:
        print(f"  - {seg}")

# Save updated shapefiles
print("Saving updated shapefiles...")
polygons.to_file(output_polygons_path, driver="ESRI Shapefile")
outlet_points.to_file(output_points_path, driver="ESRI Shapefile")
print(f"Updated shapefiles saved to {output_polygons_path} and {output_points_path}.")
