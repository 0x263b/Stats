#!/usr/bin/env ruby
# encoding: utf-8
require 'date'
require 'cgi'
require 'json'
require 'yaml'
require 'erb'

config = ARGV.first
directory = File.expand_path(File.dirname(__FILE__))

if config.nil?
  @config = YAML.load_file("#{directory}/config.yml")
else
  @config = YAML.load_file("#{directory}/#{config}")
end

if @config["database_location"].nil?
  @config["database_location"] = "#{directory}/database.json"
end

if @config["save_location"].nil?
  @config["database_location"] = "#{directory}/stats.html"
end


now = Date.today
@ten_weeks_ago = (now - 70).to_time.utc

class Array
  def sum
    inject(0.0) { |result, el| result + el }
  end

  def mean 
    sum / size
  end
end

def largest_hash_key(hash)
  hash.max_by{|k,v| v}
end

def add_commas(number)
  return number.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
end

def save_database
  File.open(@config["database_location"], "w") do |file|
    file.write(JSON.pretty_generate(@database))
  end
end

@correct_user = Hash.new
if !@config["correct"].nil?
  @config["correct"].each do |key, value|
    value.each do |v|
      @correct_user[v] = key
    end
  end
end

@database = Hash.new

@database[:channel] = {
  :user_count => 0,
  :active_user_count => 0,
  :line_count => 0,
  :word_count => 0,
  :max_day    => nil,
  :mean       => 0,
  :first      => nil,
  :last       => nil
}
@database[:users] = Array.new
@database[:active_users] = Array.new

@database[:days]  = Hash.new
@database[:hours] = Array.new(24, 0)

def new_user(nick, timestamp)
  return { 
    :username    => nick,
    :url         => nil,
    :avatar      => nil,
    :line_count  => 0,
    :word_count  => 0,
    :char_count  => 0,
    :words_line  => 0,
    :line_length => 0,
    :lines_day   => 0,
    :words_day   => 0,
    :vocabulary  => 0,
    :days_total  => 0,
    :first_seen  => timestamp,
    :last_seen   => timestamp,
    :max_day     => nil,
    :hours       => Array.new(24, 0),
    :days        => Hash.new,
    :words       => Array.new
  }
end

def median(array)
  sorted = array.sort
  len = sorted.length
  return (sorted[(len - 1) / 2] + sorted[len / 2]) / 2.0
end

def parse_time(data)
  return DateTime.strptime(data, "%F %T %z").to_time.utc
end

