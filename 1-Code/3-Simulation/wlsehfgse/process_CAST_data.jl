# File name: process_CAST_data.jl
# Megan Harris

# Primary goal: map data from CAST to myLFES data

#### Set up indices
# Set up and index that maps resource ID to transformation resource ID (in this system, they should be identical since the transformation resources
    # are the first resources entered into the XML file)
# transformationResource arrays index 1:numTransformationResources; each has an resource id
# idxTransformationResourceResource[id_transformResource] => resource_id
# Build inverse mapping resource_id to id_transformResource for quick lookup (land-segment “transformation resources”)
resourceID_to_transformResource = Dict{Int,Int}()
for id_transformResource in eachindex(myLFES.transformationResource.idxResource)
    resourceID_to_transformResource[ myLFES.transformationResource.idxResource[id_transformResource] ] = id_transformResource
end

# Quick accessors to get river segment name and county name from transformation resources
transformResource_riverSegment(id_transformResource) = String(myLFES.transformationResource.RiverSegN[id_transformResource])
transformResource_county(id_transformResource) =
    transformationResource_to_fips5[id_transformResource]   # e.g., "42057"

# Nutrient detector for capabilities by name (fallback)
function cap_nutrient(cap_idx::Int)
    nm = lowercase(String(myLFES.engSysNet.pnTransitions.name[cap_idx]))
    return occursin("phosph", nm) ? :P : :N
end

# Parse buffer kind and segment id (Land Segment for lands and River Segment from outlets) from bufferName 
function buffer_kind_and_segment(bname::AbstractString)
    lb = lowercase(String(bname))

    # Try explicit prefixes first
    if startswith(lb, "land segment")
        # pull last token like A..Z0..9_####_####
        m = match(r"([A-Za-z0-9]+_[0-9]+_[0-9]+)$", bname)
        return (:land, m === nothing ? nothing : String(m.captures[1]))
    elseif startswith(lb, "outlet")
        m = match(r"([A-Za-z0-9]+_[0-9]+_[0-9]+)$", bname)
        return (:outlet, m === nothing ? nothing : String(m.captures[1]))
    else
        # Fallback: try to capture a trailing segment-like token anyway
        m = match(r"([A-Za-z0-9]+_[0-9]+_[0-9]+)$", bname)
        return (m === nothing ? :other : :other, m === nothing ? nothing : String(m.captures[1]))
    end
end

# Is the destination an estuary node?
function is_estuary_destination(tp_idx::Int)
    dest = myLFES.transportProcess.idxDestination[tp_idx]
    if 1 <= dest <= length(myLFES.buffer.name)
        bname = lowercase(String(myLFES.buffer.name[dest]))
        return occursin(r"estuar", bname)
    else
        return false
    end
end

#### Normalize county level data
# Use check_or_stop to stop run if conditions are not met
check_or_stop(cond::Bool, msg::AbstractString) = cond ? nothing : error(msg)

# Normalize geographies:
# for counties, converting to string, stripping white space and parenthetical expressions ()
# (this is a fall back since we already stripped the county data in load_data.jl)
norm_geog(s) = replace(strip(String(s)), r"\s*\([^)]*\)\s*" => "") |> strip
# for FIPS codes
zp5(x) = lpad(String(x), 5, '0') 

# County names are given as County, ST. This function separates them.
split_county_state(s::AbstractString) = begin
    t = norm_geog(s)
    if occursin(",", t)
        parts = split(t, ",")
        cname = strip(parts[1])
        sabbr = uppercase(strip(parts[end]))
        if cname in ("Washington","District of Columbia") && sabbr == "DC"
            return "Washington", "DC"
        end
        return cname, sabbr
    else
        return strip(t), nothing
    end
end

# pick modal key from a Dict{K,Int}
function modal_key(d::Dict{K,Int}) where {K}
    best_k = first(keys(d)); best_v = -1
    for (k,v) in d
        if v > best_v; best_v=v; best_k=k; end
    end
    return best_k
end

# Strip county prefix; it is a CAST notation about county delineation 
# and will not match to county level data
transformationResource_to_fips5 = replace.(String.(myLFES.transformationResource.FIPS_NHL), r"^[A-Z]" => "")

#### Applied-derived county to FIPS map
applied_county_full = norm_geog.(applied_df.County)  # should look like "Accomack, VA"
applied_fips5       = zp5.(applied_df.FIPS)
county_fips_pairs   = DataFrame(County=applied_county_full, FIPS5=applied_fips5)

