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
state_summary = combine(groupby(df, :state_or_territory), :perf_ratio => mean => :avg_perf)
rsp_summary = combine(groupby(dropmissing(df, :rsp), :rsp), :perf_ratio => mean => :avg_perf)
sort!(rsp_summary, :avg_perf, rev = true)

println("Generating graph...")

fig = Figure(size = (1600, 1200), backgroundcolor = "#0D1B2A")
rowgap!(fig.layout, 20)
colgap!(fig.layout, 20)

Label(fig[1, 1:3], "The State of NBN"; fontsize = 40, color = "#FFFFFF",
      halign = :left, tellwidth = false)

ax_state = Axis(fig[2, 1];
    title = "Performance by State/Territory (% of plan speed, higher is better)",
    titlecolor = "#FFFFFF", backgroundcolor = "#1B263B",
    yticks = (1:nrow(state_summary), string.(state_summary.state_or_territory)),
    xticklabelcolor = "#FFFFFF", yticklabelcolor = "#FFFFFF")
barplot!(ax_state, 1:nrow(state_summary), state_summary.avg_perf;
         direction = :x, color = "#2196F3")

ax_rsp = Axis(fig[2, 2];
    title = "Top Performing RSP (% of Plan Speed, higher is better)",
    titlecolor = "#FFFFFF", backgroundcolor = "#1B263B",
    xticks = (1:nrow(rsp_summary), string.(rsp_summary.rsp)),
    xticklabelrotation = pi / 4,
    xticklabelcolor = "#FFFFFF", yticklabelcolor = "#FFFFFF")
barplot!(ax_rsp, 1:nrow(rsp_summary), rsp_summary.avg_perf; color = "#00E676")

card = GridLayout(fig[2, 3])
Box(card[1:3, 1]; color = "#1B263B", strokevisible = false,
    tellwidth = false, tellheight = false)
Label(card[1, 1], "Average Daily Outages"; color = "#FFFFFF", fontsize = 16, valign = :bottom)
Label(card[2, 1], "Lower is better"; color = "#A0AAB5", fontsize = 10, valign = :bottom)
Label(card[3, 1], "$outages%"; color = "#00E676", fontsize = 70, valign = :top)
rowgap!(card, 5)
colsize!(fig.layout, 3, Relative(0.2))

println("Saving graph...")
mkpath(OUTDIR)
save(OUTPUT1, fig)

# Only written once everything above succeeded
open(RELEASEENV, "w") do io
    write(io, "RELEASE_VERSION=Report-$number\n")
    write(io, "RELEASE_TAG=$tag\n")
    write(io, "GE_JOB_ID=$(ENV["CI_JOB_ID"])\n")
end

println("Completed")
