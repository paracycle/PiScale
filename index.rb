require "listen"
require "descriptive_statistics"

offset = (ARGV[0] || 0.0).to_f

Event = Struct.new(:tl, :tr, :bl, :br)
# do
#  def weight
#    [tl, tr, bl, br].map(&:to_i).sum / 100.0
#  end
#end

EV_SYN = 0x00
EV_ABS = 0x03

ABS_TR_HAT = 0x10
ABS_TL_HAT = 0x11
ABS_BR_HAT = 0x12
ABS_BL_HAT = 0x13

require 'google/apis/fitness_v1'
require 'signet/oauth_2/client'

Fitness = Google::Apis::FitnessV1

def send_to_fit(weight)
  return
  client = Signet::OAuth2::Client.new(
    :authorization_uri => 'https://accounts.google.com/o/oauth2/auth',
    :token_credential_uri =>  'https://www.googleapis.com/oauth2/v3/token',
    :client_id => '865181343027-tg2q09ap133k5i5necjkmens4dh0ocl1.apps.googleusercontent.com',
    :client_secret => '8hfiYny_vXEIWdzArLSb_lv6',
    :scope => 'https://www.googleapis.com/auth/fitness.activity.read https://www.googleapis.com/auth/fitness.activity.write https://www.googleapis.com/auth/fitness.body.read https://www.googleapis.com/auth/fitness.body.write https://www.googleapis.com/auth/fitness.location.read https://www.googleapis.com/auth/fitness.location.write',
    :refresh_token => '1/P2fUVmxgIy_3jsHznfPuTYci3CweMsrxiG69UnS4o4M'
  )
  client.refresh!
  Google::Apis::RequestOptions.default.authorization = client

  service = Fitness::FitnessService.new
  data_source_id = "raw:com.google.weight:865181343027:Nintendo:wii-balance-board:123456"

  ts = (Time.now.to_f * 1_000_000_000).to_i
  data = Fitness::Dataset.new(
    data_source_id: data_source_id,
    min_start_time_ns: ts,
    max_end_time_ns: ts,
    point: [
      Fitness::DataPoint.new(
        data_type_name: 'com.google.weight',
        start_time_nanos: ts,
        end_time_nanos: ts,
        value: [
          Fitness::Value.new(fp_val: weight)
        ]
      )
    ]
  )

  print "Posting #{weight} to Google Fit..."
  response = service.patch_user_data_source_dataset('me', data_source_id, "#{data.min_start_time_ns}-#{data.max_end_time_ns}", data)
  puts "Posted"
end

def measure(file, zero_weight = 0)
  fevent = File.open file

  measurements = []
  event = Event.new

  while measurements.size < 100 do
    raw = fevent.read(16)
    time_sec, time_usec, type, code, value = raw.unpack('llssl')
    case type
    when EV_SYN then measurements << event
    when EV_ABS
      case code
      when ABS_TR_HAT then event.tr = value
      when ABS_TL_HAT then event.tl = value
      when ABS_BR_HAT then event.br = value
      when ABS_BL_HAT then event.bl = value
      end
    end
    print '.' if measurements.size % 10 == 0
  end

  weight = [:tr, :tl, :br, :bl].map do |axis|
    measurements.map(&axis).compact.mean #.tap {|v| puts "Mean for #{axis} is #{v}" }
  end.sum / 100.0 #.tap {|v| puts "Sum is #{v}" }

  weight - zero_weight
ensure
  fevent.close
  puts ""
end

listener = Listen.to '/dev/input' do |m, a, r|
  next if a.empty?
begin
  print "Found WiiBoard. Calibrating"
  event_source = a.first
  zero_weight = measure(event_source)
  puts "Got zero weight as: #{zero_weight}"
  print "Get on the board"
  5.times {
    print "."
    sleep 1
  }
  puts ""
  weight = measure(event_source, zero_weight) + offset
  puts "-------------"
  puts "YOUR WEIGHT IS: #{weight}"
  puts "-------------"
  puts ""
  send_to_fit(weight)
ensure
  %x{echo 'disconnect 00:1E:35:FA:45:2D\nquit' | bluetoothctl}
end
end

puts "Waiting for WiiBoard"

listener.start
sleep
