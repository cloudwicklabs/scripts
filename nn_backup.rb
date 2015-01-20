#!/usr/bin/env ruby
#
# Author:: Ashrith Mekala
# Description:: Script to bacup Hadoop's metadata from NameNode
# Version:: 0.1
# Tested Ruby Versions: 1.9.3
#
# OPTIMIZE - Make this script auto-detect whether running from namenode
#            if so, check the edits transactions to copy to instead of
#            relying on user passing starting and ending transactions
#
# Copyright 2013, Cloudwick, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'optparse'
require 'open-uri'
require 'timeout'
require 'fileutils'
require 'tempfile'
require 'date'
require 'zlib'

options = {}
optparse = OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [OPTIONS]"

  options[:verbose] = false
  opts.on( '-v', '--verbose', 'Output more information') do
    options[:verbose] = true
  end

  opts.on('-d', '--dirs DIR1,DIR2,DIR3', Array, 'List of directories to store the metadata to') do |d|
    options[:dirs] = d
  end

  opts.on('-n', '--namenode HOST', 'NameNode hostname or IpAddress') do |n|
    options[:namenode] = n
  end

  options[:port] = 50070
  opts.on('-p', '--port PORT', 'NameNode port number') do |p|
    options[:port] = p
  end

  # options[:start_trans_id] = 1
  opts.on('-s', '--start-trans-id START_TRANS_ID', Numeric, 'Start transaction id for edits file, required for hadoop > 2.0.0') do |s|
    options[:start_trans_id] = s
  end

  # options[:end_trans_id] = -1
  opts.on('-e', '--end-trans-id END_TRANS_ID', Numeric, 'End transaction id for edits file, required for hadoop > 2.0.0') do |e|
    options[:end_trans_id] = e
  end

  options[:retention_days] = 5
  opts.on('-r', '--retention-days', Numeric, 'How many days do we have to keep the files, default: 5 days') do |r|
    options[:retention_days] = r
  end

  opts.on('-h', '--help', 'Display this screen') do
    puts opts
    exit
  end
end

begin
  optparse.parse!
  mandatory = [:dirs, :namenode]
  missing = mandatory.select { |param| options[param].nil? }
  unless missing.empty?
    puts "Missing options: #{missing.join(', ')}"
    puts optparse
    exit
  end
rescue OptionParser::InvalidOption, OptionParser::MissingArgument
  puts $!.to_s
  puts optparse
  exit
end

puts options
$rwd = Dir.pwd
puts $rwd

def compress_file (src_file)
  Zlib::GzipWriter.open("#{File.basename(src_file)}.gz") do |gz|
   File.open(src_file) do |fp|
     while chunk = fp.read(16 * 1024) do
       gz.write chunk
     end
   end
   gz.close
  end
end

def check_download_dirs (dirs)
  dirs.each do |dir|
    unless File.directory? dir
      FileUtils::mkdir_p dir
    end
  end
end

def file_age (name)
  (Time.now - File.ctime(name))/(24 * 3600)
end

def delete_on_retention (dirs, file_pattern, days)
  # `find -atime +#{days} -name "#{file_regex}" -exec rm {} \\;`
  dirs.each do |dir|
    Dir.chdir(dir)
    Dir.glob(file_pattern).each do |file|
      File.delete(file) if file_age(file) > days
    end
  end
  Dir.chdir($rwd)
end

def get_namenode_webpage_contents (namenode_host, namenode_port)
  uri = "http://#{namenode_host}:#{namenode_port}/dfshealth.jsp"
  begin
    open(uri) { |f| f.read }
  rescue Timeout::Error
    puts "The request for a page at #{uri} timed out...exiting."
    exit
  rescue OpenURI::HTTPError => e
    puts "The request for a page at #{uri} returned an error. #{e.message}"
    exit
  end
end

# Get hadoop's version from NameNode's web page
def get_hadoop_version (namenode_wp_contents)
  namenode_wp_contents.match(/Version:<\/td><td>(.*),/i).captures
end

