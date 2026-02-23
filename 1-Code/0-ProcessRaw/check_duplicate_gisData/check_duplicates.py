import geopandas as gpd
from itertools import combinations

# Load your shapefile
path = "0-Data/1-RawData/0-GIS/QGIS/RenamedPointsPolygons/RenamedPolygons/CentroidsSavedLRsegments.shp"
gdf = gpd.read_file(path)

# Compare each pair of columns to see if they are identical row-by-row
identical_pairs = []
for col1, col2 in combinations(gdf.columns, 2):
    if gdf[col1].equals(gdf[col2]):
        identical_pairs.append((col1, col2))

# Report results
if identical_pairs:
    print("Columns with identical values in every row:")
    for c1, c2 in identical_pairs:
        print(f"  - {c1} == {c2}")
else:
    print("No column pairs have identical values for all rows.")