# enforce one-to-one by picking the modal FIPS per county name
geog_to_fips = Dict{String,String}()
for sub in groupby(county_fips_pairs, :County)
    cnts = countmap(String.(sub.FIPS5))
    geog_to_fips[first(sub.County)] = modal_key(cnts)
end
# DC alias
if haskey(geog_to_fips, "District of Columbia, DC") && !haskey(geog_to_fips, "Washington, DC")
    geog_to_fips["Washington, DC"] = geog_to_fips["District of Columbia, DC"]
end

# Build a unified crosswalk
# Rows from applied (county, state, FIPS5, statefips)
function build_crosswalk(geog_to_fips::Dict{String,String})
    rows = NamedTuple[]
    for (county_full, digs) in geog_to_fips
        cname, sabbr = split_county_state(county_full)   # ("Accomack", "VA")
        st2 = digs[1:2]                                  # "51"
        push!(rows, (
            County       = county_full,                  # "Accomack, VA"
            County_norm  = norm_geog(county_full),       # normalized text for joins
            CountyName   = cname,                        # "Accomack"
            StateAbbr    = sabbr,                        # "VA"
            StateFIPS2   = st2,                          # "51"
            FIPS5        = digs                          # "51001"
        ))
    end
    DataFrame(rows)
end

county_crosswalk = build_crosswalk(geog_to_fips)

#### Use the crosswalk to fill CountyKey everywhere
# (A) Applied
applied_df.County = norm_geog.(applied_df.County)  # ensure normalized before the join
applied_df = leftjoin(
    applied_df,
    select(county_crosswalk, :County_norm, :FIPS5),
    on = :County => :County_norm,
    makeunique = true,
)
applied_df.CountyKey = copy(applied_df.FIPS5)  # use numeric FIPS as the only key

# (B) Loads
loads_df.County = norm_geog.(loads_df.County)
loads_df = leftjoin(
    loads_df,
    select(county_crosswalk, :County_norm, :FIPS5),
    on = :County => :County_norm,
    makeunique = true,
)
loads_df.CountyKey = copy(loads_df.FIPS5)  # optional convenience column

# Coverage diagnostics
nA, nL = nrow(applied_df), nrow(loads_df)
missA = count(ismissing, applied_df.CountyKey)
missL = count(ismissing, loads_df.CountyKey)
println("Applied CountyKey coverage: ",
    round(100*(nA-missA)/max(nA,1), digits=1), "% (", nA-missA, "/", nA, ")")
println("Loads   CountyKey coverage: ",
    round(100*(nL-missL)/max(nL,1), digits=1), "% (", nL-missL, "/", nL, ")")

#### Transportation Resolver
strip_state_prefix(s::AbstractString) = replace(s, r"^[A-Z]{2}-" => "")
clean_lrs(s::AbstractString) = strip_state_prefix(norm_lrs(String(s)))
river_token_from_land(s::AbstractString) = replace(clean_lrs(s), r"^[A-Z]\d{5}_?" => "")

# Build a lookup from buffer name to county (one-time cost)
BUFFER_NAME_TO_COUNTY = Dict{String, String}()
for (i, name) in enumerate(myLFES.transformationResource.transformationResourceName)
    BUFFER_NAME_TO_COUNTY[String(name)] = transformationResource_to_fips5[i]
end

function origin_info(tp_idx::Int)
    origin = myLFES.transportProcess.idxOrigin[tp_idx]

    if 1 <= origin <= myLFES.buffer.number
        bname = String(myLFES.buffer.name[origin])
        kind, seg_token = buffer_kind_and_segment(bname)

        if kind == :land
            full_lrs = clean_lrs(bname)  # strips state prefix if needed
            cnty = get(BUFFER_NAME_TO_COUNTY, bname, missing)

            return (segment = full_lrs, kind = kind, county = cnty)
        else
            # Outlet or estuary
            seg_val = isnothing(seg_token) ? nothing : seg_token
            return (segment = seg_val, kind = kind, county = missing)
        end
    else
        # No valid origin buffer
        return (segment = nothing, kind = :other, county = missing)
    end
end

function dest_info(tp_idx::Int)
    dest = myLFES.transportProcess.idxDestination[tp_idx]

    if 1 <= dest <= myLFES.buffer.number
        bname = String(myLFES.buffer.name[dest])
        kind, seg = buffer_kind_and_segment(bname)
        return (segment = seg, kind = kind, county = missing)
    else
        return (segment = nothing, kind = :other, county = missing)
    end
