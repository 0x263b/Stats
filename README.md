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
# eg: /home/Alice/irc/logs/file.log
# or: /home/Alice/irc/logs/directory
:location: "/home/Alice/irc/logs/#channel.log"

# Is this a directory? yes/no
:directory: no

# Full path to generated .html file
# eg: /var/www/example.com/stats.html
:save_location: 

# Full path to database file
:database_location: 

# Page info in the header of generated .html
:title: 
:description: 

# Scale for the heatmap (integer)
:heatmap_scale:

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
