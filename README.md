# Stats
Stats/Analytics generator for IRC and Slack channels

### Demos
* [Aligned Pixels, Ink. 🏇](https://kash.im/stats/aligned.html) (Slack group, four channels)
* [Designer Network](https://kash.im/stats/dn.html) (IRC channel)
* [Spec.fm](https://kash.im/stats/spec.html) (Slack group, one channel, no avatars)

### Usage

This script assumes your logs are formatted like so

```
[2006-01-02 15:04:05 -0700] <joebloggs> This is a message
[2006-01-02 15:04:05 -0700] * joebloggs is preforming an action
```

#### Basic usage

Edit `config.yaml` and set `:location`to your log file, then run `stats.rb`. This will create a `database.json` and `stats.html` in the script directoy.

#### Config explained

```yaml
# Full path to your log file or directory (mandatory)
:location: 

# Full path to generated .html file
:save_location: 

# Full path to database file
:database_location: 

# Page info in the header of generated .html
:title: 
:description: 

# The interval (distance between numbers) for the scale on the days heatmap. Integer
:heatmap_interval:

# Ignore list
:ignore:
  # - somebot
  # - otherbot

# Combine nick names for people who use multiple
:correct:
  # joebloggs:
  #   - joebloggs_away
  #   - joebloggs_phone

# Url and Avatar to show in active users table
:profiles:
  # joebloggs:
  #   :url: https://www.example.com
  #   :avatar: https://secure.gravatar.com/avatar/ba1e13e0887456893b07e4ee8e78aece

```

**Example config**

```yaml
:location: "/home/Alice/irc/logs/#channel.log"

:save_location: /var/www/example.com/stats.html
:database_location: /var/www/example.com/database.json

:title: Some Channel
:description: Some Channel is some channel on some network

:heatmap_interval: 50

:ignore:
  - somebot
  - otherbot

:correct:
  joebloggs:
    - joebloggs_away
    - joebloggs_phone
  fred: 
    - fred_
    - freddy

:profiles:
  joebloggs:
    :url: https://www.example.com
    :avatar: https://secure.gravatar.com/avatar/ba1e13e0887456893b07e4ee8e78aece
  fred:
    :url: http://www.something.com
    :avatar: http://www.something.com/stuff/fred.jpg
    
```