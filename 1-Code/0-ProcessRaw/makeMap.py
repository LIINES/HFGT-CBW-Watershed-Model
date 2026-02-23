import geopandas as gpd
import matplotlib.pyplot as plt

# Load the shapefile
gdf = gpd.read_file('0-Data/1-RawData/0-GIS/QGIS/P6Beta_v3_LRSegs_081516.zip')

# Create the plot
fig, ax = plt.subplots(1, 1, figsize=(10, 8))

# Plot with clearer boundaries
gdf.plot(column='ST', legend=True, cmap='tab20', ax=ax, edgecolor='black', linewidth=0.5)

# Get the current x-axis limits
xlim = ax.get_xlim()

# Extend the x-axis boundary to make space for the legend
ax.set_xlim([xlim[0], xlim[1] + (xlim[1] - xlim[0]) * 0.75])  # Add 30% of the x-range to the upper limit

# Customize the legend
legend = ax.get_legend()
legend.set_bbox_to_anchor((0.99, 0.54))  # Adjust the position
# legend.set_bbox_to_anchor((1.0, 0.76))  # Adjust the position
legend.set_frame_on(True)  # Optional: Keep or remove the frame as desired
legend.set_title("State")  # Add a title to the legend

# Adjust the layout to prevent overlap
plt.subplots_adjust(right=0.8)  # Adjust this value to make space for the legend

# Add title and axis labels
plt.title("Land-River Segments in the Chesapeake Bay")
plt.xlabel("Longitude")
plt.ylabel("Latitude")

# Show the plot
plt.show()
# Save the plot
# plt.savefig('0-Data/2-IntermediateData/GISFigs/Chesapeake_Bay_Watersheds.png', bbox_inches='tight')
