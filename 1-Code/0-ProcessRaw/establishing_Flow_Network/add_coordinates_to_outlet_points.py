import geopandas as gpd
import os

def add_coordinates_to_outlet_points(outlet_points_path, output_path):
    # Load the outlet points shapefile
    print("Loading outlet points shapefile...")
    outlet_points_gdf = gpd.read_file(outlet_points_path)

    # Ensure the geometries are points
    if not outlet_points_gdf.geometry.geom_type.isin(["Point"]).all():
        raise ValueError("The geometries in the shapefile are not all points.")

    # Add x and y coordinates to the attribute table
    print("Adding x and y coordinates...")
    outlet_points_gdf['x_coord'] = outlet_points_gdf.geometry.x
    outlet_points_gdf['y_coord'] = outlet_points_gdf.geometry.y

    # Ensure the output directory exists
    output_dir = os.path.dirname(output_path)
    if not os.path.exists(output_dir):
        print(f"Creating output directory: {output_dir}")
        os.makedirs(output_dir)

    # Save the updated shapefile
    print("Saving updated outlet points shapefile...")
    outlet_points_gdf.to_file(output_path, driver="ESRI Shapefile")
    print(f"Updated outlet points saved to {output_path}")

# File paths
outlet_points_path = "0-Data/1-RawData/0-GIS/QGIS/RenamedPointsPolygons/RenamedPoints/RenamedPoints.shp"
output_path = "0-Data/1-RawData/0-GIS/QGIS/RenamedPointsPolygons/OutletPointsWithCoordinates/OutletPointsWithCoordinates.shp"

# Run the function
add_coordinates_to_outlet_points(outlet_points_path, output_path)