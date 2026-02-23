# File name: generate_maps.jl
# Megan Harris

using DataFrames, Shapefile, GeoInterface, CairoMakie, ColorSchemes, Colors
using StatsBase, Printf, Statistics
import CairoMakie as CM

#  Define output folder
outdir = joinpath(pwd(), "0-Data/3-FinalData/nutrient_maps")

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

include("pre_process_maps.jl")
include("accumulation_maps.jl")
include("sector_maps.jl")
include("transport_maps.jl")