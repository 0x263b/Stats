# Stats
Stats/Analytics generator for IRC and Slack channels

### Demos
* [Aligned Pixels, Ink. 🏇](https://kash.im/stats/aligned.html) ([Slack group](http://alignedpixels.com/), four channels)
* [Designer Network](https://kash.im/stats/dn.html) ([IRC channel](http://designers.im/))
* [NYCTech](https://kash.im/stats/nyctech.html) ([Slack group](http://www.nyctechslack.com/), four channels)
* [Spec.fm](https://kash.im/stats/spec.html) ([Slack group](http://spec.fm/), one channel)
* [Webdev Collective](https://kash.im/stats/webdev.html) ([Slack group](http://webdev-collective.clarkt.com/), one channel)

Slack provides a stats page of their own at `https://<group>.slack.com/stats` ([Example output from NYCTech](https://i.imgur.com/CUDfoPx.png))

### Usage

This script assumes your logs are formatted like so

```
[2006-01-02 15:04:05 -0700] <joebloggs> This is a message
[2006-01-02 15:04:05 -0700] * joebloggs is preforming an action
```

Take a look at [this gist](https://gist.github.com/0x263b/a296fad860edc4ea3deb7f30e0e41bc0) for how to obtain logs from Slack.

Note: This script works best if you split your logs into multiple files. ex: `#channel/YYYY-MM.log`

#### Basic usage

Edit `config.yaml` and set `:location`to your log file, then run `stats.rb`. This will create a `database.json` and `stats.html` in the script directoy.

#### Example config

```yaml
# Full path to your log file or directory (mandatory)
:location: "/home/Alice/irc/logs/#channel.log"

# Full path to generated .html file
:save_location: /var/www/example.com/stats.html

# Full path to database file
:database_location: /var/www/example.com/database.json

# Page info in the header of generated .html
:title: Some Channel
:description: Some Channel is some channel on some network

# The interval (distance between numbers) for the scale on the days heatmap. Integer
:heatmap_interval: 50

# Ignore list
:ignore:
  - somebot
  - otherbot

# Combine nick names for people who use multiple
:correct:
  joebloggs:
    - joebloggs_away
    - joebloggs_phone
  fred: 
    - fred_
    - freddy

# Url and Avatar to show in active users table
:profiles:
  joebloggs:
    :url: https://www.example.com
    :avatar: https://secure.gravatar.com/avatar/ba1e13e0887456893b07e4ee8e78aece
  fred:
    :url: http://www.something.com
    :avatar: http://www.something.com/stuff/fred.jpg
```