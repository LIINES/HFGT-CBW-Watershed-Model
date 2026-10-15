# File name: network_retention_map.jl
# Megan Harris (2026-10 revision)
#
# Figure A: river-network transport over land retention, (a) nitrogen and (b) phosphorus.
#   - Lines: outlet->outlet transport. Width = estimated flow (log scale over the top
#     FLOW_DECADES decades). Color = modeled reach loss = storage at the reach's upstream outlet /
#     inflow to that outlet, from the estimator solution (between 0 and 1 because the network
#     conserves mass and storage is non-negative).
#   - Open circles: load delivered to the Bay at outlets draining directly to the estuary
#     (these final links have no line geometry in the shapefiles).
#   - Gray dots: land retention per land-river segment = applied minus delivered to the river
#     (final buffer stock QB of each land segment).
#
# Publication layout: drawn at final print size, Elsevier double-column width (190 mm = 539 pt),
# 8 pt type. Saved as vector PDF (for submission) and 600 dpi PNG (for drafts).
# Map coordinates are Web Mercator (EPSG:3857); the scale bar corrects for latitude.
#
# Requires pre_process_maps.jl, accumulation_maps.jl (seg_xy, out_xy, size_scale_sqrt) and
# transport_maps.jl (flow helpers) to be included first, with the estimator results in memory.

# ---------- appearance (sizes in pt at final print size) ----------
FIGA_WIDTH_PT = 539.0                       # 190 mm
FIGA_FONT     = 8
FIGA_SMALL    = 7
FIGA_WMIN     = 0.35                        # thinnest river line
FIGA_WMAX     = 3.6                         # main stems
DELIV_SMAX    = 16.0                        # largest Bay-delivery circle
DOT_SMAX      = 9.0                         # largest land-retention dot
LAND_COLOR    = RGBf(0.955, 0.950, 0.940)   # watershed footprint
WATER_COLOR   = RGBf(0.80, 0.88, 0.95)      # Chesapeake Bay
DOT_COLOR     = RGBAf(0.35, 0.35, 0.35, 0.35)
NOFACT_COLOR  = RGBAf(0.35, 0.35, 0.35, 0.80)
SCALEBAR_KM   = 100

# Loss colormaps: start from a visible tint (35% of the nutrient color) rather than near-white
_mix(c, t) = RGBf(1 - t * (1 - c.r), 1 - t * (1 - c.g), 1 - t * (1 - c.b))
loss_cmap(n) = (c = n === :N ? N_FILL : P_FILL; [_mix(c, 0.35), _mix(c, 0.7), RGBf(c.r, c.g, c.b)])
loss_color(n, t) = (cs = loss_cmap(n); t <= 0.5 ? Colors.weighted_color_mean(1 - 2t, cs[1], cs[2]) :
                                                  Colors.weighted_color_mean(2 - 2t, cs[2], cs[3]))

# ---------- data ----------
# Modeled loss at each outlet: QB / (QB + outflow), from the estimator solution
function outlet_loss(nutrient::Symbol)
    nb  = myLFES.buffer.number
    off = nutrient === :N ? 0 : nb
    qb  = Dict{String,Float64}()
    for k in 1:nb
        bname = String(myLFES.buffer.name[k])
        startswith(bname, "Outlet ") || continue
        qb[replace(bname, "Outlet " => "")] = max(Float64(cap_results.QB[k + off, end]), 0.0)
    end
    out = Dict{String,Float64}()
    for (j, tp) in cap_to_transportProcess
        o = origin_info(tp)
        (o.kind == :outlet && o.segment !== nothing && cap_nutrient(j) === nutrient) || continue
        tok = String(o.segment)
        out[tok] = get(out, tok, 0.0) + max(Float64(cap_results.U[j, 1]), 0.0)
    end
    loss = Dict{String,Float64}()
    for (tok, q) in qb
        inflow = q + get(out, tok, 0.0)
        inflow > 0 && (loss[tok] = q / inflow)
    end
    return loss
end