# Get the current namenode transaction id
def get_current_transaction_id (namenode_wp_contents)
  namenode_wp_contents.match(/<b>Current transaction ID:<\/b> (.*)<br\/>/i).captures
end

def download_fsimage (namenode_host, namenode_port, hadoop_version, download_dirs, retention)
  if hadoop_version =~ "1.[0-9].[0-9]"
    puts "hadoop v1"
    uri = "http://#{namenode_host}:#{namenode_port}/getimage?getimage=1"
  elsif hadoop_version =~ "2.[0-3].[0-9]"
    puts "hadoop <v2.3"
    uri="http://#{namenode_host}:#{namenode_port}/getimage?getimage=1&txid=latest"
  else
    puts "hadoop >v2.4"
    uri="http://#{namenode_host}:#{namenode_port}/imagetransfer?getimage=1&txid=latest"
  end

  check_download_dirs download_dirs
  delete_on_retention download_dirs, "fsimage*", retention

  time_in_ms = DateTime.now.strftime('%s')
  random_5chars = (0...5).map { ('a'..'z').to_a[rand(26)] }.join
  file_to_write = "fsimage.#{random_5chars}.#{time_in_ms}"
  file_to_write_gz = "fsimage.#{random_5chars}.#{time_in_ms}.gz"
  begin
    open(file_to_write, 'wb') do |file|
      file << open(uri, 'rb').read
    end
    compress_file file_to_write
    download_dirs.each do |dir|
      FileUtils.cp(file_to_write_gz, dir)
    end
  rescue Timeout::Error
    puts "The request for a page at #{uri} timed out...exiting."
    exit
  rescue OpenURI::HTTPError => e
    puts "The request for a page at #{uri} returned an error."
    puts e.message.split("\t")
    exit
  ensure
    FileUtils.rm(file_to_write)
    FileUtils.rm(file_to_write_gz)
  end
end

def download_edits (namenode_host, namenode_port, hadoop_version, start_trans_id, end_trans_id, download_dirs, retention)
  if hadoop_version =~ "1.[0-9].[0-9]"
    uri = "http://#{namenode_host}:#{namenode_port}/getimage?getedit=1"
  elsif hadoop_version =~ "2.[0-3].[0-9]"
    uri="http://#{namenode_host}:#{namenode_port}/getimage?getedit=1&startTxId=#{start_trans_id}&endTxId=#{end_trans_id}"
  else
    uri="http://#{namenode_host}:#{namenode_port}/imagetransfer?getedit=1&startTxId=#{start_trans_id}&endTxId=#{end_trans_id}"
  end

  check_download_dirs download_dirs
  delete_on_retention download_dirs, "edits*", retention

  time_in_ms = DateTime.now.strftime('%s')
  file_to_write = "edits.#{start_trans_id}.#{end_trans_id}.#{time_in_ms}"
  file_to_write_gz = "edits.#{start_trans_id}.#{end_trans_id}.#{time_in_ms}.gz"
  begin
    open(file_to_write, 'wb') do |file|
      file << open(uri, 'rb').read
    end
    compress_file file_to_write
    download_dirs.each do |dir|
      FileUtils.cp(file_to_write_gz, dir)
    end
  rescue Timeout::Error
    puts "The request for a page at #{uri} timed out...exiting."
    exit
  rescue OpenURI::HTTPError => e
    puts "The request for a page at #{uri} returned an error."
    puts e.message.split("\t")
    exit
  ensure
    FileUtils.rm(file_to_write)
    FileUtils.rm(file_to_write_gz)
  end
end

# Main
nn_wb_cnts = get_namenode_webpage_contents(options[:namenode], options[:port])
hadoop_version = get_hadoop_version(nn_wb_cnts)
current_trans_id = get_current_transaction_id(nn_wb_cnts).first.to_i

download_fsimage(options[:namenode], options[:port], hadoop_version, options[:dirs], options[:retention_days])
download_edits(options[:namenode], options[:port], hadoop_version, options[:start_trans_id], options[:end_trans_id], options[:dirs], options[:retention_days])