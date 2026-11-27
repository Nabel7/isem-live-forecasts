#!/bin/zsh
# The laptop's spare try at the morning forecast.
#
# GitHub's job (.github/workflows/forecast.yml) tries six times overnight, and usually
# has the forecast saved before this runs. launchd runs this at 07:30 and again at 08:15
# local time (see install_laptop_job.sh). If the next day's forecast is already saved
# with SEMO's wind forecast, there's nothing to do. Otherwise (no forecast yet, or one
# made with the backup wind or none, which a better one may replace before the cut-off):
#
# 1. It starts GitHub's job by hand and waits up to WAIT_MINUTES for it to save the
#    forecast. A run started by hand begins within a minute or two, and does the work on
#    GitHub's servers.
# 2. If GitHub hasn't saved it by then, it forecasts here: downloads the last few days
#    with isem-data, forecasts with isem-forecast, and commits and pushes the two files.
#
# The Mac is kept awake while this runs, but only while it's plugged in: on battery with
# the lid shut, macOS sleeps anyway, waking for seconds at a time (23 Nov 2026: asleep
# from 07:38 until the lid was opened at 09:40). The wait below counts real time, so a
# sleep can't stretch it.
#
# If both make a forecast for the same day, whichever pushes first is kept: the other's
# push fails, and this script drops its own copy. Nothing is replaced after the cut-off.
#
# Safe to run by hand at any time. Uses the two projects' own .venv folders:
#   ISEM_DATA_PROJECT     (default ~/Developer/isem-data)
#   ISEM_FORECAST_PROJECT (default ~/Developer/isem-forecast)

set -uo pipefail  # no -e: each failure is reported, not fatal

if [[ -z ${MORNING_AWAKE:-} ]]; then  # run again under caffeinate, which keeps the Mac awake
    MORNING_AWAKE=1 exec /usr/bin/caffeinate -i -s /bin/zsh "$0" "$@"
fi
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"  # gh, which launchd's PATH lacks
WAIT_MINUTES=${WAIT_MINUTES:-15}

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

# The next delivery day whose cut-off (09:00 UTC the day before) is still ahead, as in
# GitHub's job: tomorrow before 09:00 UTC, the day after once tomorrow's has passed.
if [[ $(date -u +%H) < 09 ]]; then
    day=$(date -u -v+1d +%Y-%m-%d)
else
    day=$(date -u -v+2d +%Y-%m-%d)
fi
# Is there anything to do? isem-forecast decides: exit 3 means the saved forecast stands.
todo() {
    "$forecast_project/.venv/bin/python" -m isem_forecast.live --check --day "$day" --out forecasts
    (( $? != 3 ))
}
if ! todo; then
    exit 0
fi

# 1. Start GitHub's job, and give it time to save the forecast.
saved() { git pull -q --ff-only && ! todo >/dev/null; }
if gh workflow run forecast.yml -R Nabel7/isem-live-forecasts >/dev/null 2>&1; then
    say "started GitHub's job; waiting up to $WAIT_MINUTES minutes for it"
    deadline=$(( $(date +%s) + WAIT_MINUTES * 60 ))
    while (( $(date +%s) < deadline )); do
        sleep 30
        if saved; then
            say "GitHub's job saved $day: nothing more to do"
            exit 0
        fi
    done
    say "GitHub's job hasn't saved $day: forecasting here"
else
    say "couldn't start GitHub's job: forecasting here"
fi

# 2. Forecast here. The newest prices and wind forecast versions. If a download fails, forecast with
# what's there: live.py says "not ready" if something it needs is missing.
(cd "$data_project" && .venv/bin/python -m isem_data \
    --datasets prices entsoe_prices wind_unit_forecasts entsoe_wind_forecasts \
    --start "$(date -u -v-3d +%Y-%m-%d)" --end "$(date -u +%Y-%m-%d)") \
    || echo "Some downloads failed; forecasting with what's there."

"$forecast_project/.venv/bin/python" -m isem_forecast.live \
    --day "$day" --data-dir "$data_project/data" --out forecasts
if [[ ! -e forecasts/$day.csv ]]; then
    say "FAILED: no forecast for $day (see above)"
    notify "No forecast for $day. See isem-live-forecasts/logs/morning.log"
    exit 1
fi
if [[ -z $(git status --porcelain -- "forecasts/$day.csv" "forecasts/$day.json") ]]; then
    say "the saved forecast for $day stands: no better wind input here"
    exit 0
fi

git add "forecasts/$day.csv" "forecasts/$day.json"
if git diff --cached --name-status | grep -q "^M"; then
    what="Better forecast for $day (replaces the earlier one)"
else
    what="Forecast for $day"
fi
git commit -q -m "$what, made $(date -u +%H:%M) UTC (laptop)"
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
