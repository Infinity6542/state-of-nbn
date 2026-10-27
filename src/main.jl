using HTTP, JSON3, CSV, DataFrames, CairoMakie, Statistics

const ROOT = dirname(@__DIR__)
const OUTDIR = joinpath(ROOT, "outputs")
const OUTPUT1 = joinpath(OUTDIR, "output1.png")
const RELEASEENV = joinpath(ROOT, "release.env")
const BASE_URL = "https://data.gov.au/data/api/3/action"

function fetch_json(url)
    resp = HTTP.get(url)
    data = JSON3.read(resp.body)
    data.success == true || error("Data query failed: $(data.error)")
    return data.result
end

function extract_adv(tier)
    m = match(r"(\d+)(?=/|\s)", string(tier))
    return m === nothing ? 1.0 : parse(Float64, m.captures[1])
end

println("Beginning pipeline...")

release = fetch_json("$BASE_URL/package_search?fq=tags:%22Measuring%20Broadband%20Australia%22").results[1]
println("Newest dataset: $(release.name)")

m = match(r"report-(\d+)", release.name)
m === nothing && error("Could not find a report number in dataset name: $(release.name)")
number = parse(Int, m.captures[1])
tag = "v$number"

# Skip if this release already exists in GitLab
if haskey(ENV, "CI_API_V4_URL")
    r = HTTP.get("$(ENV["CI_API_V4_URL"])/projects/$(ENV["CI_PROJECT_ID"])/releases/$tag";
                 headers = ["JOB-TOKEN" => ENV["CI_JOB_TOKEN"]], status_exception = false)
    if r.status == 200
        println("Release $tag already exists, exiting...")
        exit(0)
    end
end

println("New data release $number, processing...")

df = nothing
for resource in release.resources
    if endswith(resource.url, ".csv")
        global df = CSV.read(IOBuffer(HTTP.get(resource.url).body), DataFrame)
        println("Loaded data with $(nrow(df)) rows and $(ncol(df)) columns")
    end
end
df === nothing && error("No CSV resource found")

df[!, :advertised_download] = extract_adv.(df[!, :tier])
df[!, :perf_ratio] = (df[!, "Busy hour trimmed mean download speed"] ./ df[!, :advertised_download]) .* 100.0

outages = round(mean(skipmissing(df[!, "Average daily outages"])), digits = 2)

state_df = dropmissing(df, [:state_or_territory, :perf_ratio])
state_summary = combine(groupby(state_df, :state_or_territory), 
                        :perf_ratio => (x -> mean(skipmissing(x))) => :avg_perf)

rsp_df = dropmissing(df, [:rsp, :perf_ratio])
rsp_summary = combine(groupby(rsp_df, :rsp), 
                      :perf_ratio => (x -> mean(skipmissing(x))) => :avg_perf)
sort!(rsp_summary, :avg_perf, rev = true)

println("Generating graph...")

fig = Figure(
    size = (1600, 1200),
    backgroundcolor = "#0D1B2A",
    figure_padding = (25, 25, 25, 20)
)

rowgap!(fig.layout, 15)
colgap!(fig.layout, 20)

Label(fig[1, 1:3], "The State of NBN";
      fontsize = 36, color = "#FFFFFF",
      halign = :left, tellwidth = false)

ax_state = Axis(fig[2, 1];
    title = "Performance by State/Territory (% of plan speed, higher is better)",
    titlecolor = "#FFFFFF",
    titlesize = 16,
    backgroundcolor = "#1B263B",
    yticks = (1:nrow(state_summary), string.(state_summary.state_or_territory)),
    xticklabelcolor = "#FFFFFF",
    yticklabelcolor = "#FFFFFF",
    xgridcolor = ("#FFFFFF", 0.08),
    ygridcolor = :transparent)

barplot!(ax_state, 1:nrow(state_summary), state_summary.avg_perf;
         direction = :x, color = "#2196F3", gap = 0.15)

tightlimits!(ax_state, Left())
xlims!(ax_state, 0, maximum(state_summary.avg_perf) * 1.08)
ylims!(ax_state, 0.4, nrow(state_summary) + 0.6)

ax_rsp = Axis(fig[2, 2];
    title = "Top Performing RSP (% of Plan Speed, higher is better)",
    titlecolor = "#FFFFFF",
    titlesize = 16,
    backgroundcolor = "#1B263B",
    xticks = (1:nrow(rsp_summary), string.(rsp_summary.rsp)),
    xticklabelrotation = pi / 4,
    xticklabelcolor = "#FFFFFF",
    yticklabelcolor = "#FFFFFF",
    ygridcolor = ("#FFFFFF", 0.08),
    xgridcolor = :transparent)

barplot!(ax_rsp, 1:nrow(rsp_summary), rsp_summary.avg_perf;
         color = "#00E676", gap = 0.15)

tightlimits!(ax_rsp, Bottom())
ylims!(ax_rsp, 0, maximum(rsp_summary.avg_perf) * 1.08)
xlims!(ax_rsp, 0.4, nrow(rsp_summary) + 0.6)

card = GridLayout(fig[2, 3])
Box(card[1, 1]; color = "#1B263B", strokevisible = false)

inner_card = GridLayout(card[1, 1], tellheight = false)
Label(inner_card[1, 1], "Average Daily\nOutages";
      color = "#FFFFFF", fontsize = 18, halign = :center)
Label(inner_card[2, 1], "Lower is better";
      color = "#A0AAB5", fontsize = 12, halign = :center)
Label(inner_card[3, 1], "$outages%";
      color = "#00E676", fontsize = 64, halign = :center)
rowgap!(inner_card, 10)

rowsize!(fig.layout, 1, Auto())
rowsize!(fig.layout, 2, Relative(1.0))

colsize!(fig.layout, 1, Relative(0.40))
colsize!(fig.layout, 2, Relative(0.44))
colsize!(fig.layout, 3, Relative(0.16))

println("Saving graph...")
mkpath(OUTDIR)
save(OUTPUT1, fig)

# Only written once everything above succeeded
open(RELEASEENV, "w") do io
    write(io, "RELEASE_VERSION=Report-$number\n")
    write(io, "RELEASE_TAG=$tag\n")
end

println("Completed")
