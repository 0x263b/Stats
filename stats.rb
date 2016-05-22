#!/usr/bin/env ruby
# encoding: utf-8

# Ignore the shell environment and force utf-8
# since people rarely set the environment in crontab
Encoding.default_external = "UTF-8"
Encoding.default_internal = "UTF-8"

require 'date'
require 'cgi'
require 'json'
require 'yaml'
require 'erb'

# add .sum and .mean methods to Array
class Array
  # [1, 2, 3].sum => 6.0
  def sum
    inject(0.0) { |result, el| result + el }
  end
  # [1, 2, 3].mean => 2.0
  def mean 
    sum / size
  end
end

# returns the hash k/v with the largest value
def largest_hash_key(hash)
  hash.max_by{|k,v| v}
end

# adds commas to integers
# add_commas(12345) => 12,345
def add_commas(number)
  return number.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
end

# default user values
def new_user(nick, timestamp)
  return { 
    :username    => nick,
    :url         => nil,
    :avatar      => nil,
    :line_count  => 0,
    :word_count  => 0,
    :char_count  => 0,
    :words_line  => nil,
    :line_length => nil,
    :lines_day   => nil,
    :words_day   => nil,
    :vocabulary  => nil,
    :days_total  => nil,
    :first_seen  => timestamp,
    :last_seen   => timestamp,
    :max_day     => nil,
    :hours       => Array.new(24, 0),
    :days        => Hash.new,
    :words       => Array.new
  }
end

# clean fields from user and calculate totals/averages
def clean_user(nick)
  nick[:words] = nick[:words].flatten.uniq
  # delete urls
  nick[:words].reject!{ |word| word.start_with?("http") }
  nick[:words].uniq!

  nick[:vocabulary]  = nick[:words].length
  nick[:days_total]  = nick[:days].length
  nick[:words_line]  = nick[:word_count]/nick[:line_count].to_f
  nick[:line_length] = nick[:char_count]/nick[:line_count].to_f
  nick[:lines_day]   = nick[:line_count]/nick[:days_total].to_f
  nick[:words_day]   = nick[:word_count]/nick[:days_total].to_f
  nick[:max_day]     = largest_hash_key(nick[:days])

  return nick if @config[:profiles].nil?

  if @config[:profiles].has_key?(nick[:username])
    nick[:url] = @config[:profiles][nick[:username]][:url] if @config[:profiles][nick[:username]].has_key?(:url)
    nick[:avatar] = @config[:profiles][nick[:username]][:avatar] if @config[:profiles][nick[:username]].has_key?(:avatar)
  end

  return nick
end

