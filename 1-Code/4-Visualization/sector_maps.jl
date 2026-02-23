# File name: sector_maps.jl
# Megan Harris

seg_id_col = hasproperty(seg_tbl, :LndRvrSegN) ? :LndRvrSegN :
             (hasproperty(seg_tbl, :LndRvrSeg) ? :LndRvrSeg :
              error("Segments file missing :LndRvrSegN and :LndRvrSeg"))

_extract_seg_id(s::AbstractString) = begin
    m = match(r"(\d+)$", s)
    m === nothing ? s : m.captures[1]
end

function collect_accept_by_segment_fromU()
    rows = NamedTuple[]
    for r in 1:length(myLFES.physicalResource.name)
        resname = String(myLFES.physicalResource.name[r])
        startswith(resname, "Land Segment ") || continue
        segid = replace(resname, "Land Segment " => "")

        agN = 0.0; agP = 0.0; devN = 0.0; devP = 0.0
        for j in 1:myLFES.systemConcept.DOFS
            myLFES.systemConcept.idxResource[j] == r || continue
            p = myLFES.systemConcept.idxProcess[j]
            (1 <= p <= 4) || continue
            uval = cap_results.U[j]
            if p == 1; agN += uval
            elseif p == 2; agP += uval
            elseif p == 3; devN += uval
            else; devP += uval
            end
        end
        push!(rows, (SegID=segid, AgN=agN, DevN=devN, AgP=agP, DevP=devP))
    end
    df = DataFrame(rows)
    isempty(df) && return DataFrame(SegID=String[], AgN=Float64[], DevN=Float64[], AgP=Float64[], DevP=Float64[])
    combine(groupby(df, :SegID),
            :AgN => sum => :AgN, :DevN => sum => :DevN,
            :AgP => sum => :AgP, :DevP => sum => :DevP)
end

accept_seg2 = collect_accept_by_segment_fromU()

poly_rows = NamedTuple[]
for rec in seg_tbl
    geom = GeoInterface.geometry(rec)
    idv  = getproperty(rec, seg_id_col)
    push!(poly_rows, (SegID = String(idv), geometry = geom))
end
poly_df = DataFrame(poly_rows)
polygon_data = leftjoin(poly_df, accept_seg2, on=:SegID)

polygon_data[!, :N_total] = coalesce.(polygon_data.AgN, 0.0) .+ coalesce.(polygon_data.DevN, 0.0)
polygon_data[!, :P_total] = coalesce.(polygon_data.AgP, 0.0) .+ coalesce.(polygon_data.DevP, 0.0)
polygon_data[!, :N_ag_share] = [n_tot > 0 ? agn / n_tot : 0.0 
                                for (agn, n_tot) in zip(coalesce.(polygon_data.AgN, 0.0), polygon_data.N_total)]
polygon_data[!, :P_ag_share] = [p_tot > 0 ? agp / p_tot : 0.0 
                                for (agp, p_tot) in zip(coalesce.(polygon_data.AgP, 0.0), polygon_data.P_total)]

CM.set_theme!(
    fonts = (; regular = "Helvetica"),
    fontsize = 26
)

# Nitrogen map
figNsec = CM.Figure(size=(800, 1000))
axNsec = CM.Axis(figNsec[1,1],
    xlabel="Easting (m)", ylabel="Northing (m)",
    title="Sector Share of Applied Nitrogen",
    aspect=DataAspect()
)
pltNsec = CM.poly!(axNsec, polygon_data.geometry;
    color = polygon_data.N_ag_share,
    colormap = ColorSchemes.turbo,
    strokecolor = :black, strokewidth = 0.25
)

# Colorbar in separate grid cell
CM.Colorbar(figNsec[1,2], pltNsec;
    label = "Sector Share (0 = Developed, 1 = Agricultural)",
    width = 15,
    labelpadding = 6,
    ticklabelpad = 2
)

# Use NEGATIVE gap to move colorbar closer (or even overlap)
CM.colgap!(figNsec.layout, 0)  # Try -10, -20, -30, etc.
CM.rowgap!(figNsec.layout, 0)

# CM.hidedecorations!(axNsec, ticks=false, grid=false)
CM.save(joinpath(outdir, "map_accept_sector_share_N.png"), figNsec)


# Phosphorus map (note: you had variable name errors - fixed below)
figPsec = CM.Figure(size=(800, 1000))
axPsec = CM.Axis(figPsec[1,1],  # Changed from axNsec
    xlabel="Easting (m)", ylabel="Northing (m)",
    title="Sector Share of Applied Phosphorus",  # Changed title
    aspect=DataAspect()
)
pltPsec = CM.poly!(axPsec, polygon_data.geometry;  # Changed from axNsec and pltNsec
    color = polygon_data.P_ag_share,  # Changed from N_ag_share
    colormap = ColorSchemes.turbo,
    strokecolor = :black, strokewidth = 0.25
)

# Colorbar in separate grid cell
CM.Colorbar(figPsec[1,2], pltPsec;  # Changed from pltNsec
    label = "Sector Share (0 = Developed, 1 = Agricultural)",
    width = 15,
    labelpadding = 6,
    ticklabelpad = 2
)

# Use NEGATIVE gap
CM.colgap!(figPsec.layout, 0)
CM.rowgap!(figPsec.layout, 0)

# CM.hidedecorations!(axPsec, ticks=false, grid=false)
CM.save(joinpath(outdir, "map_accept_sector_share_P.png"), figPsec)  

# Combined figure with both maps side-by-side and colorbar in middle
figBoth = CM.Figure(size=(1600, 1000))

# Nitrogen map (left side)
axNsec = CM.Axis(figBoth[1,1],
    xlabel="Easting (m)", ylabel="Northing (m)",
    title="Sector Share of Applied Nitrogen",
    aspect=DataAspect()
)

pltNsec = CM.poly!(axNsec, polygon_data.geometry;
    color = polygon_data.N_ag_share,
    colormap = ColorSchemes.turbo,
    strokecolor = :black, strokewidth = 0.25
)
# CM.hidedecorations!(axNsec, ticks=false, grid=false)

# Colorbar in the middle
CM.Colorbar(figBoth[1, 2], pltNsec;
    label = "Sector Share (0 = Developed, 1 = Agricultural)",
    width = 15,
    labelpadding = 6,
    ticklabelpad = 2
)

# Phosphorus map (right side)
axPsec = CM.Axis(figBoth[1,3],
    xlabel="Easting (m)", ylabel="Northing (m)",
    title="Sector Share of Applied Phosphorus",
    aspect=DataAspect()
)

pltPsec = CM.poly!(axPsec, polygon_data.geometry;
    color = polygon_data.P_ag_share,
    colormap = ColorSchemes.turbo,
    strokecolor = :black, strokewidth = 0.25
)
# CM.hidedecorations!(axPsec, ticks=false, grid=false)

# Adjust gaps
CM.colgap!(figBoth.layout, 20)
CM.rowgap!(figBoth.layout, 0)

CM.save(joinpath(outdir, "map_accept_sector_share_both.png"), figBoth)
println("Wrote: map_accept_sector_share_N.png, map_accept_sector_share_P.png, map_accept_sector_share_both.png")