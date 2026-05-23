using HTTP, JSON3, CSV, DataFrames, CairoMakie, Statistics

const base_url = "https://data.gov.au/data/api/3/action"
latest = open("latest", "r") do io
  read(io, String)
end

function fetch(url)

  resp = HTTP.get(url)

  if resp.status != 200

    error("Failed to fetch data with code: $(resp.status)")

  end


  data = JSON3.read(resp.body)

  if data.success != true

    error("Data query failed with error: $(data.error)")

  end


  return data.result

end

function extract_adv(tier)

  m = match(r"(\d+)(?=/|\s)", string(tier))

  return m === nothing ? 1.0 : parse(Float64, m.captures[1])

end


println("Beginning pipeline...")

release = fetch("$base_url/package_search?fq=tags:%22Measuring%20Broadband%20Australia%22").results[1]
if release.name == "measruing-broadband-australia-report-$latest-dataset-release"
  println("No new release, exiting...")
  exit()
else
  global latest = latest + 1
  open("latest", "w") do io
    write(io, string(latest))
  end
  println("Confirmed new data release, now tracking and performing data for release no. $latest")
end

for resource in release.resources
  if endswith(resource.url, ".csv")
    global df = CSV.read(IOBuffer(HTTP.get(resource.url).body), DataFrame)
    println("Loaded fata with $(nrow(df)) rows and $(ncol(df)) columns")
  end
end

df[!, :advertised_download] = extract_adv.(df[!, :tier])

df[!, :perf_ratio] = (df[!, "Busy hour trimmed mean download speed"] ./ df[!, :advertised_download]) .* 100.0

outages = round(mean(skipmissing(df[!, "Average daily outages"])), digits=2)

state_summary = combine(groupby(df, :state_or_territory), :perf_ratio => mean => :avg_perf)

rsp_summary = combine(groupby(dropmissing(df, :rsp), :rsp), :perf_ratio => mean => :avg_perf)

sort!(rsp_summary, :avg_perf, rev=true)

fig = Figure(size = (1600, 1200), backgroundcolor = "#0D1B2A")

rowgap!(fig.layout, 20)

colgap!(fig.layout, 20)

fig[1, 1:3] = Label(fig, "The State of NBN", fontsize = 40, color = "#FFFFFF", halign = :left)

left_pane = fig[2:4, 1] = GridLayout()

centre_pane = fig[2:4, 2] = GridLayout()

right_pane = fig[2:4, 3] = GridLayout()


outage_card = right_pane[3, 1] = Axis(fig, backgroundcolor = "#1B263B")
hidedecorations!(outage_card)

inner_card = right_pane[3, 1] = GridLayout()

Label(inner_card[1, 1], "Average Daily Outages", color = "#FFFFFF", fontsize = 16, halign = :center, valign = :bottom)
Label(inner_card[2, 1], "Lower is better", color = "#A0AAB5", fontsize = 8, halign = :center, valign = :bottom)
Label(inner_card[3, 1], "$outages%", fontsize = 70, color = "#00E676", halign = :center, valign = :top)
rowgap!(inner_card, 5)

rsp = centre_pane[1, 1] = Axis(fig, title = "Top Performing RSP (% of Plan Speed, higher is better)", titlecolor = "#FFFFFF", xticks = (1:nrow(rsp_summary), rsp_summary.rsp), backgroundcolor = "#1B263B")

barplot!(rsp, 1:nrow(rsp_summary), rsp_summary.avg_perf, color = "#00E676")
rsp.xticklabelrotation = 45.0
rsp.xticklabelcolor = "#FFFFFF"
rsp.yticklabelcolor = "#FFFFFF"

state = left_pane[1, 1] = Axis(fig, title = "Performance by State/Territory (% of plan speed, higher is better)", titlecolor = "#FFFFFF", yticks = (1:nrow(state_summary), state_summary.state_or_territory), backgroundcolor = "#1B263B")
barplot!(state, 1:nrow(state_summary), state_summary.avg_perf, direction = :x, color="#2196F3")
state.xticklabelcolor = "#FFFFFF"
state.yticklabelcolor = "#FFFFFF"

save("output1.png", fig) 