end

# Classifiers
is_land_origin(tp_idx::Int) = begin
    _, kind, _ = origin_info(tp_idx)
    kind == :land
end

is_outlet_origin(tp_idx::Int) = begin
    _, kind, _ = origin_info(tp_idx)
    kind == :outlet
end

#### Aggregations: Applied and EOS/EOT datasets
# Applications by county & sector
apply_countySector = combine(groupby(applied_df, [:CountyKey, :Sector]),
                  :TotalNApplication => sum => :N_app,
                  :TotalPApplication => sum => :P_app)

# Applications totals by county
apply_by_county = combine(groupby(applied_df, :CountyKey),
                         :TotalNApplication => sum => :N_app_tot,
                         :TotalPApplication => sum => :P_app_tot)
N_app_tot = Dict(String(r.CountyKey)=>Float64(r.N_app_tot) for r in eachrow(apply_by_county))
P_app_tot = Dict(String(r.CountyKey)=>Float64(r.P_app_tot) for r in eachrow(apply_by_county))

# EOS/EOT by county
function county_eos_eot(df::DataFrame)
    # Filter out rows with missing CountyKey first
    df_valid = filter(row -> !ismissing(row.CountyKey), df)
    g = groupby(df_valid, :CountyKey)
    out = DataFrame(CountyKey=String[], EOS_N=Float64[], EOS_P=Float64[], EOT_N=Float64[], EOT_P=Float64[])
    for sdf in g
        eosN = sum(coalesce.(sdf[!, Symbol("2024 Progress_NLoadEOS")], 0.0))
        eosP = sum(coalesce.(sdf[!, Symbol("2024 Progress_PLoadEOS")], 0.0))
        eotN = sum(coalesce.(sdf[!, Symbol("2024 Progress_NLoadEOT")], 0.0))
        eotP = sum(coalesce.(sdf[!, Symbol("2024 Progress_PLoadEOT")], 0.0))
        push!(out, (String(first(sdf.CountyKey)), eosN, eosP, eotN, eotP))
    end
    out
end
eoseot = county_eos_eot(loads_df)
EOS_N = Dict(String(r.CountyKey)=>Float64(r.EOS_N) for r in eachrow(eoseot))
EOS_P = Dict(String(r.CountyKey)=>Float64(r.EOS_P) for r in eachrow(eoseot))
EOT_N = Dict(String(r.CountyKey)=>Float64(r.EOT_N) for r in eachrow(eoseot))
EOT_P = Dict(String(r.CountyKey)=>Float64(r.EOT_P) for r in eachrow(eoseot))

#### Computing a delivery factor for: land to outlet (one for each land segment) and all river segments
# robust numeric parser
function tofloat(x)
    if x === missing || x === nothing
        return 0.0
    elseif x isa Real
        return float(x)
    elseif x isa AbstractString
        s = strip(x)
        isempty(s) && return 0.0
        v = tryparse(Float64, replace(s, "," => ""))
        return v === nothing ? 0.0 : v
    else
        return 0.0
    end
end
river_token(s::AbstractString) =
    replace(strip_state_prefix(String(s)), r"^[A-Z]\d{5}_?" => "")

