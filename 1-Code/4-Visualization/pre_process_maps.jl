# File Name: pre_process_maps.jl
# Megan Harris

### 1) Load shapefiles ###
seg_tbl = Shapefile.Table(segments_shapefile) 
out_pts = Shapefile.Table(outlet_points_shapefile)
out_lines = Shapefile.Table(outlet_lines_shapefile)
out_lines_est = Shapefile.Table(outlet_lines_estuary_shapefile)
estuary_tbl = Shapefile.Table(estuary_shapefile_zip)

###  2) Field introspection ###
seg_id_col = :LndRvrSeg
hasproperty(seg_tbl, seg_id_col) || error("Segments file missing $(seg_id_col) column")
line_from_col = :from
line_to_col   = :to
for c in (line_from_col, line_to_col)
    hasproperty(out_lines, c) || error("Outlet lines missing $(c) column")
    hasproperty(out_lines_est, c) || error("Outlet→estuary lines missing $(c) column")
end

### 3) Prepare result tables (kept for later maps that use U) ###

# 3a) Land/river segment centroids colored by "accumulation" (land→stream) — used elsewhere
function collect_land2stream_by_segment()
    rows = Vector{NamedTuple}()
    for (j, tp) in cap_to_transportProcess
        (seg, kind, _) = origin_info(tp)
        seg === nothing && continue
        kind == :land || continue
        nut = cap_nutrient(j)   # :N or :P
        push!(rows, (LandRiverSegment = seg, nutrient = Symbol(nut), flow=cap_results.U[j]))
    end
    df = DataFrame(rows)
    combine(groupby(df, [:LandRiverSegment, :nutrient]), :flow => sum => :flow_sum)
end

land2stream = collect_land2stream_by_segment()
seg_metric = unstack(land2stream, :LandRiverSegment, :nutrient, :flow_sum; fill=0.0)
rename!(seg_metric, Dict(:N => :N_value, :P => :P_value))

# 3b) Accept-process sector totals by segment (from U), used in sector maps
function segment_for_capability(j::Int)
    r = myLFES.systemConcept.idxResource[j]
    if haskey(resourceID_to_transformResource, r)
        tr_idx = resourceID_to_transformResource[r]
        return String(myLFES.transformationResource.RiverSegN[tr_idx])
    else
        return nothing
    end
end

function collect_accept_by_segment_sector()
    rows = NamedTuple[]
    for j in 1:myLFES.systemConcept.DOFS
        p = myLFES.systemConcept.idxProcess[j]
        (p >= 1 && p <= 4) || continue  # accept processes only
        seg = segment_for_capability(j)
        seg === nothing && continue

        if p == 1
            sector, nut = "Agriculture", :N
        elseif p == 2
            sector, nut = "Agriculture", :P
        elseif p == 3
            sector, nut = "Developed", :N
        else # p == 4
            sector, nut = "Developed", :P
        end
        push!(rows, (LandRiverSegment=seg, sector=sector, nutrient=nut, U=cap_results.U[j]))
    end
    df = DataFrame(rows)
    isempty(df) && return df

    df2 = combine(groupby(df, [:LandRiverSegment, :nutrient, :sector]), :U => sum => :U)

    dfN = filter(:nutrient => ==(:N), df2)
    dfNw = unstack(dfN, :LandRiverSegment, :sector, :U; allowduplicates=true)
    rename!(dfNw, Dict("Agriculture" => :AgN, "Developed" => :DevN))
    dfNw.AgN  = coalesce.(dfNw.AgN, 0.0)
    dfNw.DevN = coalesce.(dfNw.DevN, 0.0)

    dfP = filter(:nutrient => ==(:P), df2)
    dfPw = unstack(dfP, :LandRiverSegment, :sector, :U; allowduplicates=true)
    rename!(dfPw, Dict("Agriculture" => :AgP, "Developed" => :DevP))
    dfPw.AgP  = coalesce.(dfPw.AgP, 0.0)
    dfPw.DevP = coalesce.(dfPw.DevP, 0.0)

    segs = unique(vcat(String.(dfNw.LandRiverSegment), String.(dfPw.LandRiverSegment)))
    base = DataFrame(LandRiverSegment = segs)
    leftjoin!(base, dfNw, on=:LandRiverSegment)
    leftjoin!(base, dfPw, on=:LandRiverSegment)

    for col in [:AgN, :DevN, :AgP, :DevP]
        hasproperty(base, col) || (base[!, col] = zeros(nrow(base)))
    end

    base[!, :N_total]    = base.AgN .+ base.DevN
    base[!, :P_total]    = base.AgP .+ base.DevP
    base[!, :N_ag_share] = [n_tot > 0 ? ag_n / n_tot : 0.0 for (n_tot, ag_n) in zip(base.N_total, base.AgN)]
    base[!, :P_ag_share] = [p_tot > 0 ? ag_p / p_tot : 0.0 for (p_tot, ag_p) in zip(base.P_total, base.AgP)]
    return base
