require "faraday"
require "json"
require "yaml"

SETTINGS_FILE = File.expand_path "../settings.yml", __FILE__
SETTINGS = YAML.load_file SETTINGS_FILE
USER_ID = SETTINGS["fit_bit"]["user_id"]
HUE_USERNAME = SETTINGS["hue"]["username"]
CLIENT_SECRET = SETTINGS["fit_bit"]["client_secret"]
HUE_IDS = SETTINGS["hue"]["light_ids"]
DEFAULT_COLOR = SETTINGS["hue"]["default_color"]
GAINED_WEIGHT_COLOR = SETTINGS["hue"]["gained_weight_color"]
LOST_WEIGHT_COLOR = SETTINGS["hue"]["lost_weight_color"]
SAME_WEIGHT_COLOR = SETTINGS["hue"]["same_weight_color"]
DEFAULT_SAT = SETTINGS["hue"]["default_sat"]
GAINED_WEIGHT_SAT = SETTINGS["hue"]["gained_weight_sat"]
LOST_WEIGHT_SAT = SETTINGS["hue"]["lost_weight_sat"]
SAME_WEIGHT_SAT = SETTINGS["hue"]["same_weight_sat"]

previous_weight_log = nil
FITBIT_REQUEST = Faraday.new "https://api.fitbit.com"

def change_colors(hue, sat)
  HUE_IDS.each do |hue_id|
    hue_client.put "/api/#{HUE_USERNAME}/lights/#{hue_id}/state", JSON.generate(hue: hue, sat: sat, on: true)
  end
end

def get_weight_log
  current_date = Time.now.strftime("%Y-%m-%d")
  weight_api_url = "/1/user/#{USER_ID}/body/log/weight/date/#{current_date}/1m.json"
  access_token = SETTINGS["fit_bit"]["access_token"]
  FITBIT_REQUEST.headers["Authorization"] = "Bearer #{access_token}"
  FITBIT_REQUEST.headers["Accept-Language"] = "en_US"
  FITBIT_REQUEST.get weight_api_url
end

def hue_client
  internal_api = Faraday.new "https://www.meethue.com/api/nupnp"
  JSON.parse(response.get.body)[0]["internalipaddress"]
  Faraday.new "http://#{hue_ip}"
end

def reauthorize
  refresh_token = SETTINGS["fit_bit"]["refresh_token"]
  FITBIT_REQUEST.headers["Authorization"] = "Basic #{CLIENT_SECRET}"
  response = FITBIT_REQUEST.post "/oauth2/token", {grant_type: "refresh_token", refresh_token: refresh_token}
  tokens = JSON.parse(response.body)

  unless tokens["access_token"]
    return
  end

  SETTINGS["fit_bit"]["access_token"] = tokens["access_token"]
  SETTINGS["fit_bit"]["refresh_token"] = tokens["refresh_token"]

  file = File.open(SETTINGS_FILE, 'w')
  file.write SETTINGS.to_yaml
  file.close
end

def gained_weight?(previous_weight_log, latest_weight_log)
  previous_weight_log["weight"] > latest_weight_log["weight"]
end

def lost_weight?(previous_weight_log, latest_weight_log)
  previous_weight_log["weight"] < latest_weight_log["weight"]
end

def new_weight?(previous_weight_log, latest_weight_log)
  previous_weight_log["logId"] != latest_weight_log["logId"]
end

while true
  response = get_weight_log
  if response.status == 401
    reauthorize
    sleep 24
    next
  end
  weight_logs = JSON.parse(response.body)
  latest_weight_log = weight_logs["weight"].last
  if previous_weight_log
    if new_weight? previous_weight_log, latest_weight_log
      if gained_weight? previous_weight_log, latest_weight_log
        change_colors GAINED_WEIGHT_COLOR, GAINED_WEIGHT_SAT
      elsif lost_weight? previous_weight_log, latest_weight_log
        change_colors LOST_WEIGHT_COLOR, LOST_WEIGHT_SAT
      else
        change_colors SAME_WEIGHT_COLOR, SAME_WEIGHT_SAT
      end
      sleep 10
      change_colors DEFAULT_COLOR, DEFAULT_SAT
    end
    previous_weight_log = latest_weight_log
  else
    previous_weight_log = latest_weight_log
  end
  sleep 24
end