function build_factor_maps_area(dfact_df::DataFrame, basecond_df::DataFrame;
                                area_col::Symbol = Symbol("2024 Progress_PostBMPAcres"))

    # --- normalize join keys on both tables ---
    if !(:LRS in propertynames(dfact_df));  dfact_df.LRS  = clean_lrs.(dfact_df.LandRiverSegment);  end
    if !(:RIV in propertynames(dfact_df));  dfact_df.RIV  = river_token.(dfact_df.LandRiverSegment); end

    if !(:LRS in propertynames(basecond_df)); basecond_df.LRS = clean_lrs.(basecond_df.LandRiverSegment); end
    if !(:RIV in propertynames(basecond_df)); basecond_df.RIV = river_token.(basecond_df.LandRiverSegment); end

    # --- build df_f (carry LoadSource only if present) ---
    df_f = DataFrame(
        LRS    = String.(dfact_df.LRS),
        RIV    = String.(dfact_df.RIV),
        ltw_tn = tofloat.(dfact_df.LandToWater_TN_Factor),
        str_tn = tofloat.(dfact_df.StreamToRiver_TN_Factor),
        rtb_tn = tofloat.(dfact_df.RiverToBay_TN_Factor),
        ltw_tp = tofloat.(dfact_df.LandToWater_TP_Factor),
        str_tp = tofloat.(dfact_df.StreamToRiver_TP_Factor),
        rtb_tp = tofloat.(dfact_df.RiverToBay_TP_Factor),
    )
    if :LoadSource in propertynames(dfact_df)
        df_f.LoadSource = String.(dfact_df.LoadSource)  # add only if present
    end

    # --- build area_df properly ---
    @assert area_col in propertynames(basecond_df) "Area column $(area_col) not found in basecond_df"
    areas = tofloat.(basecond_df[!, area_col])

    if :LoadSource in propertynames(basecond_df)
        area_df = select(basecond_df, [:LRS, :LoadSource])
        area_df.LoadSource = String.(area_df.LoadSource)
    else
        area_df = select(basecond_df, :LRS)
    end
    area_df.LRS = String.(area_df.LRS)
    @assert length(areas) == nrow(area_df)
    area_df[:, :area] = areas  # add the numeric area column

    # --- decide join keys ONLY if present on BOTH sides ---
    join_keys = [:LRS]
    if (:LoadSource in propertynames(df_f)) && (:LoadSource in propertynames(area_df))
        push!(join_keys, :LoadSource)
    end

    # --- join and fill missing areas with 0 ---
    df_join = leftjoin(df_f, area_df, on = join_keys, makeunique = true)
    df_join.area = coalesce.(df_join.area, 0.0)

    # --- per-LRS area-weighted means ---
    FS_LRS = Dict{String, NamedTuple{
        (:N_LTW,:P_LTW,:N_STR,:P_STR,:N_R2B,:P_R2B,:N_LTWSTR,:P_LTWSTR),
        NTuple{8,Float64}
    }}()

    for sdf in groupby(df_join, :LRS)
        A = sum(sdf.area)
        if A <= 0
            N_LTW = P_LTW = N_STR = P_STR = N_R2B = P_R2B = N_LTWSTR = P_LTWSTR = 0.0
        else
            w = sdf.area ./ A
            N_LTW    = sum(w .* sdf.ltw_tn)
            P_LTW    = sum(w .* sdf.ltw_tp)
            N_STR    = sum(w .* sdf.str_tn)
            P_STR    = sum(w .* sdf.str_tp)
            N_R2B    = sum(w .* sdf.rtb_tn)
            P_R2B    = sum(w .* sdf.rtb_tp)
            N_LTWSTR = sum(w .* (sdf.ltw_tn .* sdf.str_tn))
            P_LTWSTR = sum(w .* (sdf.ltw_tp .* sdf.str_tp))
        end
        FS_LRS[String(first(sdf.LRS))] =
            (N_LTW=N_LTW, P_LTW=P_LTW, N_STR=N_STR, P_STR=P_STR,
             N_R2B=N_R2B, P_R2B=P_R2B, N_LTWSTR=N_LTWSTR, P_LTWSTR=P_LTWSTR)
    end

    # --- per-RIV area-weighted R2B across LRS in that river ---
    lrs_area = combine(groupby(df_join, :LRS), :area => sum => :LRS_area)
    riv_map  = unique(select(df_f, [:LRS, :RIV]))  # map LRS -> RIV
    lrs_area = leftjoin(lrs_area, riv_map, on=:LRS)

    FS_RIV = Dict{String, NamedTuple{(:R2B_N,:R2B_P), NTuple{2,Float64}}}()
    for sdf in groupby(lrs_area, :RIV)
        A = sum(sdf.LRS_area)
        if A <= 0
            R2B_N = R2B_P = 0.0
        else
            weights = sdf.LRS_area ./ A
            R2B_N = sum(weights .* [FS_LRS[String(LRS)].N_R2B for LRS in sdf.LRS])
            R2B_P = sum(weights .* [FS_LRS[String(LRS)].P_R2B for LRS in sdf.LRS])
        end
        FS_RIV[String(first(sdf.RIV))] = (R2B_N=R2B_N, R2B_P=R2B_P)
    end
    # Per-RIV area-weighted means for LTW & STR (N and P) — fallback when an LRS is missing
    FS_RIV_LS = Dict{String, NamedTuple{(:N_LTW,:P_LTW,:N_STR,:P_STR), NTuple{4,Float64}}}()
    for sdf in groupby(df_join, :RIV)
        A = sum(sdf.area)
        if A <= 0
            FS_RIV_LS[String(first(sdf.RIV))] = (N_LTW=0.0, P_LTW=0.0, N_STR=0.0, P_STR=0.0)
        else
            w = sdf.area ./ A
            FS_RIV_LS[String(first(sdf.RIV))] = (
                N_LTW = sum(w .* sdf.ltw_tn),
                P_LTW = sum(w .* sdf.ltw_tp),
                N_STR = sum(w .* sdf.str_tn),
                P_STR = sum(w .* sdf.str_tp),
            )
        end
    end

    return FS_LRS, FS_RIV, FS_RIV_LS
