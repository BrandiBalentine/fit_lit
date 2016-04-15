require "faraday"
require "json"

USER_ID = File.open("user_id.txt", "r").read.strip
HUE_USERNAME = File.open("hue_username.txt", "r").read.strip
CLIENT_SECRET = File.open("client_secret.txt", "r").read.strip
HUE_IDS = [1, 2, 3, 9]

previous_weight_log = nil
FITBIT_REQUEST = Faraday.new "https://api.fitbit.com"
HUE_REQUEST = Faraday.new "http://10.0.0.15"

def change_colors(hue, sat)
  HUE_IDS.each do |hue_id|
    HUE_REQUEST.put "/api/#{HUE_USERNAME}/lights/#{hue_id}/state", JSON.generate(hue: hue, sat: sat, on: true)
  end
end

def get_weight_log
  current_date = Time.now.strftime("%Y-%m-%d")
  weight_api_url = "/1/user/#{USER_ID}/body/log/weight/date/#{current_date}/1m.json"
  access_file = File.open "access_token.txt", "r"
  access_token = access_file.read.strip
  access_file.close
  FITBIT_REQUEST.headers["Authorization"] = "Bearer #{access_token}"
  FITBIT_REQUEST.headers["Accept-Language"] = "en_US"
  FITBIT_REQUEST.get weight_api_url
end

def reauthorize
  refresh_file = File.open "refresh_token.txt", "r+"
  refresh_token = refresh_file.read.strip
  refresh_file.close
  FITBIT_REQUEST.headers["Authorization"] = "Basic #{CLIENT_SECRET}"
  response = FITBIT_REQUEST.post "/oauth2/token", {grant_type: "refresh_token", refresh_token: refresh_token}
  tokens = JSON.parse(response.body)
  access_file = File.open "access_token.txt", "w+"
  access_file.write tokens["access_token"]
  access_file.close
  refresh_file = File.open "refresh_token.txt", "w+"
  refresh_file.write tokens["refresh_token"]
  refresh_file.close
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
    next
  end
  weight_logs = JSON.parse(response.body)
  latest_weight_log = weight_logs["weight"].last
  if previous_weight_log
    if new_weight? previous_weight_log, latest_weight_log
      if gained_weight? previous_weight_log, latest_weight_log
        change_colors 25500, 254
      elsif lost_weight? previous_weight_log, latest_weight_log
        change_colors 65280, 254
      else
        change_colors 46920, 254
      end
      sleep(10)
      change_colors 15660, 100
    end
    previous_weight_log = latest_weight_log
  else
    previous_weight_log = latest_weight_log
  end
  sleep(24)
end
