#!/bin/zsh
# The laptop's copy of the morning forecast: a backup for the GitHub job
# (.github/workflows/forecast.yml), which runs at 07:30 UTC.
#
# launchd runs this at 08:30 local time (see install_laptop_job.sh). It brings this
# folder up to date first, so if GitHub's job has already saved tomorrow's forecast,
# there's nothing to do. Otherwise it downloads the last few days with isem-data,
# forecasts with isem-forecast, and commits and pushes the two files.
#
# If both make a forecast for the same day, whichever pushes first is kept: the other's
# push fails, and this script drops its own copy. A saved forecast is never replaced.
#
# Safe to run by hand at any time. Uses the two projects' own .venv folders:
#   ISEM_DATA_PROJECT     (default ~/Developer/isem-data)
#   ISEM_FORECAST_PROJECT (default ~/Developer/isem-forecast)

set -uo pipefail  # no -e: each failure is reported, not fatal

repo=$(cd "$(dirname "$0")/.." && pwd)
data_project=${ISEM_DATA_PROJECT:-$HOME/Developer/isem-data}
forecast_project=${ISEM_FORECAST_PROJECT:-$HOME/Developer/isem-forecast}

notify() {  # a notification on the Mac; harmless if nobody is logged in
    osascript -e "display notification \"$1\" with title \"Morning forecast\"" >/dev/null 2>&1 || true
}
say() { echo "=== $(date '+%Y-%m-%d %H:%M:%S') $1 ==="; }

cd "$repo"
say "morning forecast (laptop)"

if [[ $(git branch --show-current) != main ]]; then
    say "FAILED: this folder isn't on main, so nothing is saved"
    notify "Not run: isem-live-forecasts isn't on main"
    exit 1
fi
if ! git pull -q --ff-only; then
    say "FAILED: couldn't bring this folder up to date"
    notify "Not run: git pull failed in isem-live-forecasts"
    exit 1
fi

day=$(TZ=Europe/Dublin date -v+1d +%Y-%m-%d)  # tomorrow, by the date in Ireland
if [[ -e forecasts/$day.csv ]]; then
    say "$day already has a forecast: nothing to do"
    exit 0
fi

# The newest prices and wind forecast versions. If a download fails, forecast with
# what's there: live.py says "not ready" if something it needs is missing.
(cd "$data_project" && .venv/bin/python -m isem_data \
    --datasets prices entsoe_prices wind_unit_forecasts \
    --start "$(date -u -v-3d +%Y-%m-%d)" --end "$(date -u +%Y-%m-%d)") \
    || echo "Some downloads failed; forecasting with what's there."

"$forecast_project/.venv/bin/python" -m isem_forecast.live \
    --day "$day" --data-dir "$data_project/data" --out forecasts
if [[ ! -e forecasts/$day.csv ]]; then
    say "FAILED: no forecast for $day (see above)"
    notify "No forecast for $day. See isem-live-forecasts/logs/morning.log"
    exit 1
fi

git add "forecasts/$day.csv" "forecasts/$day.json"
git commit -q -m "Forecast for $day, made $(date -u +%H:%M) UTC (laptop)"
if git pull -q --rebase && git push -q; then
    say "saved and pushed the forecast for $day"
    exit 0
fi

# The push failed. If GitHub's job got there first, its forecast stands: drop ours.
git rebase --abort >/dev/null 2>&1
git fetch -q origin
if git cat-file -e "origin/main:forecasts/$day.csv" 2>/dev/null; then
    git reset -q --hard origin/main
    say "GitHub's job saved $day first; dropped the laptop's copy"
    exit 0
fi
say "FAILED: the forecast for $day is committed here but not pushed"
notify "Forecast for $day not pushed. See isem-live-forecasts/logs/morning.log"
exit 1
