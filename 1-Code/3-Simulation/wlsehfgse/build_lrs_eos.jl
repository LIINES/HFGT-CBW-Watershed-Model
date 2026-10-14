# File name: build_lrs_eos.jl
# Megan Harris (2026-10 revision)
#
# Purpose: build land-river-segment (LRS) edge-of-stream (EOS) and edge-of-river (EOR) loads for
# the modeled sectors (Agriculture, Developed). CAST does not report loads at the LRS scale, so:
#   EOS[lrs, loadsource, agency] = PostBMP acres[lrs, loadsource, agency] * county EOS loading rate[loadsource, agency]
#   EOR[lrs]                     = sum over load sources of EOS[lrs, loadsource] * StreamToRiver[lrs, loadsource]
# Riparian Pasture Deposition has a load but no acres; each county's load is allocated to its LRS
# in proportion to Pasture acres. County totals of EOS_LRS reproduce CAST's county EOS (checked below).
# Assumption to state in the paper: one loading rate per load source and agency within a county.
#
# Requires (from load_data.jl / process_CAST_data.jl): basecond_df, dfact_df (with :LRS), loads_df,
# BASE_FOLDER, norm_geog, clean_lrs, tofloat, FS_LRS, EOS_N, EOS_P, EOS_EOT_SECTORS

_s(v) = string.(coalesce.(v, ""))   # strings, with missing -> ""

# CAST's loads-per-unit file lacks cell references that XLSX.jl requires, so a re-saved copy
# (same contents, written with pandas from the raw file) is read instead:
#   raw:      0-Data/1-RawData/1-ScenarioData/2024-progress/loads-per-unit-countyLoadsourceAgency.xlsx
PATH_LPU = "0-Data/2-IntermediateData/loads-per-unit-countyLoadsourceAgency-2024progress-repaired.xlsx"
lpu_df   = DataFrame(XLSX.readtable(PATH_LPU, "Source - Agency"))
LRS_SECTORS = EOS_EOT_SECTORS === nothing ? ["Agriculture", "Developed"] : EOS_EOT_SECTORS

# County loading rates (lb/acre) for the modeled sectors
lpu = filter(r -> !ismissing(r.Sector) && String(r.Sector) in LRS_SECTORS, lpu_df)
lpu_k = DataFrame(G          = norm_geog.(_s(lpu.Geography)),
                  LoadSource = _s(lpu.LoadSource),
                  Agency     = _s(lpu.Agency),
                  rateN      = tofloat.(lpu[!, Symbol("2024 Progress_NLoadRateEOS")]),
                  rateP      = tofloat.(lpu[!, Symbol("2024 Progress_PLoadRateEOS")]))

# LRS acres
bc_k = DataFrame(G          = norm_geog.(_s(basecond_df.Geography)),
                 LRS        = clean_lrs.(_s(basecond_df.LandRiverSegment)),
                 LoadSource = _s(basecond_df.LoadSource),
                 Agency     = _s(basecond_df.Agency),
                 acres      = tofloat.(basecond_df[!, Symbol("2024 Progress_PostBMPAcres")]))

# Stream-to-river factors per LRS x load source
str_k = DataFrame(LRS        = _s(dfact_df.LRS),
                  LoadSource = _s(dfact_df.LoadSource),
                  strN       = tofloat.(dfact_df.StreamToRiver_TN_Factor),
                  strP       = tofloat.(dfact_df.StreamToRiver_TP_Factor))
str_k = combine(groupby(str_k, [:LRS, :LoadSource]), :strN => first => :strN, :strP => first => :strP)

lrs_str_fallback(lrs, nut) = haskey(FS_LRS, lrs) ? (nut == :N ? FS_LRS[lrs].N_STR : FS_LRS[lrs].P_STR) : 1.0

