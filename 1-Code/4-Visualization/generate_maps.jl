# File name: generate_maps.jl
# Megan Harris

using DataFrames, Shapefile, GeoInterface, CairoMakie, ColorSchemes, Colors
using ZipFile   # lets Shapefile.Table read the zipped Chesapeake shoreline file
using StatsBase, Printf, Statistics
import CairoMakie as CM

#  Define output folder
# Revision runs write to a separate folder so the submitted-manuscript figures in
# 0-Data/3-FinalData/nutrient_maps are not overwritten. Set MAP_OUTDIR before include() to change.
if !@isdefined(MAP_OUTDIR); MAP_OUTDIR = joinpath(pwd(), "0-Data/3-FinalData/nutrient_maps_revision"); end
outdir = MAP_OUTDIR
mkpath(outdir)
println("Maps will be written to: ", outdir)

# Define colors for nitrogen and phosphorous
# Nitrogen Hex color #FF4600
# Phosphorus Hex color #00A078
const N_FILL   = RGBAf(255/255, 70/255, 0/255, 0.6) 
const N_STROKE = RGBAf(255/255, 70/255, 0/255, 0.9) 
const P_FILL   = RGBAf(0/255, 160/255, 120/255, 0.6) 
const P_STROKE = RGBAf(0/255, 160/255, 120/255, 0.9)

# Continuous colormaps for nitrogen and phosphorus
# Light tint of the color to full saturation
const cmap_N_custom = ColorScheme([
    RGBA(1.0, 0.92, 0.85, 1.0),   # pale tint (soft peach)
    RGBA(1.0, 0.55, 0.25, 1.0),   # mid-tone orange
    RGB(N_FILL.r, N_FILL.g, N_FILL.b)  # deep vivid red-orange
])

const cmap_P_custom = ColorScheme([
    RGBA(0.85, 1.0, 0.95, 1.0),   # pale mint
    RGBA(0.45, 0.85, 0.75, 1.0),  # mid-tone teal
    RGB(P_FILL.r, P_FILL.g, P_FILL.b)  # rich teal-green
])

# Simple selector for scripts
choose_cmap(nutrient::Symbol) = nutrient === :N ? cmap_N_custom : cmap_P_custom

# Which maps to make. Default: only Fig. A. For others, set before include(), e.g.
#   MAPS = [:figA, :transport]      or      MAPS = [:figA, :accumulation, :sector, :transport]
if !@isdefined(MAPS); MAPS = [:figA]; end
println("Maps to make: ", MAPS)

include("pre_process_maps.jl")                       # data for all maps (always)
include("accumulation_maps.jl")                      # helpers always; figures if :accumulation
:sector in MAPS && include("sector_maps.jl")
include("transport_maps.jl")                         # helpers always; figures if :transport
:figA in MAPS && include("network_retention_map.jl") # Fig. A (revision): network flows over land retention