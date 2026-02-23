# Title: Snap Outlet Points to Estuary
# Author: Megan Harris
# Institution: Virginia Tech
# Copyright: 2025
# Developed with Python 3.x

import geopandas as gpd
import ast
from shapely.geometry import Point

# File paths
polygons_path = "0-Data/1-RawData/0-GIS/QGIS/RiverSegments/RiverSegmentLayer.shp"
intersection_points_path = "0-Data/1-RawData/0-GIS/QGIS/IntersectionPoints/intersection_points.shp"
assigned_intersection_points_path = "0-Data/1-RawData/0-GIS/QGIS/IntersectionPoints/assigned_intersection_points.shp"
outlet_points_path = "0-Data/1-RawData/0-GIS/QGIS/OutletPoints/outlet_points.shp"
estuary_path = "0-Data/1-RawData/0-GIS/QGIS/Coastline/Chesapeake_Bay_Shoreline_High_Resolution.zip"
output_path = "0-Data/1-RawData/0-GIS/QGIS/OutletPointSnapping/SnapByEstuary/SnappedOutletPointsEstuary.shp"

# Load GeoDataFrames
print("Loading data...")
polygons = gpd.read_file(polygons_path)
intersection_points = gpd.read_file(intersection_points_path)
assigned_intersection_points = gpd.read_file(assigned_intersection_points_path)
outlet_points = gpd.read_file(outlet_points_path)
estuary = gpd.read_file(estuary_path)

# Convert intersecti column values to lists if they are strings formatted as lists
assigned_intersection_points['intersecti'] = assigned_intersection_points['intersecti'].apply(
    lambda x: ast.literal_eval(x) if isinstance(x, str) else x
)

# Ensure CRS consistency
print("Ensuring CRS consistency...")
common_crs = polygons.crs
intersection_points = intersection_points.to_crs(common_crs)
assigned_intersection_points = assigned_intersection_points.to_crs(common_crs)
outlet_points = outlet_points.to_crs(common_crs)
estuary = estuary.to_crs(common_crs)

# Map outlet points to assigned intersection points
snapped_outlet_points = []
total_points = len(outlet_points)
print(f"Total outlet points to process: {total_points}")

for i, outlet in enumerate(outlet_points.itertuples(), start=1):
    outlet_geom = outlet.geometry
    outlet_riverseg = outlet.RiverSeg

    # Find the polygon associated with the outlet point
    polygon = polygons[polygons['RiverSeg'] == outlet_riverseg]

    if polygon.empty:
        print(f"[{i}/{total_points}] No polygon found for RiverSeg {outlet_riverseg}. Skipping.")
        snapped_outlet_points.append({'geometry': outlet_geom, 'RiverSeg': outlet_riverseg})
        continue

    polygon_geom = polygon.iloc[0].geometry

    # Iterate through outlet points and find matches in assigned_intersection_points
    for index, outlet in outlet_points.iterrows():
        outlet_riverseg = outlet['RiverSeg']  # Assuming RiverSeg column exists in outlet_points

        # Check if outlet_riverseg is in the intersecti list for any intersection point
        matches = assigned_intersection_points[
            assigned_intersection_points['intersecti'].apply(lambda lst: outlet_riverseg in lst)
        ]

        if not matches.empty:
            # Do something with the matching intersection points
            print(f"Outlet point {outlet_riverseg} matches intersection points:")
            print(matches)

    # Check if the polygon intersects the estuary
    if polygon_geom.intersects(estuary.geometry.unary_union):
        # Get assigned intersection points for this RiverSeg
        valid_intersections = assigned_intersection_points[
            assigned_intersection_points['intersecti'] == outlet_riverseg
        ]

        if not valid_intersections.empty:
            # Find the closest assigned intersection point
            distances = valid_intersections.geometry.apply(lambda x: outlet_geom.distance(x))
            closest_intersection = valid_intersections.loc[distances.idxmin()]

            snapped_outlet_points.append({'geometry': closest_intersection.geometry, 'RiverSeg': outlet_riverseg})
            print(f"[{i}/{total_points}] Snapped outlet point for RiverSeg {outlet_riverseg} to intersection.")
        else:
            # No valid assigned intersection points, keep the original outlet point
            snapped_outlet_points.append({'geometry': outlet_geom, 'RiverSeg': outlet_riverseg})
            print(f"[{i}/{total_points}] No assigned intersections for RiverSeg {outlet_riverseg}.")
    else:
        # Polygon is not adjacent to the estuary
        snapped_outlet_points.append({'geometry': outlet_geom, 'RiverSeg': outlet_riverseg})
        print(f"[{i}/{total_points}] RiverSeg {outlet_riverseg} is not adjacent to estuary.")

# Convert results to GeoDataFrame and save
snapped_gdf = gpd.GeoDataFrame(snapped_outlet_points, crs=outlet_points.crs)
print("Saving snapped points...")
snapped_gdf.to_file(output_path)
print(f"Snapped points saved to {output_path}.")
