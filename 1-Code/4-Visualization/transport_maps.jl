# File name: transport_maps.jl
# Megan Harris
# Revised 2026-10:
#   - flows below FLOW_MIN (solver round-off, e.g. 1e-24 lb/yr) are not drawn
#   - line width is a fixed log10 scale over the top FLOW_DECADES orders of magnitude of flow,
#     and the legend is drawn from the same function, so legend and lines always agree
#   - links are drawn smallest-first so main stems sit on top; optional round line caps
#   - shared helpers (also used by network_retention_map.jl)

_fmt(x) = @sprintf("%.2e", x)

FLOW_MIN     = 1.0   # lb/yr
FLOW_DECADES = 5     # widths span [max/1e5, max]; smaller flows get the minimum width

# Width on a log10 scale between lmin and lmax (default: the top FLOW_DECADES decades)
flow_width(u, lmax; lmin = lmax - FLOW_DECADES, wmin = 0.6, wmax = 7.0) =
    wmin + (wmax - wmin) * clamp((log10(u) - lmin) / max(lmax - lmin, 1e-9), 0.0, 1.0)

_SUP = Dict('0'=>'⁰','1'=>'¹','2'=>'²','3'=>'³','4'=>'⁴','5'=>'⁵','6'=>'⁶','7'=>'⁷','8'=>'⁸','9'=>'⁹','-'=>'⁻')
pow10_label(e::Integer) = "10" * join(_SUP[c] for c in string(e)) * " lb yr⁻¹"

transport_lines(nutrient::Symbol) =
    filter(row -> !ismissing(row.U) && row.U > FLOW_MIN && row.nutrient === nutrient, line_map)

function map_extent(dfs...)
    xs = Float64[]; ys = Float64[]
    for df in dfs, line in df.line
        isempty(line) && continue
        append!(xs, first.(line)); append!(ys, last.(line))
    end
    if estuary_tbl !== nothing
        collect_xy(c) = c isa Tuple ? (push!(xs, c[1]); push!(ys, c[2])) :
                        (c isa AbstractArray ? foreach(collect_xy, c) : nothing)
        for rec in estuary_tbl
            collect_xy(GeoInterface.coordinates(GeoInterface.geometry(rec)))
        end
    end
    xmin, xmax = extrema(xs); ymin, ymax = extrema(ys)
    dx, dy = 0.03 * (xmax - xmin), 0.03 * (ymax - ymin)
    return (xmin - dx, xmax + dx, ymin - dy, ymax + dy)
end

function draw_estuary!(ax; color = RGBAf(0.75, 0.75, 0.75, 0.4))
    estuary_tbl === nothing && return
    CM.poly!(ax, estuary_tbl; color = color, strokecolor = color, strokewidth = 0.5)
end

# Draw links (smallest flow first, so main stems are on top); colorfun(row) gives each link's
# color. Returns log10(max flow).
function draw_transport!(ax, df, colorfun; wmin = 0.6, wmax = 7.0, linecap = :butt, lmin = nothing)
    lmax = log10(maximum(df.U))
    lmin_ = lmin === nothing ? lmax - FLOW_DECADES : lmin
    for row in eachrow(sort(df, :U))
        pts = row.line; isempty(pts) && continue
        CM.lines!(ax, first.(pts), last.(pts); linewidth = flow_width(row.U, lmax; lmin = lmin_, wmin = wmin, wmax = wmax),
                  color = colorfun(row), linecap = linecap)
    end
    return lmax
end

function add_flow_legend!(ax, lmax, color; extra_handles = Any[], extra_labels = String[],
                          position = :rb, title = "Flow")
    top  = floor(Int, lmax)
    exps = (top - 3):top
    hs = Any[CM.lines!(ax, [NaN, NaN], [NaN, NaN]; color = color, linewidth = flow_width(10.0^e, lmax)) for e in exps]
    CM.axislegend(ax, vcat(hs, extra_handles), vcat(pow10_label.(exps), extra_labels), title;
                  position = position, framevisible = true)
end

function draw_outlet_points!(ax)
    pts = [GeoInterface.coordinates(GeoInterface.geometry(r)) for r in out_pts]
    isempty(pts) && return
    CM.scatter!(ax, [p[1] for p in pts], [p[2] for p in pts]; markersize = 2.5, color = (0, 0, 0, 0.25))
end

nutrient_name(n) = n === :N ? "Nitrogen" : "Phosphorus"
nutrient_color(n) = n === :N ? N_STROKE : P_STROKE

function transport_panel!(fig, pos, nutrient, ext; title = nutrient_name(nutrient) * " Transportation Flows")
    df = transport_lines(nutrient)
    ax = CM.Axis(fig[pos...]; xlabel = "Easting (m)", ylabel = "Northing (m)", title = title, aspect = DataAspect())
    CM.xlims!(ax, ext[1], ext[2]); CM.ylims!(ax, ext[3], ext[4])
    draw_estuary!(ax)
    lmax = draw_transport!(ax, df, row -> nutrient_color(nutrient))
    draw_outlet_points!(ax)
    add_flow_legend!(ax, lmax, nutrient_color(nutrient))
    return ax
end

function report_dropped(nutrient)
    all_ = filter(row -> !ismissing(row.U) && row.nutrient === nutrient, line_map)
    kept = transport_lines(nutrient)
    println("Transport ($(nutrient_name(nutrient))): drawing $(nrow(kept)) of $(nrow(all_)) links; ",
            "$(nrow(all_) - nrow(kept)) below $(FLOW_MIN) lb/yr not drawn")
end

function plot_transport_for(nutrient::Symbol, outpath::String)
    report_dropped(nutrient)
    fig = CM.Figure(size = (900, 1000))
    transport_panel!(fig, (1, 1), nutrient, map_extent(transport_lines(nutrient)))
    CM.save(outpath, fig); fig
end

function plot_transport_both(outdir::String)
    ext = map_extent(transport_lines(:N), transport_lines(:P))
    fig = CM.Figure(size = (1600, 1000))
    transport_panel!(fig, (1, 1), :N, ext)
    transport_panel!(fig, (1, 2), :P, ext)
    CM.colgap!(fig.layout, 0); CM.rowgap!(fig.layout, 0)
    CM.save(joinpath(outdir, "map_transport_flows_both.png"), fig)
    fig
end

# Calls (only when :transport is in MAPS; the helpers above are always loaded)
if :transport in MAPS
fig4 = plot_transport_for(:N, joinpath(outdir, "map_transport_flows_N.png"))
fig5 = plot_transport_for(:P, joinpath(outdir, "map_transport_flows_P.png"))
fig6 = plot_transport_both(outdir)
println("Wrote: map_transport_flows_N.png, map_transport_flows_P.png, map_transport_flows_both.png")
end # if :transport in MAPS