# return a date object in UTC
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

    timestamp = parse_time(parsed[1])
    unix_timestamp = timestamp.strftime("%s").to_i
    # skip old lines
    return if unix_timestamp < @database[:generated]

    username = parsed[2].downcase
    username = @correct_user[username] if @correct_user.has_key?(username)
    # ignore list
    return if @config[:ignore].any? { |user| username =~ /#{user}/i }

    message = parsed[3].gsub(/[^\d\w\s]/, "")
    return if message.empty?

    char_count = message.length
    words      = message.downcase.split(/\s+/)

    # All time stats
    day = timestamp.strftime("%F")
    day_sym = day.to_sym

    # create user if none exists
    if !@database[:users].find{ |h| h[:username] == username }
      @database[:users] << new_user(username, unix_timestamp)
    end
    nick = @database[:users].find{ |h| h[:username] == username }

    # Update words/lines/characters
    nick[:line_count] += 1
    nick[:word_count] += words.length
    nick[:char_count] += char_count
    nick[:words] << words

    @database[:channel][:line_count] += 1
    @database[:channel][:word_count] += words.length

    # Days
    nick[:days][day_sym] = 0 unless nick[:days].has_key?(day_sym)
    nick[:days][day_sym] += 1

    @database[:days][day_sym] = 0 unless @database[:days].has_key?(day_sym)
    @database[:days][day_sym] += 1

    # Hours
    @database[:hours][timestamp.hour] += 1
    nick[:hours][timestamp.hour] += 1

    # Set first and last message dates
    nick[:first_seen] = unix_timestamp if nick[:first_seen] > unix_timestamp
    nick[:last_seen]  = unix_timestamp if nick[:last_seen] < unix_timestamp

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

    nick[:days][day_sym] = 0 unless nick[:days].has_key?(day_sym)
    nick[:days][day_sym] += 1

    nick[:hours][timestamp.hour] += 1
  rescue
    puts data
  end
end

def iterate_lines(line)
  # [2006-01-02 15:04:05 -0700] <joebloggs> This is a message
  message = /^\[(.+)\] <(\S+)> (.+)/i
  # [2006-01-02 15:04:05 -0700] * joebloggs is preforming an action
  action  = /^\[(.+)\] \* (\S+) (.+)/i

  if line =~ action
    parse_message(line, true)
  elsif line =~ message
    parse_message(line, false)
  end
end

# Active users defined as people who spoke in the past 10 weeks (70 days)
now = Date.today
@ten_weeks_ago = (now - 70).to_time.utc

# Parse config
config = ARGV.first
directory = File.expand_path(File.dirname(__FILE__))

if config.nil?
  @config = YAML.load_file("#{directory}/config.yaml")
else
  @config = YAML.load_file("#{directory}/#{config}")
end

if !@config.has_key?(:location) or @config[:location].nil?
  abort("please specify a log location")
end

if !@config.has_key?(:database_location) or @config[:database_location].nil?
  @config[:database_location] = "#{directory}/database.json"
end

if !@config.has_key?(:save_location) or @config[:save_location].nil?
  @config[:save_location] = "#{directory}/stats.html"
end

if !@config.has_key?(:title) or @config[:title].nil?
  @config[:title] = ""
end

if !@config.has_key?(:description) or @config[:description].nil?
  @config[:description] = ""
end

if !@config.has_key?(:heatmap_interval) or @config[:heatmap_interval].nil?
  @config[:heatmap_interval] = 100
end

if !@config.has_key?(:ignore)
  @config[:ignore] = Array.new
end
if !@config.has_key?(:correct)
  @config[:correct] = nil
end
if !@config.has_key?(:profiles)
  @config[:profiles] = nil
end

# Create a hash for username corrections
@correct_user = Hash.new
if !@config[:correct].nil?
  @config[:correct].each do |key, value|
    value.each do |v|
      @correct_user[v] = key
    end
  end
end

if File.file?(@config[:database_location])
  # Read from a database if one exists
  @database = JSON.parse(File.read(@config[:database_location]), {:symbolize_names => true})
else
  # Generate a new database
  @database = Hash.new
  @database[:generated] = 0
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
  @database[:active_users] = Array.new
  @database[:users] = Array.new
  @database[:hours] = Array.new(24, 0)
  @database[:days]  = Hash.new
end

# Begin
if File.directory?(@config[:location])
  # If we're given a directory of log files
  Dir.glob("#{@config[:location]}/**/*") do |file|
    # Skip hidden files
    next if file.start_with?(".")
    # Skip directories
    next unless File.file?(file)
    # Skip files that haven't been updated since last execution
    next if File.mtime(file).to_i < @database[:generated]

    File.open(file).each_line do |line|
      iterate_lines(line)
    end
  end
else 
  File.open(@config[:location]).each_line do |line|
    iterate_lines(line)
  end
end

# Sort users by word count
@database[:users].sort_by!{ |v| -v[:word_count] }
@database[:active_users].sort_by!{ |v| -v[:word_count] }

@database[:channel][:user_count] = @database[:users].length
@database[:channel][:active_user_count] = @database[:active_users].length

# Get average lines/day
daily_lines = Array.new
@database[:days].each do |day, lines|
  daily_lines << lines
end
@database[:channel][:mean] = daily_lines.mean

# Clean up junk
@database[:users].each do |nick|
  nick = clean_user(nick)
end
@database[:active_users].each do |nick|
  nick = clean_user(nick)
end

# Peak activity
max_day = largest_hash_key(@database[:days])
@database[:channel][:max_day] = {:day => max_day[0], :lines => max_day[1]}

# Save database
@database[:generated] = @database[:channel][:last]
File.write(@config[:database_location], JSON.pretty_generate(@database))

# initialize variables for stats.erb
@hours_max = @database[:hours].max
@days = Array.new
@weeks = Array.new
@weekdays = Array.new(7, 0) 
@labels = Array.new

first_day = Time.at(@database[:channel][:first]).utc.to_datetime
last_day = Time.at(@database[:channel][:last]).utc.to_datetime
@total_days = (last_day - first_day).to_i

x = 0
week_first = nil
week_last = nil
week_lines = 0
@weeks_max = 0

# Day heatmap
first_day.upto(last_day) do |date|
  week_first = date.strftime("%b %e") if week_first.nil?
  date_f = date.strftime("%F") # 2015-05-21

  y = date.wday
  if y == 0
    x += 1 
    week_lines = 0
    week_first = date.strftime("%b %e")
  end

  lines = @database[:days][date_f.to_sym] || 0
  week_lines += lines
  week_last = date.strftime("%b %e") # May 21

  @weeks[x] = {:x => x, :lines => week_lines, :first => week_first, :last => week_last}
  @weekdays[date.wday] += lines

  case
  when lines < @config[:heatmap_interval]
    css_class = "scale-1"
  when lines < @config[:heatmap_interval] * 2
    css_class = "scale-2"
  when lines < @config[:heatmap_interval] * 3
    css_class = "scale-3"
  when lines < @config[:heatmap_interval] * 4
    css_class = "scale-4"
  when lines < @config[:heatmap_interval] * 5
    css_class = "scale-5"
  else 
    css_class = "scale-6"
  end

  # x = week
  # y = weekday
  # date = Sat, May 21
  @days << {:x => x, :y => y, :date => date.strftime("%a, %b %e"), :class => css_class, :lines => lines}

  # April, July, October
  if [92, 183, 274].include?(date.yday)
    @labels << {:x => x, :month => date.strftime("%B") }
  end
  # Happy New Year!
  if date.yday == 1
    @labels << {:x => x, :month => date.year }
  end
end

# Week graph
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

# Grab the top 10 users
@active_users = @database[:active_users][0..9]
@top_users = @database[:users][0..9]

# Generate html
template = ERB.new(File.read("#{directory}/stats.erb"), nil, "-")
html_content = template.result(binding)
File.write(@config[:save_location], html_content)

# Fin