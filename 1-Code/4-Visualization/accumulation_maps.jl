# File name: accumulation_maps.jl
# Megan Harris

# Makie.set_theme!(fonts = (; regular="Helvetica"))
Makie.set_theme!(
    fonts = (; regular = "Helvetica"),
    fontsize = 26
)

# --- helpers to parse buffer names and build coordinates lookups ---

_extract_seg_token(s::AbstractString) = begin
    # Handle "Land Segment" format: extract everything after "Land Segment "
    if startswith(s, "Land Segment ")
        return replace(s, "Land Segment " => "")
    # Handle "Outlet" format: extract everything after "Outlet "
    elseif startswith(s, "Outlet ")
        return replace(s, "Outlet " => "")
    else
        return nothing
    end
end

_buffer_kind_and_seg(bname::AbstractString) = begin
    if startswith(bname, "Land Segment ")
        return (:land, _extract_seg_token(bname))
    elseif startswith(bname, "Outlet ")
        return (:outlet, _extract_seg_token(bname))
    elseif startswith(bname, "Estuary ")
        return (:estuary, _extract_seg_token(bname))
    else
        return (:other, nothing)
    end
end

function build_seg_xy_map(tbl::Shapefile.Table)
    seg_id_col = hasproperty(tbl, :LndRvrSegN) ? :LndRvrSegN :
                 (hasproperty(tbl, :LndRvrSeg)  ? :LndRvrSeg  :
                  error("Segments file missing :LndRvrSegN and :LndRvrSeg"))
    xy = Dict{String, Tuple{Float64,Float64}}()
    for rec in tbl
        sid_raw = getproperty(rec, seg_id_col)
        x = getproperty(rec, :x_LRseg)
        y = getproperty(rec, :y_LRseg)
        sid_raw === nothing && continue
        xy[String(sid_raw)] = (Float64(x), Float64(y))
    end
    return xy
end

# Robust (x,y) extractor for Point-ish geometries
function _xy_from_geom(geom)
    # Try GeoInterface accessors first (fast path)
    try
        return (Float64(GeoInterface.x(geom)), Float64(GeoInterface.y(geom)))
    catch
        # fall through
    end
    coords = GeoInterface.coordinates(geom)
    if coords isa Tuple
        return (Float64(coords[1]), Float64(coords[2]))
    elseif coords isa AbstractVector
        if !isempty(coords)
            c1 = coords[1]
            if c1 isa Tuple
                return (Float64(c1[1]), Float64(c1[2]))
            elseif length(coords) >= 2 && eltype(coords) <: Real
                return (Float64(coords[1]), Float64(coords[2]))
            end
        end
    end
    return (NaN, NaN)  # last-resort fallback
end

# Fixed outlet coordinates function - add RiverSeg to candidate columns
function build_outlet_xy_map(tbl::Shapefile.Table)
    # Add RiverSeg to the candidate columns list
    cand_cols = Symbol[:RiverSeg, :LndRvrSeg, :LndRvrSegN, :Seg, :segment, :id, :SEGID, :SEG]
    idcol = nothing
    for c in cand_cols
        if hasproperty(tbl, c)
            idcol = c; break
        end
    end
    has_id = idcol !== nothing

    xy = Dict{String, Tuple{Float64,Float64}}()
    for rec in tbl
        geom = GeoInterface.geometry(rec)
        (x, y) = _xy_from_geom(geom)
        if has_id
            sid_raw = getproperty(rec, idcol)
            if !ismissing(sid_raw) && sid_raw !== nothing
                xy[String(sid_raw)] = (x, y)
            end
        end
    end
    # println("build_outlet_xy_map: using column $idcol, found $(length(xy)) outlets")
    return xy
end

seg_xy = build_seg_xy_map(seg_tbl)
out_xy = build_outlet_xy_map(out_pts)

# Fixed size scaling function - the issue was missing explicit return
function size_scale_sqrt(v::AbstractVector{<:Real}; smin::Float64=3.0, smax::Float64=26.0)
    isempty(v) && return Float64[]
    vals  = max.(0.0, Float64.(v))
    tvals = sqrt.(vals)
    lo, hi = extrema(tvals)

    # handle degenerate range and avoid any eps() shadowing
    if hi <= lo
        return fill(smin, length(v))
    end
    tiny = Base.eps(Float64)  # <- never shadowed
    den  = max(hi - lo, tiny)

    return smin .+ (tvals .- lo) .* (smax - smin) ./ den
end