# --- acre-based load sources ---
m = innerjoin(bc_k, lpu_k, on = [:G, :LoadSource, :Agency])
m.eosN = m.acres .* m.rateN
m.eosP = m.acres .* m.rateP
m = leftjoin(m, str_k, on = [:LRS, :LoadSource])
n_str_missing = count(ismissing, m.strN)
m.strN = [ismissing(s) ? lrs_str_fallback(l, :N) : s for (s, l) in zip(m.strN, m.LRS)]
m.strP = [ismissing(s) ? lrs_str_fallback(l, :P) : s for (s, l) in zip(m.strP, m.LRS)]

# --- Riparian Pasture Deposition: allocate county load to LRS by Pasture acres ---
rip = filter(r -> !ismissing(r.LoadSource) && String(r.LoadSource) == "Riparian Pasture Deposition" &&
                  !ismissing(r.Sector) && String(r.Sector) in LRS_SECTORS, loads_df)
rip_cty = combine(groupby(DataFrame(G = norm_geog.(_s(rip.County)),
                                    n = tofloat.(rip[!, Symbol("2024 Progress_NLoadEOS")]),
                                    p = tofloat.(rip[!, Symbol("2024 Progress_PLoadEOS")])), :G),
                  :n => sum => :n, :p => sum => :p)
past_lrs = combine(groupby(filter(r -> r.LoadSource == "Pasture", bc_k), [:G, :LRS]), :acres => sum => :acres)
past_cty = combine(groupby(past_lrs, :G), :acres => sum => :tot)
rip_alloc = innerjoin(innerjoin(past_lrs, past_cty, on = :G), rip_cty, on = :G)
rip_alloc = filter(r -> r.tot > 0, rip_alloc)
rip_alloc.eosN = rip_alloc.n .* rip_alloc.acres ./ rip_alloc.tot
rip_alloc.eosP = rip_alloc.p .* rip_alloc.acres ./ rip_alloc.tot
rip_alloc.LoadSource = fill("Riparian Pasture Deposition", nrow(rip_alloc))
rip_alloc = leftjoin(rip_alloc, str_k, on = [:LRS, :LoadSource])
rip_alloc.strN = [ismissing(s) ? lrs_str_fallback(l, :N) : s for (s, l) in zip(rip_alloc.strN, rip_alloc.LRS)]
rip_alloc.strP = [ismissing(s) ? lrs_str_fallback(l, :P) : s for (s, l) in zip(rip_alloc.strP, rip_alloc.LRS)]
rip_unallocated_N = sum(rip_cty.n) - sum(rip_alloc.eosN; init = 0.0)

# --- LRS totals ---
EOS_LRS_N = Dict{String,Float64}(); EOS_LRS_P = Dict{String,Float64}()
EOR_LRS_N = Dict{String,Float64}(); EOR_LRS_P = Dict{String,Float64}()
for df_ in (m, rip_alloc), r in eachrow(df_)
    EOS_LRS_N[r.LRS] = get(EOS_LRS_N, r.LRS, 0.0) + r.eosN
    EOS_LRS_P[r.LRS] = get(EOS_LRS_P, r.LRS, 0.0) + r.eosP
    EOR_LRS_N[r.LRS] = get(EOR_LRS_N, r.LRS, 0.0) + r.eosN * r.strN
    EOR_LRS_P[r.LRS] = get(EOR_LRS_P, r.LRS, 0.0) + r.eosP * r.strP
end

println("LRS loads built for ", length(EOS_LRS_N), " land-river segments (sectors: ", join(LRS_SECTORS, ", "), ")")
println("  EOS from LRS (M lb): N=", round(sum(values(EOS_LRS_N))/1e6; digits=2), " P=", round(sum(values(EOS_LRS_P))/1e6; digits=3),
        "  vs county EOS: N=", round(sum(values(EOS_N))/1e6; digits=2), " P=", round(sum(values(EOS_P))/1e6; digits=3))
println("  EOR from LRS (M lb): N=", round(sum(values(EOR_LRS_N))/1e6; digits=2), " P=", round(sum(values(EOR_LRS_P))/1e6; digits=3))
println("  rows without a stream-to-river factor (LRS fallback used): ", n_str_missing,
        " | riparian N not allocated (no pasture acres): ", round(rip_unallocated_N/1e6; digits=3), " M lb")