end

# Build weighted maps using the Post-BMP area column
FS_LRS, FS_RIV, FS_RIV_LS = build_factor_maps_area(
    dfact_df, basecond_df; area_col = Symbol("2024 Progress_PostBMPAcres")
)

#### Index capabilities
cap_is_accept  = [p <= 4 for p in myLFES.systemConcept.idxProcess]                      #  accept
cap_is_trans   = .!cap_is_accept                             # >4 transport
accept_caps    = findall(cap_is_accept)
transport_caps = findall(cap_is_trans)

# Accept capability to county (via associated resource's transformation county)
cap_county     = Vector{Union{String,Nothing}}(undef, myLFES.systemConcept.DOFS)
for j in 1:myLFES.systemConcept.DOFS
    r = myLFES.systemConcept.idxResource[j]
    if haskey(resourceID_to_transformResource, r)
        cap_county[j] = transformResource_county(resourceID_to_transformResource[r])
    else
        cap_county[j] = nothing
    end
end

# Transport capability to transport-myLFES.systemConcept.idxProcess index
# Map myLFES.systemConcept.idxProcessess id to list of transport-myLFES.systemConcept.idxProcess rows (should usually be 1:1)
process_to_transportProcess = Dict{Int, Vector{Int}}()
for k in eachindex(myLFES.transportProcess.idxProcess)
    p = myLFES.transportProcess.idxProcess[k]
    push!(get!(process_to_transportProcess, p, Int[]), k)
end

cap_to_transportProcess = Dict{Int,Int}()
for j in transport_caps
    p = myLFES.systemConcept.idxProcess[j]
    if haskey(process_to_transportProcess, p) && !isempty(process_to_transportProcess[p])
        cap_to_transportProcess[j] = process_to_transportProcess[p][1]
    end
end

check_or_stop(all(.!ismissing.(applied_df.CountyKey)),
    "Applied: some rows missing CountyKey (FIPS to LFES mapping failed).")

# check_or_stop(all(.!ismissing.(loads_df.CountyKey)),
#     "Loads: some rows missing CountyKey (County->FIPS or FIPS->LFES mapping failed).")

# Check CountyKey coverage but allow missing values for out-of-watershed counties
missing_county_keys = count(ismissing, loads_df.CountyKey)
if missing_county_keys > 0
    println("WARNING: Loads data contains $missing_county_keys rows with missing CountyKey.")
    println("This represents $(round(100*missing_county_keys/nrow(loads_df), digits=1))% of loads data.")
    println("These are counties outside the LFES watershed boundaries.")
    println("Proceeding with $(nrow(loads_df)-missing_county_keys) rows that have valid LFES mapping...")
end

println("accept_caps = ", length(accept_caps)) 
println( "transport_caps = ", length(transport_caps))
println( "total = ", length(accept_caps) + length(transport_caps))
println( "myLFES.systemConcept.DOFS = ", myLFES.systemConcept.DOFS)

#### Defining one delivery factor for each capability
# --- helpers to canonicalize names for lookups ---
strip_prefix(s::AbstractString, pref::AbstractString) = startswith(s, pref) ? s[length(pref)+1:end] : s
canon_lrs(s::AbstractString) = String(strip_prefix(String(s), "Land Segment ")) |> strip
canon_riv(s::AbstractString) = String(s)  # origin_info/dest_info already give river tokens for outlets

# --- vectors to fill: one DF per capability (use Missing for non-applicable) ---
N_capDF = Vector{Union{Missing,Float64}}(undef, myLFES.systemConcept.DOFS)
P_capDF = Vector{Union{Missing,Float64}}(undef, myLFES.systemConcept.DOFS)
fill!(N_capDF, missing); fill!(P_capDF, missing)

