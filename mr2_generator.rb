#!/usr/bin/env ruby

# Author:: Ashrith Mekala (<ashrith@cloudwick.com>)
# Description:: Generates yarn configuration parameters for mapreduce 2
# Version: 0.1
#
# Copyright 2014, Cloudwick Inc.
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

require 'rubygems' if RUBY_VERSION < "1.9"
require 'optparse'
require 'ostruct'

# Parse command line args
options  = OpenStruct.new

req_options = %w(cores ram disks)

options.hbase = false

optparse = OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [options]"

  opts.on('-c', '--cores INT', Numeric, "Specify number of cores on each slave node") do |c|
    options.cores = c
  end

  opts.on('-r', '--ram INT', Numeric, "Specify RAM in GB on each slave node") do |r|
    options.ram = r
  end

  opts.on('-d', '--disks INT', Numeric, "Specify number of disks on each slave node") do |d|
    options.disks = d
  end

  opts.on('-h', '--hbase', 'Wether HBase is part of the cluster') do |h|
    options.hbase = true
  end

  opts.on('--help', 'Show this message') do
    puts opts
    exit
  end
end

begin
  optparse.parse!
  req_options.each do |req|
    raise OptionParser::MissingArgument, req if options.send(req).nil?
  end
rescue OptionParser::InvalidOption, OptionParser::MissingArgument
  puts $!.to_s
  puts optparse
  exit
end

# As a general recommendation, allowing for two Containers per disk and per
# core gives the best balance for cluster utilization.

# Spevify the nodes RAM in GB, Cores and physical mount points
RAM = options.ram
CORES = options.cores
DISKS = options.disks

# Specify if hbase is being installed
HBASE = options.hbase

# OS + DEAMONS (DN + NM)
RESERVED_MEM_STACK = {
  4 => 1,
  8 => 2,
  16 => 2,
  24 => 4,
  48 => 6,
  72 => 8,
  96 => 12,
  128 => 24,
  256 => 32,
  512 => 64
}

RESERVED_MEM_HBASE = {
  4 => 1,
  8 => 1,
  16 => 2,
  24 => 4,
  48 => 8,
  64 => 8,
  72 => 8,
  96 => 16,
  128 => 24,
  256 => 32,
  512 => 64
}

MIN_CONTAINER_SIZE_MB = if RAM <= 4
                          256
                        elsif RAM <= 8
                          512
                        elsif RAM <= 24
                          1024
                        else
                          2048
                        end


@reserved_for_mem_stack =  if RESERVED_MEM_STACK.has_key?(RAM)
                             RESERVED_MEM_STACK[RAM]
                           elsif RAM <= 4
                             1
                           elsif RAM <= 48
                             6
                           elsif RAM <= 72
                             8
                           elsif RAM <= 128
                             12
                           elsif RAM >= 512
                             64
                           else
                             1
                           end

@reserved_for_mem_hbase = if RESERVED_MEM_HBASE.has_key?(RAM)
                            RESERVED_MEM_HBASE[RAM]
                          elsif RAM <= 4
                            1
                          elsif RAM <= 48
                            6
                          elsif RAM <= 72
                            8
                          elsif RAM <= 128
                            12
                          elsif RAM >= 512
                            64
                          else
                            1
                          end
@reserved_mem = if HBASE
                  @reserved_for_mem_hbase + @reserved_for_mem_stack
                else
                  @reserved_for_mem_stack
                end

@usable_mem = ( RAM - @reserved_mem ) * 1024

@containers = [2 * CORES, (1.8 * DISKS.to_f), (@usable_mem.to_i / MIN_CONTAINER_SIZE_MB)].min.ceil

@ram_per_container = [MIN_CONTAINER_SIZE_MB, (@usable_mem.to_i / @containers)].max

@yarn_nodemanager_resource_memory_mb = @containers * @ram_per_container
@yarn_scheduler_minimum_allocation_mb = @ram_per_container
@yarn_scheduler_maximum_allocation_mb = @containers * @ram_per_container
@mapreduce_map_memory_mb = @ram_per_container
@mapreduce_reduce_memory_mb = 2 * @ram_per_container
@mapreduce_map_java_opts = 0.8 * @ram_per_container
@mapreduce_reduce_java_opts = 0.8 * 2 * @ram_per_container
@yarn_app_mapreduce_am_resource_mb = 2 * @ram_per_container
@yarn_app_mapreduce_am_command_opts = 0.8 * 2 * @ram_per_container
@mapreduce_task_io_sort_mb = [ 0.4 * @mapreduce_map_memory_mb, 1024 ].min.to_i
@mapreduce_task_io_sort_factor = @mapreduce_task_io_sort_mb / 10

puts "Number of containers: #{@containers}"
puts "Stack Reserved (OS + NM + DN): #{@reserved_for_mem_stack} GB"
puts "HBASE Reserved: #{@reserved_for_mem_hbase} GB" if options.hbase
puts "Usable Mem: #{@usable_mem} MB"
puts "=== Properties that go into yarn-site.xml ==="
puts "yarn.nodemanager.resource.memory-mb (in MB): #{@yarn_nodemanager_resource_memory_mb}"
puts "yarn.scheduler.minimum-allocation-mb (in MB): #{@yarn_scheduler_minimum_allocation_mb}"
puts "yarn.scheduler.maximum-allocation-mb (in Mb): #{@yarn_scheduler_maximum_allocation_mb}"
puts "yarn.app.mapreduce.am.resource.mb (in MB): #{@yarn_app_mapreduce_am_resource_mb}"
puts "yarn.app.mapreduce.am.command-opts: -Xmx#{@yarn_app_mapreduce_am_command_opts.to_i}m"
puts "=== Properties that go into mapred-site.xml ==="
puts "mapreduce.map.memory.mb (in MB): #{@mapreduce_map_memory_mb}"
puts "mapreduce.reduce.memory.mb (in MB): #{@mapreduce_reduce_memory_mb}"
puts "mapreduce.map.java.opts: -Xmx#{@mapreduce_map_java_opts.to_i}m"
puts "mapreduce.reduce.java.opts: -Xmx#{@mapreduce_reduce_java_opts.to_i}m"
puts "mapreduce.task.io.sort.mb (in MB): #{@mapreduce_task_io_sort_mb}"
puts "mapreduce.task.io.sort.factor: #{@mapreduce_task_io_sort_factor}"