end

accept_seg = collect_accept_by_segment_sector()

### 4) Join model data to shapes (for later maps) ############

function points_table_simple(tbl::Shapefile.Table, idcol::Symbol)
    rows = NamedTuple[]
    for rec in tbl
        id = getproperty(rec, idcol)
        x = rec.x_LRseg
        y = rec.y_LRseg
        push!(rows, (LandRiverSegment=String(id), x=x, y=y))
    end
    DataFrame(rows)
end

seg_pts  = points_table_simple(seg_tbl, seg_id_col)
ptdata   = leftjoin(seg_pts, seg_metric, on=:LandRiverSegment)
pt_accept = leftjoin(seg_pts, accept_seg, on=:LandRiverSegment)

function lines_table_to_df(tbl::Shapefile.Table, fromcol::Symbol, tocol::Symbol)
    rows = NamedTuple[]
    for rec in tbl
        geom = GeoInterface.geometry(rec)
        coords = GeoInterface.coordinates(geom)
        line = (length(coords) > 0 && isa(coords[1], Tuple)) ? coords :
               (length(coords) > 0 ? coords[1] : Tuple[])
        push!(rows, (FromSeg=String(getproperty(rec, fromcol)),
                     ToSeg=String(getproperty(rec, tocol)),
                     line=line))
    end
    DataFrame(rows)
end

line_df_regular = lines_table_to_df(out_lines, line_from_col, line_to_col)
line_df_estuary = lines_table_to_df(out_lines_est, line_from_col, line_to_col)
line_df_regular[!, :line_type] .= "outlet_to_outlet"
line_df_estuary[!, :line_type] .= "outlet_to_estuary"
line_df_all = vcat(line_df_regular, line_df_estuary)

est_pair_map = Dict{String,String}()
for r in eachrow(line_df_estuary)
    est_pair_map[r.FromSeg] = r.ToSeg
end

function collect_line_flows(est_pair_map::Dict{String,String})
    rows = NamedTuple[]
    for (j, tp) in cap_to_transportProcess
        seg_up, _, _ = origin_info(tp)
        seg_dn, _, _ = dest_info(tp)
        seg_up === nothing && continue
        to_seg::Union{String,Nothing} = seg_dn
        if to_seg === nothing
            to_seg = get(est_pair_map, seg_up, nothing)
        end
        to_seg === nothing && continue

        nut = cap_nutrient(j)
        push!(rows, (FromSeg=String(seg_up), ToSeg=String(to_seg),
                     nutrient=Symbol(nut), U=cap_results.U[j]))
    end
    df = DataFrame(rows)
    isempty(df) && return df
    combine(groupby(df, [:FromSeg, :ToSeg, :nutrient]), :U => sum => :U)
end

line_flows = collect_line_flows(est_pair_map)
line_map   = leftjoin(line_df_all, line_flows, on=[:FromSeg, :ToSeg])