function land_retention_points(nutrient::Symbol)
    nb   = myLFES.buffer.number
    rows = nutrient === :N ? (1:nb) : ((nb + 1):(2 * nb))
    xs = Float64[]; ys = Float64[]; v = Float64[]
    for (k, r) in enumerate(rows)
        bname = String(myLFES.buffer.name[k])
        startswith(bname, "Land Segment ") || continue
        tok = replace(bname, "Land Segment " => "")
        haskey(seg_xy, tok) || continue
        x, y = seg_xy[tok]
        push!(xs, x); push!(ys, y); push!(v, Float64(cap_results.QB[r, end]))
    end
    return (x = xs, y = ys, v = v)
end

# Load delivered to the estuary at each outlet that drains directly to it
function bay_delivery_points(nutrient::Symbol)
    caps = nutrient === :N ? caps_est_N : caps_est_P
    xs = Float64[]; ys = Float64[]; v = Float64[]; tok = String[]; missed = 0
    for j in caps
        o = origin_info(cap_to_transportProcess[j])
        t = o.segment === nothing ? nothing : String(o.segment)
        if t === nothing || !haskey(out_xy, t)
            missed += 1; continue
        end
        x, y = out_xy[t]
        push!(xs, x); push!(ys, y); push!(v, Float64(cap_results.U[j, 1])); push!(tok, t)
    end
    missed > 0 && println("  Bay delivery ($(nutrient_name(nutrient))): $missed outlets without coordinates")
    return (x = xs, y = ys, v = v, tok = tok)
end

function figA_extent()
    xmin, xmax, ymin, ymax = map_extent(transport_lines(:N), transport_lines(:P))
    for n in (:N, :P), p in (land_retention_points(n), bay_delivery_points(n))
        isempty(p.x) && continue
        xmin = min(xmin, minimum(p.x)); xmax = max(xmax, maximum(p.x))
        ymin = min(ymin, minimum(p.y)); ymax = max(ymax, maximum(p.y))
    end
    dx, dy = 0.02 * (xmax - xmin), 0.02 * (ymax - ymin)
    return (xmin - dx, xmax + dx, ymin - dy, ymax + dy)
end

# Legend values span the plotted range: smallest to largest.
# Sizes are proportional to sqrt(value), so intermediate values are spaced evenly in sqrt
# (the legend symbols grow in even steps).
range_vals_sqrt(vmin, vmax, n) = [round(v; sigdigits = 2) for v in range(sqrt(vmin), sqrt(vmax); length = n) .^ 2]
range_vals_log(vmin, vmax, n)  = [round(v; sigdigits = 2) for v in 10 .^ range(log10(vmin), log10(vmax); length = n)]

_sig(v) = (r = round(v; sigdigits = 2); r == round(r) ? string(round(Int, r)) : string(r))
function fmt_lb(v)                                # v in lb
    v >= 1e6 && return _sig(v / 1e6) * " M lb"
    v >= 1e3 && return _sig(v / 1e3) * " k lb"
    return _sig(v) * " lb"
end
function fmt_flow(v)                              # v in lb/yr, as m×10ⁿ
    e = floor(Int, log10(v)); m = round(v / 10.0^e; digits = 1)
    m >= 10 && (m /= 10; e += 1)
    e <= 2 && return _sig(v) * " lb yr⁻¹"
    mant = m == 1 ? "" : _sig(m) * "×"
    return mant * "10" * join(_SUP[c] for c in string(e)) * " lb yr⁻¹"
end

# Color-bar range for reach loss: :full = min to max; :p95 = 0 to 95th percentile (higher values
# share the top color, shown by a triangle on the color bar)
if !@isdefined(LOSS_RANGE); LOSS_RANGE = :full; end

# ---------- map furniture ----------
_R_EARTH = 6378137.0
mercator_lat(y) = 2 * atan(exp(y / _R_EARTH)) - pi / 2

