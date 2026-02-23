# Title: Calculate Flow Accumulation
# Author: Megan Harris
# Institution: Virginia Tech
# Copyright: 2025
# Developed with Python 3.x

import psutil
import time
from pysheds.grid import Grid
import numpy as np

# Function to monitor memory usage
def check_memory():
    process = psutil.Process()
    mem_info = process.memory_info()
    print(f"Current Memory Usage: {mem_info.rss / 1e6} MB")

# Paths to DEM and flow accumulation files
dem_path = "0-Data/1-RawData/0-GIS/QGIS/DEM/output_SRTMGL1.tif"
acc_path = '0-Data/1-RawData/0-GIS/QGIS/DEM/processed/flow_accumulation.tif'

# Load the DEM
print("Reading DEM...")
grid = Grid.from_raster(dem_path, nodata=0)
check_memory()  # Check memory usage

dem = grid.read_raster(dem_path, nodata=0)
check_memory()

# Condition the DEM data
print("Filling pits...")
pit_filled_dem = grid.fill_pits(dem)
check_memory()

print("Filling depressions...")
flooded_dem = grid.fill_depressions(pit_filled_dem)
check_memory()

print("Resolving flats...")
conditioned_dem = grid.resolve_flats(flooded_dem)
check_memory()

# Compute flow directions
print("Computing flow directions...")
flowdir = grid.flowdir(conditioned_dem)
check_memory()

# Compute flow accumulation
print("Calculating flow accumulation...")
acc = grid.accumulation(flowdir)
check_memory()

# Save the accumulation raster
print("Saving accumulation to tiff file...")
grid.to_raster(acc, acc_path)
check_memory()

print("Process complete.")
