# State of NBN
## Background
The NBN is essentially Australia's wholesale provider for broadband infrastructure. It is operated by [NBN Co](https://www.nbnco.com.au/) and is closely monitored by the [ACCC](https://www.accc.gov.au/), Australia's national competition, consumer and fair trade watchdog. As part of their monitoring, they've partnered with SamKnows, now part of [Cisco ThousandEyes](https://www.thousandeyes.com/) to allow households to install "white boxes" that monitor for outages and internet speed. I take this data and process it to make a bento box grid of statistics showing where we currently are.
## The Project
This project creates a small data dashboard to show the NBN's performance. It is currently a WIP.
## Usage
Run these commands to get started:
```
git clone https://github.com/Infinity6542/state-of-nbn.git && cd state-of-nbn/src
julia --project=. main.jl
```

The output will be stored in `state-of-nbn/outputs` as `output1.png`.