function add_size_legend!(
    ax::CM.Axis, vmax::Float64;
    title_str::String = "Size ∝ magnitude",
    nsym::Int = 4, smin::Float64 = 3.0, smax::Float64 = 26.0,
    markercolor = :gray, pos = :lt
)
    (isnan(vmax) || vmax <= 0) && return
    vals   = collect(range(0.25, 1.0; length=nsym)) .* vmax
    sizes  = size_scale_sqrt(vals; smin=smin, smax=smax)
    hs     = [CM.scatter!(ax, [NaN], [NaN]; markersize=ms, color=markercolor, strokewidth=0) for ms in sizes]
    labels = [string(round(v; digits=2)) for v in vals]
    
    # Create legend directly with axislegend and title
    CM.axislegend(ax, hs, labels, title_str; 
                  position = pos,
                  framevisible = true,
                  margin = (10, 10, 10, 10))
end

# Enhanced QB collection function with better debugging
# Enhanced QB collection function with better debugging
function collect_QB_points_enhanced(nutrient::Symbol; scale_to_millions::Bool=true)
    QB_opt    = cap_results.QB
    rows      = nutrient == :N ? (1:myLFES.buffer.number) : ((myLFES.buffer.number+1):(2*myLFES.buffer.number))

    pts_x = Float64[]; pts_y = Float64[]; mags = Float64[]; kinds = Symbol[]
    missed = 0
    matched_land = 0; matched_outlet = 0; matched_estuary = 0

    outlet_debug_count = 0
    
    for (k, r) in enumerate(rows)
        bname = myLFES.buffer.name[k]
        (kind, segtok) = _buffer_kind_and_seg(bname)
        mag = Float64(QB_opt[r, 2])
        
        # Convert to millions if requested
        if scale_to_millions
            mag = mag / 1e6
        end
        
        if kind == :land
            if segtok !== nothing && haskey(seg_xy, segtok)
                (x,y) = seg_xy[segtok]
                push!(pts_x, x); push!(pts_y, y); push!(mags, mag); push!(kinds, :land)
                matched_land += 1
            else
                missed += 1
            end
        elseif kind == :outlet
            outlet_debug_count += 1
            if segtok !== nothing && haskey(out_xy, segtok)
                (x,y) = out_xy[segtok]
                push!(pts_x, x); push!(pts_y, y); push!(mags, mag); push!(kinds, :outlet)
                matched_outlet += 1
            else
                missed += 1
            end
        elseif kind == :estuary
            matched_estuary += 1
        else
            missed += 1
        end
    end
    
    return (x=pts_x, y=pts_y, m=mags, kind=kinds)
end

# N map with million pounds
datN   = collect_QB_points_enhanced(:N; scale_to_millions=true)
sizesN = size_scale_sqrt(datN.m; smin=3.0, smax=26.0)
vmaxN  = isempty(datN.m) ? 0.0 : maximum(max.(datN.m, 0.0))

figN_QB = CM.Figure(size=(800, 1000))
axN_QB  = CM.Axis(figN_QB[1,1], xlabel="Easting (m)", ylabel="Northing (m)",
                  title="Nitrogen Losses and Accumulation in Buffers",
                  aspect=DataAspect())
if estuary_tbl !== nothing
    est_color = RGBAf(0.75, 0.75, 0.75, 0.4)
    CM.poly!(axN_QB, estuary_tbl; color=est_color, strokecolor=est_color, strokewidth=0.5)
end

land_maskN   = [k == :land for k in datN.kind]
outlet_maskN = .!land_maskN
if any(land_maskN)
    CM.scatter!(axN_QB, datN.x[land_maskN], datN.y[land_maskN];
        markersize=sizesN[land_maskN], color=N_FILL, strokewidth=0)
end
if any(outlet_maskN)
    CM.scatter!(axN_QB, datN.x[outlet_maskN], datN.y[outlet_maskN];
        markersize=sizesN[outlet_maskN], color=:transparent, strokecolor=N_STROKE, strokewidth=1.0)
end
add_size_legend!(axN_QB, vmaxN; title_str="Mass of Nitrogen\n(million lbs)", smin=3.0, smax=26.0,
                 markercolor=N_FILL, pos=:lt)

# P map with million pounds
datP   = collect_QB_points_enhanced(:P; scale_to_millions=true)
sizesP = size_scale_sqrt(datP.m; smin=3.0, smax=26.0)
vmaxP  = isempty(datP.m) ? 0.0 : maximum(max.(datP.m, 0.0))