function add_scalebar!(ax, ext; km = SCALEBAR_KM)
    W, H = ext[2] - ext[1], ext[4] - ext[3]
    x0, y0 = ext[1] + 0.05 * W, ext[3] + 0.05 * H
    L  = km * 1000 / cos(mercator_lat(y0))          # Web Mercator units for `km` at this latitude
    tk = 0.008 * H
    CM.lines!(ax, [x0, x0 + L], [y0, y0]; color = :black, linewidth = 1.2)
    for x in (x0, x0 + L / 2, x0 + L)
        CM.lines!(ax, [x, x], [y0, y0 + tk]; color = :black, linewidth = 1.0)
    end
    CM.text!(ax, x0 + L / 2, y0 + 1.6 * tk; text = "$(km) km", align = (:center, :bottom), fontsize = FIGA_SMALL)
    # north arrow
    xa, ya = x0 + 0.02 * W, y0 + 0.08 * H
    CM.lines!(ax, [xa, xa], [ya, ya + 0.045 * H]; color = :black, linewidth = 1.0)
    CM.scatter!(ax, [xa], [ya + 0.045 * H]; marker = :utriangle, markersize = 6, color = :black)
    CM.text!(ax, xa, ya + 0.052 * H; text = "N", align = (:center, :bottom), fontsize = FIGA_SMALL, font = :bold)
end

# ---------- panel ----------
function network_retention_panel!(fig, col, nutrient, ext, label)
    ax = CM.Axis(fig[1, col]; title = "($label) " * nutrient_name(nutrient), titlealign = :left,
                 titlesize = FIGA_FONT + 1, aspect = DataAspect())
    CM.hidedecorations!(ax); CM.hidespines!(ax)
    CM.xlims!(ax, ext[1], ext[2]); CM.ylims!(ax, ext[3], ext[4])
    ncol = nutrient_color(nutrient)

    # base map: watershed footprint (land-river-segment polygons) and the Bay
    CM.poly!(ax, seg_tbl; color = LAND_COLOR, strokewidth = 0)
    draw_estuary!(ax; color = WATER_COLOR)

    # land retention dots (million lb)
    pts  = land_retention_points(nutrient)
    vals = max.(pts.v, 0.0) ./ 1e6
    vmax = maximum(vals)
    vmin = minimum(filter(>(1e-6), vals))          # smallest retention above 1 lb
    CM.scatter!(ax, pts.x, pts.y; markersize = size_scale_sqrt(vals; smin = 0.0, smax = DOT_SMAX, vmax = vmax),
                color = DOT_COLOR, strokewidth = 0)

    # river links colored by modeled loss
    df    = transport_lines(nutrient)
    lossd = outlet_loss(nutrient)
    lk    = [get(lossd, String(r.FromSeg), NaN) for r in eachrow(df)]
    losses  = filter(!isnan, lk)
    lossmin = LOSS_RANGE === :full ? minimum(losses) : 0.0
    lossmax = LOSS_RANGE === :full ? maximum(losses) : quantile(losses, 0.95)
    lossmax = max(lossmax, lossmin + 1e-6)
    colorfun(row) = begin
        l = get(lossd, String(row.FromSeg), NaN)
        isnan(l) ? NOFACT_COLOR : loss_color(nutrient, clamp((l - lossmin) / (lossmax - lossmin), 0.0, 1.0))
    end
    lmin_flow = log10(minimum(df.U))
    lmax   = draw_transport!(ax, df, colorfun; wmin = FIGA_WMIN, wmax = FIGA_WMAX, linecap = :round, lmin = lmin_flow)
    n_zero = count(l -> !isnan(l) && l < 1e-4, lk)

    # delivery to the Bay (million lb), open circles
    bay  = bay_delivery_points(nutrient)
    bval = max.(bay.v, 0.0) ./ 1e6
    bmax = maximum(bval)
    bmin = minimum(filter(>(1e-6), bval))
    CM.scatter!(ax, bay.x, bay.y; markersize = size_scale_sqrt(bval; smin = 0.0, smax = DELIV_SMAX, vmax = bmax),
                color = :transparent, strokecolor = ncol, strokewidth = 0.9)
    col == 1 && add_scalebar!(ax, ext)

    # color bar and legends below the map
    cb_extra = LOSS_RANGE === :full ? (;) : (; highclip = loss_cmap(nutrient)[end])
    CM.Colorbar(fig[2, col]; cb_extra..., colormap = loss_cmap(nutrient), limits = (100 * lossmin, 100 * lossmax), vertical = false,
                flipaxis = false, label = "Modeled reach loss (% of inflow)", width = CM.Relative(0.8),
                height = 6, labelsize = FIGA_SMALL, ticklabelsize = FIGA_SMALL, ticksize = 3,
                spinewidth = 0.5, tickwidth = 0.5)
    fvals = range_vals_log(10.0^lmin_flow, 10.0^lmax, 4)
    flow_el = Any[CM.LineElement(color = loss_color(nutrient, 0.6),
                                 linewidth = flow_width(v, lmax; lmin = lmin_flow, wmin = FIGA_WMIN, wmax = FIGA_WMAX)) for v in fvals]
    dvals = range_vals_sqrt(vmin, vmax, 3)
    dot_el = [CM.MarkerElement(marker = :circle, color = DOT_COLOR, strokewidth = 0, markersize = s)
              for s in size_scale_sqrt(dvals; smin = 0.0, smax = DOT_SMAX, vmax = vmax)]
    bvals = range_vals_sqrt(bmin, bmax, 3)
    bay_el = [CM.MarkerElement(marker = :circle, color = :transparent, strokecolor = ncol, strokewidth = 0.9, markersize = s)
              for s in size_scale_sqrt(bvals; smin = 0.0, smax = DELIV_SMAX, vmax = bmax)]
    leg_kw = (; framevisible = false, tellheight = true, valign = :top, labelsize = FIGA_SMALL,
               titlesize = FIGA_SMALL, rowgap = 0, padding = (2, 2, 2, 2), patchsize = (14, 10))
    gl = fig[3, col] = CM.GridLayout()
    CM.Legend(gl[1, 1], flow_el, fmt_flow.(fvals), "River flow"; leg_kw...)
    CM.Legend(gl[1, 2], dot_el, fmt_lb.(dvals .* 1e6), "Retained on land"; leg_kw...)
    CM.Legend(gl[1, 3], bay_el, fmt_lb.(bvals .* 1e6), "Delivered to Bay"; leg_kw...)
    CM.colgap!(gl, 4)

    println("Fig A ($(nutrient_name(nutrient))): $(nrow(df)) links drawn, $n_zero with ~0% modeled loss; ",
            "land retention = $(round(sum(vals); digits = 1)) M lb; delivered to Bay = $(round(sum(bval); digits = 2)) M lb ",
            "at $(length(bval)) outlets; flow $(fmt_flow(10.0^lmin_flow)) to $(fmt_flow(10.0^lmax)); ",
            "reach loss $(round(100 * minimum(losses); digits = 1))-$(round(100 * maximum(losses); digits = 1))% ",
            "(color bar: $(round(100 * lossmin; digits = 1))-$(round(100 * lossmax; digits = 1))%, LOSS_RANGE = $(LOSS_RANGE))")
    return ax
