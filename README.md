# Stats
Stats/Analytics generator for IRC and Slack channels

### Demos
* [Aligned Pixels](https://kash.im/stats/aligned.html)
* [Designer Network](https://kash.im/stats/dn.html)
* [Spec.fm](https://kash.im/stats/spec.html)

### Usage

Create a `config.yml` file in the same directory as `stats.rb`

```
$ ./stats.rb 
```
Or use some other config filename

```
$ ./stats.rb other_config.yaml
```

The absolute minimal config file:

```yaml
location: "/home/Alice/irc/logs/#channel.log"
directory: no

save_location: 
database_file: 

title: 
description:
heatmap_scale:

ignore:
correct:
profiles:

```

Assumes logs are stored in the form

```
[2016-01-01 17:12:24 -0500] <joebloggs> Goodbye, cruel world!
[2016-01-01 17:12:32 -0500] * joebloggs dies
```