figP_QB = CM.Figure(size=(800, 1000))
axP_QB  = CM.Axis(figP_QB[1,1], xlabel="Easting (m)", ylabel="Northing (m)",
                  title="Phosphorus Losses and Accumulation in Buffers",
                  aspect=DataAspect())
if estuary_tbl !== nothing
    est_color = RGBAf(0.75, 0.75, 0.75, 0.4)
    CM.poly!(axP_QB, estuary_tbl; color=est_color, strokecolor=est_color, strokewidth=0.5)
end
land_maskP   = [k == :land for k in datP.kind]
outlet_maskP = .!land_maskP
if any(land_maskP)
    CM.scatter!(axP_QB, datP.x[land_maskP], datP.y[land_maskP];
        markersize=sizesP[land_maskP], color=P_FILL, strokewidth=0)
end
if any(outlet_maskP)
    CM.scatter!(axP_QB, datP.x[outlet_maskP], datP.y[outlet_maskP];
        markersize=sizesP[outlet_maskP], color=:transparent, strokecolor=P_STROKE, strokewidth=1.0)
end
add_size_legend!(axP_QB, vmaxP; title_str="Mass of Phosphorus\n(million lbs)", smin=3.0, smax=26.0,
                 markercolor=P_FILL, pos=:lt)

# Save accumulation = QB bubble maps
mkpath(outdir)
CM.save(joinpath(outdir, "map_accumulation_N.png"), figN_QB)
CM.save(joinpath(outdir, "map_accumulation_P.png"), figP_QB)
# println("Wrote: map_accumulation_N.png, map_accumulation_P.png")

# Combined figure with both maps side-by-side
figBoth_QB = CM.Figure(size=(1600, 1000))

# Nitrogen map (left side)
axN_both = CM.Axis(figBoth_QB[1,1], xlabel="Easting (m)", ylabel="Northing (m)",
                   title="Nitrogen Losses and Accumulation in Buffers",
                   aspect=DataAspect())
if estuary_tbl !== nothing
    est_color = RGBAf(0.75, 0.75, 0.75, 0.4)
    CM.poly!(axN_both, estuary_tbl; color=est_color, strokecolor=est_color, strokewidth=0.5)
end
land_maskN_both = [k == :land for k in datN.kind]
outlet_maskN_both = .!land_maskN_both
if any(land_maskN_both)
    CM.scatter!(axN_both, datN.x[land_maskN_both], datN.y[land_maskN_both];
        markersize=sizesN[land_maskN_both], color=N_FILL, strokewidth=0)
end
if any(outlet_maskN_both)
    CM.scatter!(axN_both, datN.x[outlet_maskN_both], datN.y[outlet_maskN_both];
        markersize=sizesN[outlet_maskN_both], color=:transparent, strokecolor=N_STROKE, strokewidth=1.0)
end
add_size_legend!(axN_both, vmaxN; title_str="Mass of Nitrogen\n(million lbs)", smin=3.0, smax=26.0,
                 markercolor=N_FILL, pos=:lt)

# Phosphorus map (right side)
axP_both = CM.Axis(figBoth_QB[1,2], xlabel="Easting (m)", ylabel="Northing (m)",
                   title="Phosphorus Losses and Accumulation in Buffers",
                   aspect=DataAspect())
if estuary_tbl !== nothing
    est_color = RGBAf(0.75, 0.75, 0.75, 0.4)
    CM.poly!(axP_both, estuary_tbl; color=est_color, strokecolor=est_color, strokewidth=0.5)
end
land_maskP_both = [k == :land for k in datP.kind]
outlet_maskP_both = .!land_maskP_both
if any(land_maskP_both)
    CM.scatter!(axP_both, datP.x[land_maskP_both], datP.y[land_maskP_both];
        markersize=sizesP[land_maskP_both], color=P_FILL, strokewidth=0)
end
if any(outlet_maskP_both)
    CM.scatter!(axP_both, datP.x[outlet_maskP_both], datP.y[outlet_maskP_both];
        markersize=sizesP[outlet_maskP_both], color=:transparent, strokecolor=P_STROKE, strokewidth=1.0)
end
add_size_legend!(axP_both, vmaxP; title_str="Mass of Phosphorus\n(million lbs)", smin=3.0, smax=26.0,
                 markercolor=P_FILL, pos=:lt)

# Adjust gaps and save
CM.colgap!(figBoth_QB.layout, 0)
CM.save(joinpath(outdir, "map_accumulation_both.png"), figBoth_QB)
println("Wrote: map_accumulation_N.png, map_accumulation_P.png, map_accumulation_both.png")