# small epsilon to avoid divide-by-zero when doing upstream/downstream ratios
const _EPS = 1e-12

# Canonicalize a land LRS from origin_info to the FS_LRS key
canon_land_lrs(s::AbstractString) = clean_lrs(replace(String(s), r"^Land Segment\s+" => ""))

for j in 1:myLFES.systemConcept.DOFS
    if j in accept_caps
        # Accept capabilities: no delivery factor
        continue
    end

    # Map capability -> transport process row (skip if we can't find one)
    tp_idx = get(cap_to_transportProcess, j, nothing)
    tp_idx === nothing && continue

    o = origin_info(tp_idx)
    d = dest_info(tp_idx)

    if o.kind == :land
        lrs = canon_land_lrs(get(o, :segment, ""))
        if haskey(FS_LRS, lrs)
            # exact match: product of means
            N_capDF[j] = FS_LRS[lrs].N_LTW * FS_LRS[lrs].N_STR
            P_capDF[j] = FS_LRS[lrs].P_LTW * FS_LRS[lrs].P_STR
        else
            # NEW: fallback — average over all LRS sharing the same river token
            riv = river_token(lrs)  # same tokenizer used in builder
            if haskey(FS_RIV_LS, riv)
                N_capDF[j] = FS_RIV_LS[riv].N_LTW * FS_RIV_LS[riv].N_STR
                P_capDF[j] = FS_RIV_LS[riv].P_LTW * FS_RIV_LS[riv].P_STR
            else
                N_capDF[j] = missing
                P_capDF[j] = missing
            end
        end

    elseif o.kind == :outlet
        # Outlet origin: use river->bay factors (R2B)
        riv_up = canon_riv(get(o, :segment, nothing))
        if riv_up === nothing || !haskey(FS_RIV, riv_up)
            N_capDF[j] = missing; P_capDF[j] = missing; continue
        end

        # If downstream is estuary -> just R2B(up)
        if is_estuary_destination(tp_idx)
            N_capDF[j] = FS_RIV[riv_up].R2B_N
            P_capDF[j] = FS_RIV[riv_up].R2B_P
        else
            # Otherwise ratio R2B(up) / R2B(down)
            riv_dn = canon_riv(get(d, :segment, nothing))
            if riv_dn === nothing || !haskey(FS_RIV, riv_dn)
                # If we can't identify downstream riv, fall back to R2B(up)
                N_capDF[j] = FS_RIV[riv_up].R2B_N
                P_capDF[j] = FS_RIV[riv_up].R2B_P
            else
                N_dn = FS_RIV[riv_dn].R2B_N
                P_dn = FS_RIV[riv_dn].R2B_P
                N_capDF[j] = FS_RIV[riv_up].R2B_N / max(N_dn, _EPS)
                P_capDF[j] = FS_RIV[riv_up].R2B_P / max(P_dn, _EPS)
            end
        end

    else
        # Other kinds: no delivery factor
        N_capDF[j] = missing
        P_capDF[j] = missing
    end
end

println("Per-capability delivery factors set. ",
        "N: ", count(!ismissing, N_capDF), "/", length(N_capDF),
        " | P: ", count(!ismissing, P_capDF), "/", length(P_capDF))

# One delivery factor per capability (Nx1 conceptually)
capDF = Vector{Union{Missing,Float64}}(undef, myLFES.systemConcept.DOFS)
fill!(capDF, missing)

for j in 1:myLFES.systemConcept.DOFS
    # accepts remain missing
    if j in accept_caps
        continue
    end

    tp = get(cap_to_transportProcess, j, nothing)
    tp === nothing && continue    # safety: no mapped transport process

    nutr = lowercase(String(myLFES.transportProcess.ref[tp]))  # "nitrogen" or "phosphorus"
    if nutr == "nitrogen"
        capDF[j] = N_capDF[j]     # pick the N value for this capability
    elseif nutr == "phosphorus"
        capDF[j] = P_capDF[j]     # pick the P value for this capability
    else
        capDF[j] = missing        # unexpected refinement label
    end
end

# If you explicitly want an N×1 matrix:
capDF_matrix = reshape(capDF, :, 1)

# Quick sanity:
@assert count(!ismissing, capDF) == length(transport_caps)
@assert all(j -> ismissing(capDF[j]), accept_caps)