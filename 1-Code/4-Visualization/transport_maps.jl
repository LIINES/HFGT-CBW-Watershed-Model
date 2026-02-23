# File name: transport_maps.jl
# Megan Harris

_fmt(x) = @sprintf("%.2e", x)

function plot_transport_for(
    nutrient::Symbol,
    outpath::String;
    title_suffix::String = "",
    nutrientName::Dict{Symbol,String} = Dict(:N=>"Nitrogen", :P=>"Phosphorus"),
)
    df = filter(row -> !ismissing(row.U) && row.U > 0 && row.nutrient === nutrient, line_map)

    title_core = "Transport Flows (" * get(nutrientName, nutrient, String(nutrient)) * ")"
    title_str  = title_core * (isempty(title_suffix) ? "" : " — " * title_suffix)

    if nrow(df) == 0
        @warn "No transport lines to draw for nutrient = $nutrient"
        fig = CM.Figure(size=(800, 1000))
        CM.Axis(fig[1,1], xlabel="Easting (m)", ylabel="Northing (m)", title=title_str * " — no data")
        CM.save(outpath, fig); return fig
    end

    # --- figure extent from line geometry ---
    xs_all = Float64[]; ys_all = Float64[]
    for line in df.line
        isempty(line) && continue
        append!(xs_all, first.(line)); append!(ys_all, last.(line))
    end
    if estuary_tbl !== nothing
        function _collect_xy(coords)
            if coords isa Tuple
                push!(xs_all, coords[1]); push!(ys_all, coords[2])
            elseif coords isa AbstractArray
                for c in coords; _collect_xy(c); end
            end
        end
        for rec in estuary_tbl
            _collect_xy(GeoInterface.coordinates(GeoInterface.geometry(rec)))
        end
    end
    xmin, xmax = extrema(xs_all); ymin, ymax = extrema(ys_all)
    dx, dy = 0.03*(xmax - xmin), 0.03*(ymax - ymin)

    # --- log10 color scaling ---
    Uvals = collect(skipmissing(df.U))
    # guard against any zero-ish values
    Upos  = [u for u in Uvals if u > 0]
    Umin, Umax = minimum(Upos), maximum(Upos)

    # normalized log mapping in [0,1]
    lmin, lmax = log10(Umin), log10(Umax)
    lognorm(u) = (log10(u) - lmin) / (lmax - lmin)

    cmap = choose_cmap(nutrient)

    # ── draw - changed to 900x1000 like other maps
    fig = CM.Figure(size = (900, 1000))
    ax  = CM.Axis(fig[1,1];
        xlabel="Easting (m)", ylabel="Northing (m)",
        title=title_str, aspect=DataAspect()
    )
    CM.xlims!(ax, xmin - dx, xmax + dx); CM.ylims!(ax, ymin - dy, ymax + dy)

    if estuary_tbl !== nothing
        est_color = RGBAf(0.75, 0.75, 0.75, 0.4)
        CM.poly!(ax, estuary_tbl; color=est_color, strokecolor=est_color, strokewidth=0.5)
    end

    for row in eachrow(df)
        pts = row.line; isempty(pts) && continue
        xs = first.(pts); ys = last.(pts)
        t  = clamp(lognorm(row.U), 0, 1)
        c  = get(cmap, t)
        lw = (coalesce(row.line_type, "outlet_to_outlet") == "outlet_to_estuary") ? 3.8 : 2.8
        CM.lines!(ax, xs, ys; linewidth=lw, color=c)
    end

    # outlet markers (kept subtle)
    outpts_xy = [GeoInterface.coordinates(GeoInterface.geometry(r)) for r in out_pts]
    if !isempty(outpts_xy)
        xs = [p[1] for p in outpts_xy]; ys = [p[2] for p in outpts_xy]
        CM.scatter!(ax, xs, ys; markersize=2.5, color=(0,0,0,0.25))
    end

    # line-type legend
    h1 = CM.lines!(ax, [NaN, NaN], [NaN, NaN]; color=:gray, linewidth=2.8)
    h2 = CM.lines!(ax, [NaN, NaN], [NaN, NaN]; color=:gray, linewidth=3.8)
    # CM.axislegend(ax, [h1, h2], ["Outlet → Outlet", "Outlet → Estuary"]; position=:lb, framevisible=true)

    # tick values based on nutrient - mapped to normalized log space
    if nutrient == :N
        raw_ticks = [1e-8, 1e-6, 1e-4, 1e-2, 1e0, 1e2, 1e4, 1e6]
        ticklabs = ["10⁻⁸", "10⁻⁶", "10⁻⁴", "10⁻²", "10⁰", "10²", "10⁴", "10⁶"]
    else  # Phosphorus
        raw_ticks = [1e-8, 1e-6, 1e-4, 1e-2, 1e0, 1e2, 1e4]
        ticklabs = ["10⁻⁸", "10⁻⁶", "10⁻⁴", "10⁻²", "10⁰", "10²", "10⁴"]
    end
    
    # Filter ticks to only those within data range and map to actual values
    valid_ticks = filter(t -> Umin <= t <= Umax, raw_ticks)
    valid_labels = [ticklabs[i] for (i, t) in enumerate(raw_ticks) if Umin <= t <= Umax]

    CM.Colorbar(fig[1,2], 
        colormap=cmap, 
        limits=(Umin, Umax),
        ticks=(valid_ticks, valid_labels),
        vertical=true,
        width=15,
        label="log10[Flow Magnitude (lb/year)]",
        scale=log10  # This makes the colorbar logarithmic!
    )
    
    # Reduce gap between axis and colorbar
    CM.colgap!(fig.layout, 0)
    CM.rowgap!(fig.layout, 0)

    CM.save(outpath, fig)
    fig
