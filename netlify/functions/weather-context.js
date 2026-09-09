const {
  json,
  parseJsonBody,
  requireMethod,
  supabaseFetch,
} = require("./_membership");

function cleanText(value, maxLength = 160) {
  return String(value || "").trim().slice(0, maxLength);
}

function cleanNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

exports.handler = async (event) => {
  const methodError = requireMethod(event, "POST");
  if (methodError) return methodError;

  try {
    const body = parseJsonBody(event);
    const anonymousUserId = cleanText(body.anonymous_user_id, 80);
    const latitude = cleanNumber(body.latitude);
    const longitude = cleanNumber(body.longitude);
    if (!anonymousUserId || body.data_consent !== true) {
      return json(400, { error: "missing_consent_or_user_id" });
    }
    if (latitude === null || longitude === null || Math.abs(latitude) > 90 || Math.abs(longitude) > 180) {
      return json(400, { error: "invalid_coordinates" });
    }

    const url = new URL("https://api.open-meteo.com/v1/forecast");
    url.searchParams.set("latitude", String(latitude));
    url.searchParams.set("longitude", String(longitude));
    url.searchParams.set("current", "temperature_2m,relative_humidity_2m,precipitation,rain,weather_code,cloud_cover,wind_speed_10m");
    url.searchParams.set("daily", "uv_index_max,daylight_duration,sunshine_duration,precipitation_probability_max");
    url.searchParams.set("forecast_days", "1");
    url.searchParams.set("timezone", "auto");

    const response = await fetch(url);
    const text = await response.text();
    const data = text ? JSON.parse(text) : {};
    if (!response.ok) {
      throw new Error(`weather_fetch_failed_${response.status}:${text.slice(0, 180)}`);
    }

    const current = data.current || {};
    const daily = data.daily || {};
    const metadata = {
      temperature_c: cleanNumber(current.temperature_2m),
      humidity_percent: cleanNumber(current.relative_humidity_2m),
      precipitation_mm: cleanNumber(current.precipitation),
      rain_mm: cleanNumber(current.rain),
      cloud_cover_percent: cleanNumber(current.cloud_cover),
      wind_speed_kmh: cleanNumber(current.wind_speed_10m),
      weather_code: cleanNumber(current.weather_code),
      uv_index_max: cleanNumber(daily.uv_index_max?.[0]),
      daylight_seconds: cleanNumber(daily.daylight_duration?.[0]),
      sunshine_seconds: cleanNumber(daily.sunshine_duration?.[0]),
      precipitation_probability_max: cleanNumber(daily.precipitation_probability_max?.[0]),
    };

    await supabaseFetch("wellness_signal_events", {
      method: "POST",
      headers: { prefer: "return=minimal" },
      body: JSON.stringify({
        anonymous_user_id: anonymousUserId,
        signal_type: "weather_context",
        value_number: metadata.temperature_c,
        value_text: weatherLabel(metadata),
        source: "open_meteo",
        metadata,
        measured_at: new Date().toISOString(),
      }),
    });

    return json(200, { ok: true, weather: metadata, label: weatherLabel(metadata) });
  } catch (error) {
    return json(500, { error: "weather_context_failed", detail: error.message });
  }
};

function weatherLabel(metadata) {
  if (metadata.temperature_c === null || metadata.temperature_c === undefined) return "Weather context";
  const rain = Number(metadata.precipitation_mm || 0) + Number(metadata.rain_mm || 0);
  const suffix = rain > 0 ? ", rain" : "";
  return `${Math.round(metadata.temperature_c)}C${suffix}`;
}
