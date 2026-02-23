import geopandas as gpd

def calculate_and_add_centroids(land_river_seg_path, output_path):
    # Load the land-river segment shapefile
    land_river_gdf = gpd.read_file(land_river_seg_path)
    print(land_river_gdf.columns)

    # Debugging: Check the columns in the GeoDataFrame
    print("Columns in the shapefile:", land_river_gdf.columns)

    # Ensure the 'RiverSegN' column exists
    if 'RiverSegN' not in land_river_gdf.columns:
        raise ValueError("The 'RiverSegN' column is missing from the GeoDataFrame.")

    # Ensure CRS is consistent
    land_river_gdf = land_river_gdf.to_crs(land_river_gdf.crs)

    # Calculate centroids for river segments (grouped by "RiverSegN")
    river_seg_centroids = land_river_gdf.dissolve(by="RiverSegN").centroid
    river_seg_centroids = river_seg_centroids.rename("riverSeg_centroid")
    land_river_gdf["x_riverSeg"] = land_river_gdf["RiverSegN"].map(river_seg_centroids.x)
    land_river_gdf["y_riverSeg"] = land_river_gdf["RiverSegN"].map(river_seg_centroids.y)

    # Calculate centroids for counties (grouped by "FIPS_NHL")
    if 'FIPS_NHL' not in land_river_gdf.columns:
        raise ValueError("The 'FIPS_NHL' column is missing from the GeoDataFrame.")

    county_centroids = land_river_gdf.dissolve(by="FIPS_NHL").centroid
    county_centroids = county_centroids.rename("county_centroid")
    land_river_gdf["x_county"] = land_river_gdf["FIPS_NHL"].map(county_centroids.x)
    land_river_gdf["y_county"] = land_river_gdf["FIPS_NHL"].map(county_centroids.y)

    # Calculate centroids for land-river segments (unique polygons)
    land_river_gdf["x_LRseg"] = land_river_gdf.geometry.centroid.x
    land_river_gdf["y_LRseg"] = land_river_gdf.geometry.centroid.y

    # Save the updated GeoDataFrame to a new shapefile
    land_river_gdf.to_file(output_path, driver="ESRI Shapefile")

    print(f"Centroids added and saved to {output_path}")

# File paths
land_river_seg_path = "0-Data/1-RawData/0-GIS/QGIS/RenamedPointsPolygons/RenamedLRSegments/RenamedLRSegments.shp"
output_path = "0-Data/1-RawData/0-GIS/QGIS/RenamedPointsPolygons/RenamedPolygons/CentroidsSavedLRsegments.shp"

# Run the function
calculate_and_add_centroids(land_river_seg_path, output_path)