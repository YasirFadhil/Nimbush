#!/usr/bin/env python3
import os
import sys
import json
import re
import urllib.request
import urllib.parse
import datetime
import argparse

WEATHER_DESCRIPTIONS = {
    0: "Clear Sky",
    1: "Mainly Clear",
    2: "Partly Cloudy",
    3: "Overcast",
    45: "Foggy",
    48: "Rime Fog",
    51: "Light Drizzle",
    53: "Moderate Drizzle",
    55: "Dense Drizzle",
    56: "Light Freezing Drizzle",
    57: "Dense Freezing Drizzle",
    61: "Slight Rain",
    63: "Moderate Rain",
    65: "Heavy Rain",
    66: "Light Freezing Rain",
    67: "Heavy Freezing Rain",
    71: "Slight Snow",
    73: "Moderate Snow",
    75: "Heavy Snow",
    77: "Snow Grains",
    80: "Slight Showers",
    81: "Moderate Showers",
    82: "Violent Showers",
    85: "Slight Snow Showers",
    86: "Heavy Snow Showers",
    95: "Thunderstorm",
    96: "Thunderstorm with Hail",
    99: "Heavy Thunderstorm"
}

def get_cache_path(custom_path=None):
    if custom_path:
        return os.path.expanduser(custom_path)
    home = os.path.expanduser("~")
    cache_dir = os.path.join(home, ".cache", "quickshell")
    os.makedirs(cache_dir, exist_ok=True)
    return os.path.join(cache_dir, "weather.json")

