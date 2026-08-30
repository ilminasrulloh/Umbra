<div align="center">

# 🌳 Umbra

### Jakarta's sun does not care about your commute. Umbra routes you through the shade instead of around it.

![Swift](https://img.shields.io/badge/Swift-F05138?style=flat-square&logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-0D1117?style=flat-square&logo=apple&logoColor=white)
![MapKit](https://img.shields.io/badge/MapKit-0D1117?style=flat-square&logo=apple&logoColor=white)
![WeatherKit](https://img.shields.io/badge/WeatherKit-0D1117?style=flat-square&logo=apple&logoColor=white)
![Status](https://img.shields.io/badge/status-active-brightgreen?style=flat-square)

</div>

---

## ☀️ Why Umbra

Most navigation apps optimize for one thing: getting there fast. In a city where midday pavement can feel like a stovetop, fast is not always what a pedestrian actually wants. Umbra asks a different question: what is the coolest way to get there? It trades a few minutes of walking time for a meaningfully shadier route, and shows you exactly how much sun exposure you avoided once you arrive.

## ✨ What Umbra Does

- 🧭 **Shade-first routing**: calculates walking routes that minimize direct sun exposure instead of just chasing the shortest distance
- 🔀 **Real route choices**: surfaces up to two genuinely different shaded paths alongside a standard route, so you can actually compare, not just glance at a single suggestion
- ⏱️ **Shade that knows what time it is**: the sun moves, so the shade map moves with it. Routes are recalculated against the sun's position for the current hour rather than a fixed assumption
- 🏢 **Cutting through buildings, on purpose**: routes can duck indoors when it meaningfully cuts sun exposure, with every path segment tagged as sunny, shaded, or indoor
- 🌤️ **Live weather and UV, right on the map**: an expandable panel pulls current conditions and UV index straight from WeatherKit
- 🌅 **A sun that actually moves**: a horizon-style indicator animates the sun's position across the sky between 6 AM and 6 PM
- 📍 **Real turn-by-turn navigation**: a dedicated navigation mode with instruction cards, an arrival summary, and a full route-details sheet once you are on your way

## 🧠 How the Shade-Aware Routing Works

Under the hood, Umbra treats the walkable area as a graph: nodes for intersections and points of interest, edges for the paths between them. Every edge carries a tag (sunny, shaded, or indoor) and a weight based on how exposed it is. A custom Dijkstra implementation, `RoutePlanner`, finds the lowest-exposure path between two points, then reruns the search with a penalty stacked on top of the edges it already used, so the second route it surfaces is a genuinely different option instead of a near-copy of the first.

Because shade is a moving target, the app ships a precomputed graph for every hour from 06:00 to 18:00 (`Models/MapData/*.json`). `RouteManager` swaps in whichever hour's graph matches the current time, so the route you get at 8 AM and the route you get at 1 PM are not pretending the sun stayed still.

## 🛠️ Built With

| Layer | Stack |
|---|---|
| UI | Swift, SwiftUI |
| Mapping & directions | MapKit |
| Weather & UV data | WeatherKit |
| Location | CoreLocation |
| Routing engine | Custom Dijkstra over a precomputed, time-indexed graph |

## 📁 Inside the Repo

```
Umbra/
├── App/                    → app entry point
├── Root/                   → root ContentView
├── Features/
│   ├── Map/                  → main map screen, directions sheet, route legend,
│   │                           weather/UV panel, animated sun position indicator
│   └── Navigate/              → turn-by-turn navigation, instruction cards,
│                                 arrival summary, route details
├── Models/                 → route graph structures, navigation steps, route
│                              results, and the hourly precomputed graph JSON files
└── Services/                → RouteManager & RoutePlanner (the routing engine),
                                RouteGraph, LocationManager, UserLocationIndicator
```

## 📋 Requirements

- iOS 26.5+
- Xcode 16+
- Swift 5.0
- A physical iOS device is recommended for accurate live location, heading, and WeatherKit data
- The WeatherKit capability must be enabled on the signing team/App ID (see `Umbra.entitlements`)

## 🤝 Get Involved

Built shade-aware or context-aware routing before, or just want to poke at the Dijkstra implementation? Open an issue, or reach out, always happy to compare notes on pedestrian routing.
