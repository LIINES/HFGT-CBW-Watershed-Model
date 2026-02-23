# Title: Snap Outlet Points to Downstream Connections
# Author: Megan Harris
# Institution: Virginia Tech
# Copyright: 2025
# Developed with Python 3.x

import geopandas as gpd
from shapely.ops import nearest_points
from shapely.geometry import Point

# Define paths
polygons_path = "0-Data/1-RawData/0-GIS/QGIS/RiverSegments/RiverSegmentLayer.shp"
pathOutletPoints = "0-Data/1-RawData/0-GIS/QGIS/OutletPointSnapping/SnapByEstuary/SnappedOutletPointsEstuary.shp"
pathIntersectionPoints = "0-Data/1-RawData/0-GIS/QGIS/IntersectionPoints/intersection_points.shp"
pathSnappedOutletPoints = "0-Data/1-RawData/0-GIS/QGIS/OutletPointSnapping/SnappedToDownstreamIntersection/SnappedToDownstreamIntersection.shp"
estuary_path = "0-Data/1-RawData/0-GIS/QGIS/Coastline/Chesapeake_Bay_Shoreline_High_Resolution.zip"

# Define the target CRS for consistency across all files
target_crs = "EPSG:5070"  # NAD 1983 Albers Equal Area Conic

# Function to parse RiverSeg IDs
def parse_riverseg(segment):
    upstream_id = segment[4:8]  # First four digits after prefix
    downstream_id = segment[9:13]  # Next four digits after first set
    return upstream_id, downstream_id

# Read the shapefiles
print("Loading river segment polygons...")
polygons = gpd.read_file(polygons_path).to_crs(target_crs)
print("Loading outlet points...")
points_to_snap = gpd.read_file(pathOutletPoints).to_crs(target_crs)
print("Loading intersection points...")
intersection_points = gpd.read_file(pathIntersectionPoints).to_crs(target_crs)
print("Loading estuary geometry...")
estuary = gpd.read_file(estuary_path).to_crs(target_crs)

# Remove points with river segment value "ZZ0_9999_9999"
print("Removing outlet points with river segment value 'ZZ0_9999_9999'...")
points_to_snap = points_to_snap[points_to_snap['RiverSeg'] != "ZZ0_9999_9999"]
print(f"Remaining outlet points: {len(points_to_snap)}")

# Function to check if a polygon is adjacent to the estuary
def is_adjacent_to_estuary(polygon, estuary_geom):
    adjacency = polygon.geometry.intersects(estuary_geom.unary_union)
    if adjacency:
        print(f"Polygon {polygon['RiverSeg']} is adjacent to the estuary.")
    else:
        print(f"Polygon {polygon['RiverSeg']} is not adjacent to the estuary.")
    return adjacency

# Function to find the downstream polygon
def find_downstream_polygon(river_seg, polygons):
    print(f"Finding downstream polygon for RiverSeg: {river_seg}")
    _, downstream_id = parse_riverseg(river_seg)
    downstream_polygon = polygons[polygons['RiverSeg'].str.endswith(downstream_id)]
    if not downstream_polygon.empty:
        print(f"Found downstream polygon for RiverSeg: {river_seg}")
    else:
        print(f"No downstream polygon found for RiverSeg: {river_seg}")
    return downstream_polygon.geometry.iloc[0] if not downstream_polygon.empty else None

# Function to snap an outlet point to the best intersection point
def snap_to_downstream(point, river_seg, polygons, intersection_points):
    print(f"Processing RiverSeg: {river_seg}")
    # Filter for the polygon with the same RiverSeg
    matching_polygon = polygons[polygons['RiverSeg'] == river_seg]
    if matching_polygon.empty:
        print(f"No matching polygon found for RiverSeg: {river_seg}. Returning original point.")
        return point  # No matching polygon, return original point

    # Check if the polygon is adjacent to the estuary
    if is_adjacent_to_estuary(matching_polygon.iloc[0], estuary):
        print(f"Skipping snapping for RiverSeg {river_seg} as it is adjacent to the estuary.")
        return point  # Skip snapping for polygons adjacent to the estuary

    # Filter intersection points that touch the matching polygon
    valid_targets = intersection_points[intersection_points.intersects(matching_polygon.geometry.iloc[0])]
    if valid_targets.empty:
        print(f"No valid intersection points found for RiverSeg: {river_seg}. Returning original point.")
        return point  # No valid targets, return original point

    # Find the downstream polygon
    downstream_polygon = find_downstream_polygon(river_seg, polygons)
    if downstream_polygon is None:
        print(f"No downstream polygon found for RiverSeg: {river_seg}. Snapping to nearest valid intersection point.")
        # Snap to the nearest intersection point touching the polygon
        nearest_geom = nearest_points(point, valid_targets.unary_union)[1]
        return nearest_geom

    # Find the intersection point closest to the downstream polygon
    closest_point = None
    min_distance = float('inf')
    for target in valid_targets.geometry:
        distance = target.distance(downstream_polygon)
        if distance < min_distance:
            min_distance = distance
            closest_point = target

    if closest_point:
        print(f"Snapped RiverSeg {river_seg} to intersection point closest to downstream polygon.")
    else:
        print(f"No intersection point found near downstream polygon for RiverSeg: {river_seg}. Returning original point.")
    return closest_point if closest_point else point

# Apply the snapping function
print("Starting snapping process...")
points_to_snap['geometry'] = points_to_snap.apply(
    lambda row: snap_to_downstream(
        row.geometry,
        row['RiverSeg'],
        polygons,
        intersection_points
    ), axis=1)

# Save the snapped points
print("Saving snapped points...")
points_to_snap.to_file(pathSnappedOutletPoints)
print("Snapped outlet points have been saved.")