end

function plot_network_retention(outdir::String)
    ext = figA_extent()
    fig = CM.Figure(size = (FIGA_WIDTH_PT, 1.2 * FIGA_WIDTH_PT), fontsize = FIGA_FONT,
                    fonts = (; regular = "Helvetica", bold = "Helvetica Bold", italic = "Helvetica Oblique"),
                    figure_padding = 4)
    network_retention_panel!(fig, 1, :N, ext, "a")
    network_retention_panel!(fig, 2, :P, ext, "b")
    CM.colgap!(fig.layout, 6); CM.rowgap!(fig.layout, 3)
    # map row height = map aspect ratio x column width, then trim the figure to its contents
    CM.rowsize!(fig.layout, 1, CM.Aspect(1, (ext[4] - ext[3]) / (ext[2] - ext[1])))
    CM.resize_to_layout!(fig)
    CM.save(joinpath(outdir, "figA_network_retention.pdf"), fig; pt_per_unit = 1)       # vector, 190 mm wide
    CM.save(joinpath(outdir, "figA_network_retention.png"), fig; px_per_unit = 600 / 72) # 600 dpi
    println("Wrote: figA_network_retention.pdf (vector, 190 mm wide) and figA_network_retention.png (600 dpi)")
    fig
end

figA = plot_network_retention(outdir)
