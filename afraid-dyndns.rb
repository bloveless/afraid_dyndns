#!/usr/bin/env ruby
gem 'libxml-ruby', '>= 0.8.3'
gem 'pony', '>= 1.4'

require 'net/http'
require 'fileutils'
require 'xml'
require 'pony'

# Will require a file in /etc/afraid-dyndns.conf that looks like the following file (remove the prefixed # if you are copying and pasting)
#
# AccountHash = <go to https://freedns.afraid.org/api/ while you are logged in, and click on the xml link. You will see your account has in the url as sha=###>
# Notify = <set this to what ever email you would like to have notified when the ip address changes. the sendmail command must work>
# CacheFile = /var/cache/afraid-dyndns/IP

# There will also need to be a cron job similar to the following, you can change the interval to anything you would like
# */15 * * * * root /usr/local/bin/ruby /usr/bin/afraid-dyndns.rb

# The location on the configuration file
conf_loc = '/etc/afraid-dyndns.conf'
afraid_url = 'http://freedns.afraid.org/api/?action=getdyndns&sha=%s&style=xml'

# read in conf file
def read_conf(conf_loc)
  configuration = {}
  File.open(conf_loc, 'r') do |file|
    while(line = file.gets)
      key, value = line.strip.split('=')
      configuration[key.strip] = value.strip
    end
  end
  return configuration
end

def read_cache(cache_loc)
  cache_info = ''
  begin
    File.open(cache_loc, 'r') do |file|
      while(line = file.gets)
        cache_info = line
      end
    end
  rescue Errno::ENOENT => e
  end
  cache_info
end

def get_real_ip
  return Net::HTTP.get_response(URI.parse('http://api.externalip.net/ip/')).body.strip
end

def update_afraid_dyndns(account_url)
  xml = Net::HTTP.get_response(URI.parse(account_url)).body
  parser = XML::Parser.string(xml)
  doc = parser.parse
  doc.find('//url').each do |item|
    Net::HTTP.get_response(URI.parse(item.content))
  end
end

def write_ip_to_cache(cache_file, ip_address)
  # Make the cache directory if it doesn't exist
  if(!File.directory?(cache_file.split('/')[0..-2].join('/')))
    FileUtils.mkdir_p(cache_file.split('/')[0..-2].join('/'))
  end
  File.open(cache_file, 'w') do |file|
    file.write(ip_address)
  end
end

config = read_conf(conf_loc)
cache_contents = read_cache(config['CacheFile'])
real_ip_address = get_real_ip

# Write ip address to cache
write_ip_to_cache(config['CacheFile'], real_ip_address)

if cache_contents.strip.chomp != real_ip_address.strip.chomp
  # Update afraid dyndns to let it know of the new dns settings
  update_afraid_dyndns(afraid_url % config['AccountHash'])
  # Send out update notification email
  if(!config['Notify'].blank?)
    Pony.mail({to: config['Notify'], from: config['Notify'], subject: 'IP address change', body: 'Dynamic DNS has changed', via_options: {arguments: ''}})
  end
end