end

# Combined side-by-side transport maps
function plot_transport_both(outdir::String)
    # Filter data for both nutrients
    dfN = filter(row -> !ismissing(row.U) && row.U > 0 && row.nutrient === :N, line_map)
    dfP = filter(row -> !ismissing(row.U) && row.U > 0 && row.nutrient === :P, line_map)
    
    if nrow(dfN) == 0 || nrow(dfP) == 0
        @warn "Insufficient data for combined transport map"
        return nothing
    end
    
    # --- figure extent from line geometry (same for both) ---
    xs_all = Float64[]; ys_all = Float64[]
    for line in vcat(dfN.line, dfP.line)
        isempty(line) && continue
        append!(xs_all, first.(line)); append!(ys_all, last.(line))
    end
    if estuary_tbl !== nothing
        function _collect_xy(coords)
            if coords isa Tuple
                push!(xs_all, coords[1]); push!(ys_all, coords[2])
            elseif coords isa AbstractArray
                for c in coords; _collect_xy(c); end
            end
        end
        for rec in estuary_tbl
            _collect_xy(GeoInterface.coordinates(GeoInterface.geometry(rec)))
        end
    end
    xmin, xmax = extrema(xs_all); ymin, ymax = extrema(ys_all)
    dx, dy = 0.03*(xmax - xmin), 0.03*(ymax - ymin)
    
    # --- log10 color scaling for Nitrogen ---
    UvalsN = collect(skipmissing(dfN.U))
    UposN = [u for u in UvalsN if u > 0]
    UminN, UmaxN = minimum(UposN), maximum(UposN)
    lminN, lmaxN = log10(UminN), log10(UmaxN)
    lognormN(u) = (log10(u) - lminN) / (lmaxN - lminN)
    
    # --- log10 color scaling for Phosphorus ---
    UvalsP = collect(skipmissing(dfP.U))
    UposP = [u for u in UvalsP if u > 0]
    UminP, UmaxP = minimum(UposP), maximum(UposP)
    lminP, lmaxP = log10(UminP), log10(UmaxP)
    lognormP(u) = (log10(u) - lminP) / (lmaxP - lminP)
    
    cmapN = choose_cmap(:N)
    cmapP = choose_cmap(:P)
    
    # ── draw side-by-side
    fig = CM.Figure(size = (1800, 1000))
    
    # --- Nitrogen (left) ---
    axN = CM.Axis(fig[1,1];
        xlabel="Easting (m)", ylabel="Northing (m)",
        title="Nitrogen Transportation Flows", aspect=DataAspect()
    )
    CM.xlims!(axN, xmin - dx, xmax + dx); CM.ylims!(axN, ymin - dy, ymax + dy)
    
    if estuary_tbl !== nothing
        est_color = RGBAf(0.75, 0.75, 0.75, 0.4)
        CM.poly!(axN, estuary_tbl; color=est_color, strokecolor=est_color, strokewidth=0.5)
    end
    
    for row in eachrow(dfN)
        pts = row.line; isempty(pts) && continue
        xs = first.(pts); ys = last.(pts)
        t = clamp(lognormN(row.U), 0, 1)
        c = get(cmapN, t)
        lw = (coalesce(row.line_type, "outlet_to_outlet") == "outlet_to_estuary") ? 3.8 : 2.8
        CM.lines!(axN, xs, ys; linewidth=lw, color=c)
    end
    
    outpts_xy = [GeoInterface.coordinates(GeoInterface.geometry(r)) for r in out_pts]
    if !isempty(outpts_xy)
        xs = [p[1] for p in outpts_xy]; ys = [p[2] for p in outpts_xy]
        CM.scatter!(axN, xs, ys; markersize=2.5, color=(0,0,0,0.25))
    end
    
    h1 = CM.lines!(axN, [NaN, NaN], [NaN, NaN]; color=:gray, linewidth=2.8)
    h2 = CM.lines!(axN, [NaN, NaN], [NaN, NaN]; color=:gray, linewidth=3.8)
    # CM.axislegend(axN, [h1, h2], ["Outlet → Outlet", "Outlet → Estuary"]; position=:lb, framevisible=true)
    
    # For Nitrogen colorbar - with log scale
    raw_ticksN = [1e-8, 1e-6, 1e-4, 1e-2, 1e0, 1e2, 1e4, 1e6]
    ticklabsN_all = ["10⁻⁸", "10⁻⁶", "10⁻⁴", "10⁻²", "10⁰", "10²", "10⁴", "10⁶"]
    valid_ticksN = filter(t -> UminN <= t <= UmaxN, raw_ticksN)
    valid_labsN = [ticklabsN_all[i] for (i, t) in enumerate(raw_ticksN) if UminN <= t <= UmaxN]
    
    CM.Colorbar(fig[1,2], 
        colormap=cmapN, 
        limits=(UminN, UmaxN),
        ticks=(valid_ticksN, valid_labsN),
        vertical=true,
        width=15,
        label="log10[Flow Magnitude (lb/year)]",
        scale=log10
    )
    
    # --- Phosphorus (right) ---
    axP = CM.Axis(fig[1,3];
        xlabel="Easting (m)", ylabel="Northing (m)",
        title="Phosphorus Transportation Flows", aspect=DataAspect()
    )
    CM.xlims!(axP, xmin - dx, xmax + dx); CM.ylims!(axP, ymin - dy, ymax + dy)
    
    if estuary_tbl !== nothing
        est_color = RGBAf(0.75, 0.75, 0.75, 0.4)
        CM.poly!(axP, estuary_tbl; color=est_color, strokecolor=est_color, strokewidth=0.5)
    end
    
    for row in eachrow(dfP)
        pts = row.line; isempty(pts) && continue
        xs = first.(pts); ys = last.(pts)
        t = clamp(lognormP(row.U), 0, 1)
        c = get(cmapP, t)
        lw = (coalesce(row.line_type, "outlet_to_outlet") == "outlet_to_estuary") ? 3.8 : 2.8
        CM.lines!(axP, xs, ys; linewidth=lw, color=c)
    end
    
    if !isempty(outpts_xy)
        xs = [p[1] for p in outpts_xy]; ys = [p[2] for p in outpts_xy]
        CM.scatter!(axP, xs, ys; markersize=2.5, color=(0,0,0,0.25))
    end
    
    h1 = CM.lines!(axP, [NaN, NaN], [NaN, NaN]; color=:gray, linewidth=2.8)
    h2 = CM.lines!(axP, [NaN, NaN], [NaN, NaN]; color=:gray, linewidth=3.8)
    # CM.axislegend(axP, [h1, h2], ["Outlet → Outlet", "Outlet → Estuary"]; position=:lb, framevisible=true)
    
    # For Phosphorus colorbar - with log scale
    raw_ticksP = [1e-8, 1e-6, 1e-4, 1e-2, 1e0, 1e2, 1e4]
    ticklabsP_all = ["10⁻⁸", "10⁻⁶", "10⁻⁴", "10⁻²", "10⁰", "10²", "10⁴"]
    valid_ticksP = filter(t -> UminP <= t <= UmaxP, raw_ticksP)
    valid_labsP = [ticklabsP_all[i] for (i, t) in enumerate(raw_ticksP) if UminP <= t <= UmaxP]
    
    CM.Colorbar(fig[1,4], 
        colormap=cmapP, 
        limits=(UminP, UmaxP),
        ticks=(valid_ticksP, valid_labsP),
        vertical=true,
        width=15,
        label="log10[Flow Magnitude (lb/year)]",
        scale=log10
    )
    
    CM.colgap!(fig.layout, 0)
    CM.rowgap!(fig.layout, 0)
    
    CM.save(joinpath(outdir, "map_transport_flows_both.png"), fig)
    # println("Wrote: map_transport_flows_both.png")
    return fig
end

# Calls
fig4 = plot_transport_for(:N, joinpath(outdir, "map_transport_flows_N.png"))
fig5 = plot_transport_for(:P, joinpath(outdir, "map_transport_flows_P.png"))
fig6 = plot_transport_both(outdir)
println("Wrote: map_transport_flows_N.png, map_transport_flows_P.png, Wrote: map_transport_flows_both.png")