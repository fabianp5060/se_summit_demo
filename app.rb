#
STDOUT.sync = true

require 'nexmo'
require 'sinatra'
require 'json'
require 'dm-core'
require 'dm-migrations'
require 'logger'

################################################
# Database Specific Controls
################################################

# Configure in-memory DB
DataMapper.setup(:default, "sqlite3://#{Dir.pwd}/auth.db")

class UserDB
	include DataMapper::Resource
	property :id, Serial
	property :first_name, String
	property :last_name, String
	property :phone_number, String
	property :dtmf, String
	property :convo_id, String

	def self.get_caller_by_convo_id(convo_id)
		puts "#{__method__}: looing for: #{convo_id}"
		first(convo_id: convo_id)
	end	

end

UserDB.auto_migrate!
puts "Cleard DB on start: #{UserDB.destroy}"

################################################
# Web Front End
################################################

get '/users' do
	@title = "SE Summit Testing: Call #{$did} to get started"
	@db = UserDB.all

	puts "#{__method__}: users info: #{@db.inspect}"
	erb :users
end

post '/users' do
	puts "params: #{params}"
	add_db = UserDB.first_or_create(
		first_name: params[:first_name],
		last_name: params[:last_name],
		phone_number: params[:phone_number]
	)
	redirect '/users'
end

################################################
# Nexmo Server Webhooks
################################################
get '/answer_sesummit' do 
	puts "#{__method__} | Make sure Things are working PARAMS | #{params}"
	db = UserDB.first_or_create(
		phone_number: params['from'],
		)
	db.convo_id = params[:conversation_uuid]
	db.dtmf = 0
	db.save

	puts "#{__method__} Inspecting db entry: #{db.inspect}"
	return ncco_play_welcome
end

post '/event_sesummit' do
	request_payload = JSON.parse(request.body.read)
	puts "#{__method__} | --\n#{request_payload}\n--"
	status 200
end

post '/event_sesummit_ivr' do
	request_payload = JSON.parse(request.body.read, symbolize_names: true)
	puts "#{__method__} | --\n#{request_payload}\n-- DTMF IS A INT? #{request_payload[:dtmf].is_a?(Integer)}"

	db = UserDB.get_caller_by_convo_id(request_payload[:conversation_uuid])
	db.dtmf = request_payload[:dtmf].to_i
	db.save
	puts "#{__method__}: My db result: #{db.inspect}"

	ncco_to_play = nil
	case request_payload[:dtmf]
	when "1"
		ncco_to_play = ncco_play_hours
		puts "#{__method__} | Looking for hours: \n#{JSON.pretty_generate(ncco_to_play)}\n"
	when "2"
		ncco_to_play = ncco_connect_smartnumber
		puts "#{__method__} | Trying to conect: \n#{JSON.pretty_generate(ncco_to_play)}\n"
	else
		ncco_to_play = ncco_dtmf_error
		puts "#{__method__} | Made an error: \n#{JSON.pretty_generate(ncco_to_play)}\n"		
	end

	return ncco_to_play
end

################################################
# Nexmo NCCO's
################################################

def ncco_play_welcome
	content_type :json
	return [
		{
			"action": "talk",
			"text": "Welcome to Vandelay Industries.  The leader in Importing and Exporting.  If you’d like to hear our store hours press 1 or press 2 if you’d like to speak with one of our sales representatives."
		},
		{
			"action": "input",
			"submitOnHash": true,
			"maxDigits": 1,	
			"timeOut": 10,		
			"eventUrl": ["#{$web_server}/event_sesummit_ivr"]
		}
	].to_json
end

def ncco_play_hours
	content_type :json
	return [
		{
			"action": "talk",
			"text": "Thank you for checking our hours of operations.  We are currently open.  At some point in the future we will be closed and open again afterwards"
		}	
	].to_json

end

def ncco_connect_smartnumber
	content_type :json
	return [
		{
			"action": "talk",
			"text": "Please wait while we connect you to Bob"
		},
		{
		    "action": "connect",
		    "eventUrl": ["#{$web_server}/event_sesummit"],
		    "timeout": "30",
		    "from": $did,
		    "endpoint": [
		  		{
					"type": "vbc",
		        	"extension": $vbc_extension,
		  		}
		    ]
		}
	].to_json
end

def ncco_dtmf_error
	content_type :json
	return [

	].to_json
end	


################################################
# Backend Server Code
################################################

# Update with ngrok/aws web server address
def update_webserver(app_id,web_server,app_name)
	puts "My vars: ID: #{app_id}, WS: #{web_server}, NAME: #{app_name}"
	$okta_redirect = "#{$web_server}/results"
	application = $client.applications.update(
		app_id,
		{
			type: "voice",
			name: app_name,
			answer_url: "#{$web_server}/answer_sesummit", 
			event_url: "#{$web_server}/event_sesummit"
		}
	)
	puts "Updated nexmo application name:\n  #{application.name}\nwith webhooks:\n  #{application.voice.webhooks[0].endpoint}\n  #{application.voice.webhooks[1].endpoint}"
end

# Setup Demo Environment
key = ENV['NEXMO_API_KEY']
sec = ENV['NEXMO_API_SECRET']
app_key = ENV['NEXMO_APPLICATION_PRIVATE_KEY_PATH']

# Nexmo App Specific Details
app_name = ENV['SMART_APP_NAME']
app_id = ENV['SMART_APP_ID']
$did = ENV['SMART_DID']
$vbc_extension = ENV['SMART_EXT']

$web_server = ENV['SMART_WEB_URL'] || JSON.parse(Net::HTTP.get(URI('http://127.0.0.1:4040/api/tunnels')))['tunnels'][0]['public_url']

$client = Nexmo::Client.new(
  api_key: key,
  api_secret: sec,
  application_id: app_id,
  private_key: File.read("#{app_key}")
)

update_webserver(app_id,$web_server,app_name)

UserDB.auto_migrate!