#!/usr/bin/env ruby
# encoding: utf-8

# Ignore the shell environment and force utf-8
# since people rarely set the environment in crontab
Encoding.default_external = "UTF-8"
Encoding.default_internal = "UTF-8"

require 'date'
require 'json'
require 'yaml'
require 'erb'
require 'open-uri'

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
    :max_hour    => nil,
    :hours       => Array.new(24, 0),
    :days        => Hash.new,
    :words       => Hash.new,
    :songs       => 0
  }
end

# clean fields from user and calculate totals/averages
def clean_user(nick)
  # nick[:words] = nick[:words].flatten.uniq
  # nick[:words].reject!{ |word| word.start_with?("http") }
  # nick[:words].uniq!
  nick[:words].reject!{ |k,v| k.to_s.start_with?("http") }

  nick[:vocabulary]  = nick[:words].length
  nick[:days_total]  = nick[:days].length
  nick[:words_line]  = nick[:word_count]/nick[:line_count].to_f
  nick[:line_length] = nick[:char_count]/nick[:line_count].to_f
  nick[:lines_day]   = nick[:line_count]/nick[:days_total].to_f
  nick[:words_day]   = nick[:word_count]/nick[:days_total].to_f
  nick[:max_hour]    = nick[:hours].max

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

    message = parsed[3]

    char_count = message.length
    words      = message.downcase.split(/\s+/)

    # All time stats
    day = timestamp.strftime("%F")
    day_sym = day.to_sym

    month = timestamp.strftime("%Y-%m")
    month_sym = month.to_sym

    # create user if none exists
    if !@database[:users].find{ |h| h[:username] == username }
      @database[:users] << new_user(username, unix_timestamp)
    end
    nick = @database[:users].find{ |h| h[:username] == username }

    if message.start_with?("!songrequest")
      begin
        ytid = /(youtu\.be\/|youtube\.com\/(watch\?(.*&)?v=|(embed|v)\/))([^\?&"'>]+)/.match(message)
        ytid = ytid[5].to_sym
        if @database[:songs].has_key?(ytid)
          @database[:songs][ytid][:plays] += 1
        else
          @database[:songs][ytid] = {:plays => 1}
        end
        nick[:songs] += 1
      rescue
        # nil
      end
    end

    # Update words/lines/characters
    nick[:line_count] += 1
    nick[:word_count] += words.length
    nick[:char_count] += char_count
    
    # nick[:words] << words
    words.each do |word|
      word = word.to_sym
      if nick[:words].has_key?(word)
        nick[:words][word] += 1
      else
        nick[:words][word] = 1
      end

      if @database[:emotes].has_key?(word)
        @database[:emotes][word] += 1
      end
    end

    @database[:channel][:line_count] += 1
    @database[:channel][:word_count] += words.length

    # Hours
    @database[:hours][timestamp.hour] += 1
    nick[:hours][timestamp.hour] += 1

    # Days
    nick[:days][day_sym] = 0 unless nick[:days].has_key?(day_sym)
    nick[:days][day_sym] += words.length

    @database[:days][day_sym] = 0 unless @database[:days].has_key?(day_sym)
    @database[:days][day_sym] += 1

    # Set first and last message dates
    nick[:first_seen] = unix_timestamp if nick[:first_seen] > unix_timestamp
    nick[:last_seen]  = unix_timestamp if nick[:last_seen] < unix_timestamp

    @database[:channel][:first] = unix_timestamp if @database[:channel][:first].nil?
    @database[:channel][:last]  = unix_timestamp if @database[:channel][:last].nil?

    @database[:channel][:first] = unix_timestamp if @database[:channel][:first] > unix_timestamp 
    @database[:channel][:last]  = unix_timestamp if @database[:channel][:last] < unix_timestamp
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

if !@config.has_key?(:emotes)
  @config[:emotes] = Array.new
end

# Twitch emotes https://twitchemotes.com/
@twitch_emotes = ["4head", "ampenergy", "ampenergycherry", "amptroppunch", "anele", "argieb8", "arsonnosexy", "asianglow", "bcwarrior", "bcouch", "babyrage", "batchest", "biblethump", "bigbrother", "blargnaut", "bloodtrail", "brainslug", "brokeback", "budblast", "budstar", "buddhabar", "cheffrank", "coolcat", "coolstorybob", "corgiderp", "curselit", "daesuppy", "dbstyle", "dansgame", "datsheffy", "dendiface", "dogface", "doritoschip", "dxabomb", "dxcat", "eagleeye", "elegiggle", "fungineer", "failfish", "frankerz", "freakinstinkin", "funrun", "futureman", "gowskull", "gingerpower", "giveplz", "grammarking", "hassaanchop", "hassanchop", "heyguys", "hotpokket", "humblelife", "itsboshytime", "jkanstyle", "jebaited", "joncarnage", "kapow", "kappa", "kappaclaus", "kappapride", "kappaross", "kappawealth", "keepo", "kevinturtle", "kippa", "kreygasm", "mvgame", "mau5", "mikehogu", "minglee", "mrdestructoid", "nerfblueblaster", "nerfredblaster", "ninjagrumpy", "nomnom", "notatk", "notlikethis", "omgscoots", "osfrog", "oskomodo", "ossloth", "ohmydog", "onehand", "opieop", "optimizeprime", "pjsalt", "pjsugar", "pmstwin", "prchase", "panicvis", "partytime", "peopleschamp", "permasmug", "petezaroll", "petezarolltie", "picomause", "pipehype", "pogchamp", "poooound", "praiseit", "primeme", "punchtrees", "raccattack", "ralpherz", "redcoat", "residentsleeper", "ritzmitz", "rlytho", "rulefive", "smorc", "ssssss", "seemsgood", "shadylulu", "shazbotstix", "smoocherz", "sobayed", "soonerlater", "stinkycheese", "stonelightning", "strawbeary", "supervinlin", "swiftrage", "tbangel", "tbcheesepull", "tbtacoleft", "tbtacoright", "tf2john", "ttours", "takenrg", "theilluminati", "theringer", "thetarfu", "thething", "thunbeast", "tinyface", "toospicy", "trihard", "twitchrpg", "uwot", "unsane", "unclenox", "vohiyo", "votenay", "voteyea", "wtruck", "wholewheat", "wutface", "youdontsay", "youwhy", "bleedpurple", "cmonbruh", "copythis", "dududu", "imglitch", "mcat", "panicbasket", "pastathat", "ripepperonis", "twitchraid"]

# Better emotes https://nightdev.com/betterttv/faces.php
@betterttv_emotes = ["(chompy)", "(poolparty)", "(puke)", ":'(", ":tf:", "angelthump", "aplis", "ariw", "baconeffect", "badass", "basedgod", "batkappa", "blackappa", "brobalt", "bttvangry", "bttvconfused", "bttvcool", "bttvgrin", "bttvhappy", "bttvheart", "bttvnice", "bttvsad", "bttvsleep", "bttvsurprised", "bttvtongue", "bttvtwink", "bttvunsure", "bttvwink", "burself", "buttersauce", "candianrage", "chaccepted", "cigrip", "concerndoge", "cruw", "d:", "datsauce", "dogewitit", "duckerz", "fapfapfap", "fcreep", "feelsamazingman", "feelsbadman", "feelsbirthdayman", "feelsgoodman", "firespeed", "fishmoley", "foreveralone", "fuckyea", "gaben", "hahaa", "hailhelix", "herbperve", "hhhehehe", "hhydro", "iamsocal", "idog", "kaged", "kappacool", "karappa", "kkona", "lul", "m&mjc", "minijulia", "motnahp", "nam", "notsquishy", "ohgod", "ohhhkee", "ohmygoodness", "pancakemix", "pedobear", "pokerface", "poledoge", "rageface", "rarepepe", "rebeccablack", "ronsmug", "rstrike", "saltycorn", "savagejerky", "sexpanda", "she'llberight", "shoopdawhoop", "soserious", "sosgame", "sourpls", "sqshy", "suchfraud", "swedswag", "taxibro", "tehpolecat", "topham", "twat", "vapenation", "vislaud", "watchusay", "whatayolk", "yetiz", "zappa"]

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
  @database[:active_users] = Array.new

  @config[:emotes].each do |emote|
    emote = emote.downcase.to_sym
    if !@database[:emotes].has_key?(emote)
      @database[:emotes][emote] = 0
    end
  end

  @twitch_emotes.each do |emote|
    emote = emote.to_sym
    if !@database[:emotes].has_key?(emote)
      @database[:emotes][emote] = 0
    end
  end

  @betterttv_emotes.each do |emote|
    emote = emote.to_sym
    if !@database[:emotes].has_key?(emote)
      @database[:emotes][emote] = 0
    end
  end
else
  # Generate a new database
  @database = Hash.new
  @database[:generated] = 0
  @database[:channel] = {
    :user_count => 0,
    :line_count => 0,
    :word_count => 0,
    :max_day    => nil,
    :mean       => 0,
    :first      => nil,
    :last       => nil
  }
  @database[:active_users] = Array.new
  @database[:users]  = Array.new
  @database[:hours]  = Array.new(24, 0)
  @database[:days]   = Hash.new
  @database[:songs]  = Hash.new
  @database[:emotes] = Hash.new

  @config[:emotes].each do |emote|
    @database[:emotes][emote.downcase.to_sym] = 0
  end

  @twitch_emotes.each do |emote|
    @database[:emotes][emote.to_sym] = 0
  end

  @betterttv_emotes.each do |emote|
    @database[:emotes][emote.to_sym] = 0
  end
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

# Alpha and Omega
first_day = Time.at(@database[:channel][:first]).utc
last_day = Time.at(@database[:channel][:last]).utc

first_day = Date.new(first_day.year, first_day.month, first_day.day)
last_day  = Date.new(last_day.year, last_day.month, last_day.day)

now = Date.today
ten_weeks_ago = (now - 70).to_datetime

# Sort users by word count
@database[:users].sort_by!{ |v| -v[:word_count] }
@database[:channel][:user_count] = @database[:users].length

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

# Find activity trends
@database[:users][0..9].each do |user|
  user[:months] = Array.new(1, 0)
  x = 0
  first_day.upto(last_day) do |date|
    if date.mday == 1
      x += 1
      user[:months][x] = 0
    end
    if !user[:days][date.strftime("%F").to_sym].nil?
      user[:months][x] += user[:days][date.strftime("%F").to_sym]
    end
  end
end

# Find active users
@database[:users].each do |user|
  word_count = 0
  days_active = 0
  # Gather activity from the past 10 weeks
  ten_weeks_ago.upto(last_day) do |date|
    date_f = date.strftime("%F").to_sym
    if user[:days].has_key?(date_f)
      word_count += user[:days][date_f]
      days_active += 1
    end
  end
  @database[:active_users] << {
    :username    => user[:username],
    :avatar      => user[:avatar],
    :url         => user[:url],
    :word_count  => word_count,
    :days_active => days_active,
    :words_day   => word_count.to_f/days_active,
    :last_seen   => user[:last_seen],
  }
end
# Purge the silent
@database[:active_users].delete_if{ |user| user[:days_active] == 0 }
# Sort by most vocal
@database[:active_users].sort_by!{ |v| -v[:word_count] }

# Peak activity
max_day = largest_hash_key(@database[:days])
@database[:channel][:max_day] = {:day => max_day[0], :lines => max_day[1]}

# initialize variables for stats.erb
@hours_max = @database[:hours].max
@days = Array.new
@weeks = Array.new
@weekdays = Array.new(7, 0) 
@labels = Array.new
@mlabels = Array.new
@total_days = (last_day - first_day).to_i

x = 0
mx = 0
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

  if date.mday == 1
    mx += 1
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
  if [92, 183, 275].include?(date.yday)
    @labels << {:x => x, :month => date.strftime("%B") }
    @mlabels << {:x => mx, :month => date.strftime("%B") }
  end
  # Happy New Year!
  if date.yday == 1
    @labels << {:x => x, :month => date.year }
    @mlabels << {:x => mx, :month => date.year }
  end
end

# Week graph
weeks = Array.new
@weeks.compact! # purge nil weeks
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
@top_users = @database[:users][0..9]
@active_users = @database[:active_users][0..9]

@top_users.each do |user|
  user[:month_max] = user[:months].max
end

@month_count = @top_users[0][:months].length

# Sort Emotes
@emotes = @database[:emotes].sort_by{ |k, v| -v }
@emotes = @emotes[0..9]

# Sort Songs
@songs = @database[:songs].sort_by { |k, v| -v[:plays] }
@songs = @songs[0..9]

@songs.each do |song|
  next if song[1].has_key?(:title)
  url = open("https://www.googleapis.com/youtube/v3/videos?part=snippet&id=#{song[0]}&key=#{@config[:youtube_api]}").read
  hashed = JSON.parse(url)
  title = hashed["items"][0]["snippet"]["title"]
  id    = hashed["items"][0]["id"]

  @database[:songs][song[0]][:title] = title
  @database[:songs][song[0]][:url] = "https://www.youtube.com/watch?v=#{id}"

  song[1][:title] = title
  song[1][:url] = "https://www.youtube.com/watch?v=#{id}"
end


# Save database
@database[:generated] = @database[:channel][:last]
File.write(@config[:database_location], JSON.pretty_generate(@database))

# Generate html
template = ERB.new(File.read("#{directory}/stats_twitch.erb"), nil, "-")
html_content = template.result(binding)
File.write(@config[:save_location], html_content)

# Fin