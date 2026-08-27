pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "." as Services

Singleton {
    id: root

    // ── Weather State Properties ─────────────────────────────────────────────
    property string city: "Loading..."
    property string country: ""
    property real temp: 24
    property string tempStr: "--°"
    property real feelsLike: 24
    property string feelsLikeStr: "--°"
    property real tempMin: 20
    property real tempMax: 30
    property string tempMinMaxStr: "--° / --°"
    property real humidity: 50
    property string humidityStr: "--%"
    property real windSpeed: 10
    property string windSpeedStr: "-- km/h"
    property real precipitation: 0.0
    property string precipitationStr: "0.0 mm"
    property int weatherCode: 0
    property string condition: "Clear Sky"
    property bool isDay: true
    property string lastUpdated: ""
    property var forecast: []
    property bool isLoading: false
    property bool isReady: false
    property bool isError: false
    property string errorMessage: ""

    // ── Dynamic Icon & Color Resolvers ───────────────────────────────────────
    function getIcon(code, dayTime) {
        const d = (dayTime !== undefined) ? dayTime : root.isDay
        const c = (code !== undefined) ? code : root.weatherCode

        switch (c) {
            case 0: // Clear Sky
                return d ? "󰖙" : "󰖖" // sunny / night
            case 1: // Mainly clear
                return d ? "󰖕" : "󰖔" // partly cloudy day / night
            case 2: // Partly cloudy
                return d ? "󰖕" : "󰖔"
            case 3: // Overcast
                return "󰖐" // cloudy
            case 45: // Fog
            case 48:
                return "󰖑" // fog
            case 51: // Drizzle
            case 53:
            case 55:
            case 56:
            case 57:
                return "󰖗" // rainy / drizzle
            case 61: // Rain
            case 63:
            case 65:
            case 66:
            case 67:
            case 80:
            case 81:
            case 82:
                return "󰖘" // pouring rain
            case 71: // Snow
            case 73:
            case 75:
            case 77:
            case 85:
            case 86:
                return "󰖜" // snowy
            case 95: // Thunderstorm
            case 96:
            case 99:
                return "󰖓" // lightning / storm
            default:
                return d ? "󰖙" : "󰖖"
        }
    }

    function getColor(code, dayTime) {
        const d = (dayTime !== undefined) ? dayTime : root.isDay
        const c = (code !== undefined) ? code : root.weatherCode

        switch (c) {
            case 0:
                return d ? "#f59e0b" : "#818cf8" // golden amber / soft indigo
            case 1:
            case 2:
                return d ? "#38bdf8" : "#93c5fd" // sky blue
            case 3:
                return "#94a3b8" // slate gray
            case 45:
            case 48:
                return "#a1a1aa" // mist gray
            case 51:
            case 53:
            case 55:
            case 56:
            case 57:
            case 61:
            case 63:
            case 65:
            case 80:
            case 81:
            case 82:
                return "#38bdf8" // vibrant rain cyan
            case 71:
            case 73:
            case 75:
            case 77:
            case 85:
            case 86:
                return "#67e8f9" // ice cyan
            case 95:
            case 96:
            case 99:
                return "#a855f7" // purple thunder
            default:
                return "#38bdf8"
        }
    }

    readonly property string icon: getIcon(weatherCode, isDay)
    readonly property color weatherColor: getColor(weatherCode, isDay)

    // ── Apply Parsed Data ────────────────────────────────────────────────────
    function applyWeatherData(data) {
        if (!data || data.success === false) {
            if (data && data.error) {
                root.isError = true
                root.errorMessage = data.error
            }
            return
        }

        if (data.city) root.city = data.city
        if (data.country) root.country = data.country
        if (data.temp !== undefined) root.temp = data.temp
        if (data.tempStr) root.tempStr = data.tempStr
        if (data.feelsLike !== undefined) root.feelsLike = data.feelsLike
        if (data.feelsLikeStr) root.feelsLikeStr = data.feelsLikeStr
        if (data.tempMin !== undefined) root.tempMin = data.tempMin
        if (data.tempMax !== undefined) root.tempMax = data.tempMax
        if (data.tempMinMaxStr) root.tempMinMaxStr = data.tempMinMaxStr
        if (data.humidity !== undefined) root.humidity = data.humidity
        if (data.humidityStr) root.humidityStr = data.humidityStr
        if (data.windSpeed !== undefined) root.windSpeed = data.windSpeed
        if (data.windSpeedStr) root.windSpeedStr = data.windSpeedStr
        if (data.precipitation !== undefined) root.precipitation = data.precipitation
        if (data.precipitationStr) root.precipitationStr = data.precipitationStr
        if (data.weatherCode !== undefined) root.weatherCode = data.weatherCode
        if (data.condition) root.condition = data.condition
        if (data.isDay !== undefined) root.isDay = Boolean(data.isDay)
        if (data.lastUpdated) root.lastUpdated = data.lastUpdated
        if (data.forecast && Array.isArray(data.forecast)) root.forecast = data.forecast

        root.isReady = true
        root.isError = false
    }

    // ── Fetch Process ────────────────────────────────────────────────────────
    function refresh() {
        if (root.isLoading) return
        root.isLoading = true

        let customCity = ""
        if (Services.Config && Services.Config.weatherLocationMode === "custom" && Services.Config.weatherCustomCity) {
            customCity = Services.Config.weatherCustomCity.trim()
        }

        let unit = (Services.Config && Services.Config.weatherUnit) ? Services.Config.weatherUnit : "celsius"

        const scriptPath = Quickshell.env("HOME") + "/.config/quickshell/scripts/weather-helper.py"
        weatherProc.command = [
            "python3", scriptPath,
            "--city", customCity,
            "--unit", unit
        ]
        weatherProc.running = true
    }

    Process {
        id: weatherProc
        property string rawOutput: ""

        stdout: SplitParser {
            onRead: chunk => {
                weatherProc.rawOutput += chunk
            }
        }

        onExited: (exitCode, exitStatus) => {
            root.isLoading = false
            const trimmed = weatherProc.rawOutput.trim()
            weatherProc.rawOutput = ""
            if (trimmed.length > 0 && trimmed.startsWith("{")) {
                try {
                    const parsed = JSON.parse(trimmed)
                    root.applyWeatherData(parsed)
                } catch (e) {
                    root.isError = true
                    root.errorMessage = "JSON parse error"
                }
            } else if (exitCode !== 0) {
                root.isError = true
                root.errorMessage = "Fetch failed"
            }
        }
    }

    // ── Cache Loader on Startup ──────────────────────────────────────────────
    Process {
        id: cacheLoaderProc
        command: [
            "sh", "-c",
            "f=\"$HOME/.cache/quickshell/weather.json\"; if [ -f \"$f\" ]; then cat \"$f\"; fi"
        ]
        running: true
        property string rawOutput: ""

        stdout: SplitParser {
            onRead: chunk => {
                cacheLoaderProc.rawOutput += chunk
            }
        }

        onExited: (exitCode, exitStatus) => {
            const trimmed = cacheLoaderProc.rawOutput.trim()
            if (trimmed.length > 0 && trimmed.startsWith("{")) {
                try {
                    const cached = JSON.parse(trimmed)
                    root.applyWeatherData(cached)
                } catch (e) {}
            }
            // Trigger fresh background query shortly after startup
            initialRefreshTimer.restart()
        }
    }

    Timer {
        id: initialRefreshTimer
        interval: 1500
        repeat: false
        onTriggered: root.refresh()
    }

    // ── Periodic Auto-Refresh (every 20 minutes) ─────────────────────────────
    Timer {
        id: autoRefreshTimer
        interval: 20 * 60 * 1000 // 20 mins
        repeat: true
        running: true
        onTriggered: root.refresh()
    }
}
