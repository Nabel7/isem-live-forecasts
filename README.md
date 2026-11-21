# isem-live-forecasts

Forecasts of the Irish electricity market's day-ahead prices (the SEM day-ahead auction, run by SEMOpx), **made every morning before the auction** and saved here, one day at a time, so the record can be checked.

Back-tests can always be tuned after the fact. These can't: each forecast is committed before the auction's 09:00 UTC cut-off, and never changed afterwards.

## What's here

`forecasts/` has two files for each delivery day:

| File | What's in it |
|---|---|
| `2026-11-22.csv` | Every half-hour of the day (`timestamp_utc`), for each `method`: the forecast price (`median`) in €/MWh, and for the two models an 80% range (`low`, `high`) |
| `2026-11-22.json` | When it was made, the cut-off, whether it was made in time (`in_time`), which wind forecast and which prices went in, and the versions of the models and code |

The methods:

- `chronos2_wind`: [Chronos-2](https://huggingface.co/amazon/chronos-2), Amazon's pre-trained forecasting model, given four weeks of prices and EirGrid's wind forecast.
- `lightgbm_wind`: gradient-boosted trees fitted on Irish data alone, with the same inputs.
- `yesterday` and `week_average`: the same half-hour yesterday, and its average over the last week. The bar to beat.

A delivery day runs from 23:00 to 23:00 Irish time. Times in the files are UTC.

## The rules

- **Made before the auction.** The cut-off is 09:00 UTC on the day before delivery, at least an hour before the auction closes (11:00 Irish time). A forecast made later is still saved, with `in_time: false`, and doesn't count.
- **Only what was public by then:**
  - SEMO's half-hourly prices up to two days before;
  - yesterday's prices from the [ENTSO-E Transparency Platform](https://transparency.entsoe.eu), hourly, because SEMO publishes them after the day;
  - the newest version of EirGrid's wind forecast that SEMO had listed, usually the one from the evening before.
- **Never replaced.** A day that has a forecast keeps it.

To check when a forecast was made, look at its commit: GitHub records when every commit was pushed (the repository's Activity page). The `.json` file says the same from the inside.

## How it's made

A GitHub job, [`.github/workflows/forecast.yml`](.github/workflows/forecast.yml), runs at 07:30 UTC. It downloads the data with [isem-data](https://github.com/Nabel7/isem-data), forecasts with [isem-forecast](https://github.com/Nabel7/isem-forecast) (`python -m isem_forecast.live`), and commits the result. A copy on a laptop, [`scripts/morning_forecast.sh`](scripts/morning_forecast.sh), runs at 08:30 Irish time and fills in if GitHub's job hasn't saved the day's forecast by then. If both make one, whichever is pushed first is kept, and the other is dropped. Commits made on the laptop end in "(laptop)".

How these methods did in back-tests, and how much the live inputs differ from them (almost nothing), is in [isem-forecast's README](https://github.com/Nabel7/isem-forecast#the-morning-forecast). The live record will be scored on [Open Power Lab](https://nabel7.github.io/open-power-lab/forecasts/prices).

## Licence

The forecasts are free to use under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). They're estimates, not trading advice. This project is independent and not affiliated with or endorsed by SEMO, SEMOpx, EirGrid, SONI or ENTSO-E.