def fetch_weather(city="", unit="celsius", cache_file=None):
    cache_path = get_cache_path(cache_file)
    lat, lon, city_name, country = None, None, "", ""

    # 1. Custom City or Coordinates Geocoding
    if city and city.strip():
        clean_city = city.strip()
        # Check if coordinates format (e.g. "-7.55, 110.81" or "51.5074, -0.1278" or "-7.55 110.81")
        coord_match = re.match(r'^\s*([+-]?\d+(?:\.\d+)?)\s*[,;\s]\s*([+-]?\d+(?:\.\d+)?)\s*$', clean_city)
        if coord_match:
            try:
                c_lat = float(coord_match.group(1))
                c_lon = float(coord_match.group(2))
                if -90 <= c_lat <= 90 and -180 <= c_lon <= 180:
                    lat = c_lat
                    lon = c_lon
                    city_name = f"{lat:.2f}°, {lon:.2f}°"
                    # Try reverse geocoding to get friendly city name
                    try:
                        rev_url = f"https://api.bigdatacloud.net/data/reverse-geocode-client?latitude={lat}&longitude={lon}&localityLanguage=en"
                        req = urllib.request.Request(rev_url, headers={"User-Agent": "quickshell-weather/1.0"})
                        rev_res = json.loads(urllib.request.urlopen(req, timeout=3).read().decode("utf-8"))
                        r_city = rev_res.get("city") or rev_res.get("locality") or rev_res.get("principalSubdivision")
                        if r_city:
                            city_name = r_city
                        country = rev_res.get("countryName", "")
                    except Exception:
                        pass
            except Exception as e:
                sys.stderr.write(f"Coordinate parse error: {e}\n")

        # If not coordinates or coord parsing failed, geocode as city name
        if lat is None or lon is None:
            geo_url = f"https://geocoding-api.open-meteo.com/v1/search?name={urllib.parse.quote(clean_city)}&count=1&language=en&format=json"
            try:
                req = urllib.request.Request(geo_url, headers={"User-Agent": "quickshell-weather/1.0"})
                geo_res = json.loads(urllib.request.urlopen(req, timeout=5).read().decode("utf-8"))
                if "results" in geo_res and len(geo_res["results"]) > 0:
                    r = geo_res["results"][0]
                    lat, lon = r.get("latitude"), r.get("longitude")
                    city_name = r.get("name", clean_city)
                    country = r.get("country", "")
            except Exception as e:
                sys.stderr.write(f"Geocoding error: {e}\n")

    # 2. IP-based Geolocation fallback
    if lat is None or lon is None:
        try:
            req = urllib.request.Request("http://ip-api.com/json", headers={"User-Agent": "quickshell-weather/1.0"})
            loc = json.loads(urllib.request.urlopen(req, timeout=4).read().decode("utf-8"))
            lat = loc.get("lat", -6.2)
            lon = loc.get("lon", 106.8)
            city_name = loc.get("city", "Local City")
            country = loc.get("country", "Indonesia")
        except Exception as e:
            sys.stderr.write(f"IP geoloc error: {e}\n")
            lat, lon = -6.2, 106.8
            city_name = "Local City"
            country = "Indonesia"

    # 3. Open-Meteo Forecast Query
    temp_unit_param = "fahrenheit" if unit == "fahrenheit" else "celsius"
    wind_unit_param = "mph" if unit == "fahrenheit" else "kmh"
    w_url = (f"https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}"
             f"&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,precipitation,weather_code,wind_speed_10m"
             f"&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=auto"
             f"&temperature_unit={temp_unit_param}&wind_speed_unit={wind_unit_param}")

    try:
        req = urllib.request.Request(w_url, headers={"User-Agent": "quickshell-weather/1.0"})
        w_data = json.loads(urllib.request.urlopen(req, timeout=6).read().decode("utf-8"))
    except Exception as e:
        sys.stderr.write(f"Open-Meteo error: {e}\n")
        # Try returning existing cache if available
        if os.path.exists(cache_path):
            try:
                with open(cache_path, "r", encoding="utf-8") as f:
                    old_data = json.load(f)
                    old_data["cached"] = True
                    print(json.dumps(old_data))
                    return
            except Exception:
                pass
        print(json.dumps({"success": False, "error": str(e)}))
        return

    cur = w_data.get("current", {})
    daily = w_data.get("daily", {})

    temp_val = round(cur.get("temperature_2m", 0))
    feels_val = round(cur.get("apparent_temperature", 0))
    u_symbol = "°F" if unit == "fahrenheit" else "°C"
    w_unit_str = "mph" if unit == "fahrenheit" else "km/h"
    code = cur.get("weather_code", 0)
    cond = WEATHER_DESCRIPTIONS.get(code, "Clear")
    humidity = round(cur.get("relative_humidity_2m", 0))
    wind = round(cur.get("wind_speed_10m", 0))
    precip = cur.get("precipitation", 0.0)

    daily_times = daily.get("time", [])
    daily_codes = daily.get("weather_code", [])
    daily_max = daily.get("temperature_2m_max", [])
    daily_min = daily.get("temperature_2m_min", [])

    today_min = round(daily_min[0]) if len(daily_min) > 0 else temp_val
    today_max = round(daily_max[0]) if len(daily_max) > 0 else temp_val

    forecast = []
    days_map = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    for i in range(min(4, len(daily_times))):
        d_str = daily_times[i]
        try:
            dt = datetime.datetime.strptime(d_str, "%Y-%m-%d")
            day_label = "Today" if i == 0 else ("Tomorrow" if i == 1 else days_map[dt.weekday()])
        except Exception:
            day_label = f"Day {i+1}"
        d_code = daily_codes[i] if i < len(daily_codes) else 0
        forecast.append({
            "day": day_label,
            "code": d_code,
            "condition": WEATHER_DESCRIPTIONS.get(d_code, "Clear"),
            "tempMin": round(daily_min[i]) if i < len(daily_min) else 0,
            "tempMax": round(daily_max[i]) if i < len(daily_max) else 0,
            "tempRange": f"{round(daily_min[i]) if i < len(daily_min) else 0}° / {round(daily_max[i]) if i < len(daily_max) else 0}°"
        })

    now_time = datetime.datetime.now().strftime("%H:%M")

    result = {
        "success": True,
        "city": city_name,
        "country": country,
        "lat": lat,
        "lon": lon,
        "unit": unit,
        "temp": temp_val,
        "tempStr": f"{temp_val}{u_symbol}",
        "feelsLike": feels_val,
        "feelsLikeStr": f"{feels_val}{u_symbol}",
        "tempMin": today_min,
        "tempMax": today_max,
        "tempMinMaxStr": f"{today_min}° / {today_max}°",
        "humidity": humidity,
        "humidityStr": f"{humidity}%",
        "windSpeed": wind,
        "windSpeedStr": f"{wind} {w_unit_str}",
        "precipitation": precip,
        "precipitationStr": f"{precip:.1f} mm",
        "weatherCode": code,
        "condition": cond,
        "isDay": cur.get("is_day", 1),
        "lastUpdated": now_time,
        "forecast": forecast
    }

    # Save cache
    try:
        with open(cache_path, "w", encoding="utf-8") as f:
            json.dump(result, f, indent=2)
    except Exception as e:
        sys.stderr.write(f"Cache write error: {e}\n")

    print(json.dumps(result))

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Quickshell Weather Helper")
    parser.add_argument("--city", type=str, default="", help="Custom city name or coordinates (lat,lon)")
    parser.add_argument("--unit", type=str, default="celsius", choices=["celsius", "fahrenheit"], help="Temperature unit")
    parser.add_argument("--cache-file", type=str, default="", help="Path to cache file")
    args = parser.parse_args()

    fetch_weather(city=args.city, unit=args.unit, cache_file=args.cache_file)
