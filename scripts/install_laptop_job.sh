#!/bin/zsh
# Set up (or refresh) the laptop's morning forecast as a launchd job for your user.
#
# Runs scripts/morning_forecast.sh at 07:30 and 08:15 local time every day (the second
# only matters if the first didn't get the forecast saved), appending its output to
# logs/morning.log. If the Mac is asleep, launchd runs it at its next wake.
#
# Run now:     launchctl kickstart gui/$(id -u)/com.isem-live-forecasts.morning
# Remove:      launchctl bootout gui/$(id -u)/com.isem-live-forecasts.morning
#              rm ~/Library/LaunchAgents/com.isem-live-forecasts.morning.plist

set -euo pipefail

project=$(cd "$(dirname "$0")/.." && pwd)
label=com.isem-live-forecasts.morning
plist=~/Library/LaunchAgents/$label.plist
log=$project/logs/morning.log

mkdir -p "$project/logs" ~/Library/LaunchAgents

cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$label</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/zsh</string>
        <string>$project/scripts/morning_forecast.sh</string>
    </array>
    <key>StartCalendarInterval</key>
    <array>
        <dict>
            <key>Hour</key>
            <integer>7</integer>
            <key>Minute</key>
            <integer>30</integer>
        </dict>
        <dict>
            <key>Hour</key>
            <integer>8</integer>
            <key>Minute</key>
            <integer>15</integer>
        </dict>
    </array>
    <key>StandardOutPath</key>
    <string>$log</string>
    <key>StandardErrorPath</key>
    <string>$log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$plist"
echo "Installed $label: runs at 07:30 and 08:15 every day. Log: $log"