def parse_message(data, action)
  begin
    if action
      parsed = /^\[(.+)\] \* (\S+) (.+)/.match(data)
    else
      parsed = /^\[(.+)\] <(\S+)> (.+)/.match(data)
    end

    username = parsed[2].downcase
    username = @correct_user[username] if @correct_user.has_key?(username)

    timestamp = parse_time(parsed[1])
    unix_timestamp = timestamp.strftime("%s").to_i

    message    = (parsed[3].nil? ? parsed[3] : CGI::escapeHTML(parsed[3].strip))
    char_count = parsed[3].length
    words      = parsed[3].downcase.split(" ")

    # ignore list
    return if @config["ignore"].any? { |user| username =~ /#{user}/i }

    # All time stats
    day = timestamp.strftime("%F")

    if !@database[:users].find{ |h| h[:username] == username }
      @database[:users] << new_user(username, unix_timestamp)
    end

    nick = @database[:users].find{ |h| h[:username] == username }

    nick[:first_seen] = unix_timestamp if nick[:first_seen] > unix_timestamp
    nick[:last_seen]  = unix_timestamp if nick[:last_seen] < unix_timestamp

    nick[:line_count] += 1
    nick[:word_count] += words.length
    nick[:char_count] += char_count
    nick[:words] << words

    @database[:channel][:line_count] += 1
    @database[:channel][:word_count] += words.length

    # Days
    nick[:days][day] = 0 unless nick[:days].has_key?(day)
    nick[:days][day] += 1

    @database[:days][day] = 0 unless @database[:days].has_key?(day)
    @database[:days][day] += 1

    # Hours
    @database[:hours][timestamp.hour] += 1
    nick[:hours][timestamp.hour] += 1

    # Set ends
    @database[:channel][:first] = unix_timestamp if @database[:channel][:first].nil?
    @database[:channel][:last]  = unix_timestamp if @database[:channel][:last].nil?

    @database[:channel][:first] = unix_timestamp if @database[:channel][:first] > unix_timestamp 
    @database[:channel][:last]  = unix_timestamp if @database[:channel][:last] < unix_timestamp

    # Active stats
    return if timestamp < @ten_weeks_ago

    if !@database[:active_users].find{ |h| h[:username] == username }
      @database[:active_users] << new_user(username, unix_timestamp)
    end
    nick = @database[:active_users].find{ |h| h[:username] == username }

    nick[:first_seen] = unix_timestamp if nick[:first_seen] > unix_timestamp
    nick[:last_seen]  = unix_timestamp if nick[:last_seen] < unix_timestamp

    nick[:line_count] += 1
    nick[:word_count] += words.length
    nick[:char_count] += char_count
    nick[:words] << words

    nick[:days][day] = 0 unless nick[:days].has_key?(day)
    nick[:days][day] += 1

    nick[:hours][timestamp.hour] += 1
  rescue
    puts data
  end
end

def iterate_lines(line)
  message = /^\[(.+)\] <(\S+)> (.+)/i
  action  = /^\[(.+)\] \* (\S+) (.+)/i

  if line =~ action
    parse_message(line, true)
  elsif line =~ message
    parse_message(line, false)
  end
end

# Begin
if @config["directory"]
  Dir.glob("#{@config["location"]}/**/*") do |file|
    next if file.start_with?(".")
    next unless File.file?(file)

    File.open(file).each_line do |line|
      iterate_lines(line)
    end
  end
else 
  File.open(@config["location"]).each_line do |line|
    iterate_lines(line)
  end
end

@database[:users].sort_by!{ |v| -v[:word_count] }
@database[:active_users].sort_by!{ |v| -v[:word_count] }

@database[:channel][:user_count] = @database[:users].length
@database[:channel][:active_user_count] = @database[:active_users].length

daily_lines = Array.new

@database[:days].each do |day, lines|
  daily_lines << lines
end

def clean_user(nick)
  nick[:words].flatten!.uniq!

  nick[:words].each { |word| word.gsub!(/[^\d\w]/, "") }
  nick[:words].reject!{ |word| word.start_with?("http") }

  nick[:words].uniq!
  nick[:vocabulary] = nick[:words].length

  nick[:days_total]  = nick[:days].length
  nick[:words_line]  = nick[:word_count]/nick[:line_count].to_f
  nick[:line_length] = nick[:char_count]/nick[:line_count].to_f
  nick[:lines_day]   = nick[:line_count]/nick[:days_total].to_f
  nick[:words_day]   = nick[:word_count]/nick[:days_total].to_f
  nick[:max_day]     = largest_hash_key(nick[:days])

  return nick if @config["profiles"].nil?

  if @config["profiles"].has_key?(nick[:username])
    nick[:url] = @config["profiles"][nick[:username]]["url"] if @config["profiles"][nick[:username]].has_key?("url")
    nick[:avatar] = @config["profiles"][nick[:username]]["avatar"] if @config["profiles"][nick[:username]].has_key?("avatar")
  end

  return nick
end

@database[:users].each do |nick|
  nick = clean_user(nick)
end

@database[:active_users].each do |nick|
  nick = clean_user(nick)
end

@database[:channel][:mean] = daily_lines.mean

max_day = largest_hash_key(@database[:days])

@database[:channel][:max_day] = {:day => max_day[0], :lines => max_day[1]}

save_database

if @config["heatmap_scale"].nil?
  @day_scale = 100
else 
  @day_scale = @config["heatmap_scale"]
end

@hours_max = @database[:hours].max
@days   = Array.new
@weeks  = Array.new
@weekdays = Array.new(7, 0) 
@labels = Array.new

first_day = Time.at(@database[:channel][:first]).utc.to_datetime
last_day  = Time.at(@database[:channel][:last]).utc.to_datetime

first_year = first_day.year
last_year  = last_day.year

x = 0
week_first = nil
week_last = nil
week_lines = 0
@weeks_max = 0

@total_days = (last_day - first_day).to_i

first_day.upto(last_day) do |date|
  date_f = date.strftime("%F")

  y = date.wday
  if y == 0
    x += 1 
    week_lines = 0
    week_first = date.strftime("%b %e")
  end

  lines = @database[:days][date_f] || 0
  week_lines += lines
  week_last = date.strftime("%b %e")

  @weeks[x] = {:x => x, :lines => week_lines, :first => week_first, :last => week_last}
  @weekdays[date.wday] += lines

  case
  when lines < @day_scale
    css_class = "scale-1"
  when lines < @day_scale * 2
    css_class = "scale-2"
  when lines < @day_scale * 3
    css_class = "scale-3"
  when lines < @day_scale * 4
    css_class = "scale-4"
  when lines < @day_scale * 5
    css_class = "scale-5"
  else 
    css_class = "scale-6"
  end

  @days << {:x => x, :y => y, :date => date.strftime("%a, %b %e"), :class => css_class, :lines => lines}

  if [92, 183, 274].include?(date.yday)
    @labels << {:x => x, :month => date.strftime("%B") }
  end

  if date.yday == 1
    @labels << {:x => x, :month => date.year }
  end
end

weeks = Array.new
@weeks.each do |week|
  lines = week[:lines]
  if lines > @weeks_max
    @weeks_max = lines
  end

  weeks << week[:lines]
end

@weeks_mean = weeks.mean
@weekdays_max = @weekdays.max

@active_users = @database[:active_users][0..9]
@top_users = @database[:users][0..9]

template = ERB.new(File.read("#{directory}/stats.erb"), nil, "-")
html_content = template.result(binding)

File.open(@config["save_location"], "w") do |file|
  file.write html_content
end

