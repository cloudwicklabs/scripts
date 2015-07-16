#!/usr/bin/env ruby

# Author:: Ashrith Mekala (<ashrith@cloudwick.com>)
# Description:: Produces recommended hadoop v2 cluster parameters based on
#               cluster's hardware.
# Version: 0.3
# TODO:
#   1. Add HBase tuning
#   2. Add Spark tuning
#   3. Add Hive
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
require 'json'

# Parse command line args
options  = OpenStruct.new

req_options = %w(cores ram disks slaves size)

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

  opts.on('-s', '--size INT', Numeric, "Specify size of the disk in GB") do |s|
    options.size = s
  end

  opts.on('-n', '--number-of-slaves INT', Numeric, "Specify number of worker nodes in the cluster") do |n|
    options.slaves = n
  end

  opts.on('-m', '--nn-mem INT', Numeric, "Specify NameNode memory in GB") do |nnm|
    options.nnm = nnm
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
SLAVES = options.slaves
SIZE_OF_DISKS = options.size
NNM = if options.respond_to?(:nnm)
        options.nnm
      else
        0
      end

# Specify if hbase is being installed
HBASE = options.hbase

# OS + DEAMONS on each node (DN + NM)
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

#
# Common
#

class Struct
  def to_map
    map = Hash.new
    self.members.each { |m| map[m] = self[m] }
    map
  end

  def to_json(*a)
    to_map.to_json(*a)
  end
end

class Param < Struct.new(:parameter_name, :description, :default_value, :suggested_value, :file); end

def gen_param(param_name, description, default_value, suggested_value, file)
  Param.new(param_name, description, default_value, suggested_value, file)
end

def word_wrap(text, line_width = 80)
  return text if line_width <= 0
  text.gsub(/\n/, ' ').gsub(/(.{1,#{line_width}})(\s+|$)/, "\\1\n").strip
end

#
# General
#
def general_tuning
  common_params = [
    gen_param(
      "io.file.buffer.size",
      "NA",
      4096,
      "NA",
      "core-site.xml"
    )
  ]
end

#
# HDFS
#
def hdfs_tuning
  namenode_params = [
    gen_param(
      "dfs.namenode.handler.count",
      "Number of handler threads to handle all datanode activity. Keep in mind more number of threads require more memory on the NameNode heap",
      10,
      [ Math.log(SLAVES) * 20, 10 ].max.ceil,
      "hdfs-site.xml"
    )
  ]

  if NNM != 0
    nnh = (NNM * 0.75).floor
    nnng = (nnh * 1/8)

    namenode_params << gen_param(
      "HADOOP_NAMENODE_OPTS",
      "Specify NameNode heap size, garbage collectors for new and old generation, configure GC logging, auit logging. This tweak assumes 75% of memory could be allocated to NN JVM. Note: Very roughly 32 GB of memory allocated to process will be able to store 60 million objects (files, directories, blocks).",
      "-Xmx1024m",
      "-server -XX:ParallelGCThreads=8 -XX:+UseParNewGC -XX:+UseConcMarkSweepGC -XX:-CMSConcurrentMTEnabled -XX:CMSInitiatingOccupancyFraction=70 -XX:+CMSParallelRemarkEnabled -XX:ErrorFile=/var/log/hadoop/$USER/hs_err_pid%p.log -XX:NewSize=#{nnng}G -XX:MaxNewSize=#{nnng}G -Xloggc:/var/log/hadoop/$USER/gc.log-`date +'%Y%m%d%H%M'` -verbose:gc -XX:+PrintGCDetails -XX:+PrintGCTimeStamps -XX:+PrintGCDateStamps -Xms#{nnh}G -Xmx#{nnh}G -Dhadoop.security.logger=INFO,DRFAS -Dhdfs.audit.logger=INFO,DRFAAUDIT ${HADOOP_NAMENODE_OPTS}",
      "hadoop-env.sh"
    )
  end

  datanode_params = [
    gen_param(
      "dfs.datanode.handler.count",
      "The number of server threads for the DataNode. More threads means more read/write requests"+
      " can be handled simultaneously",
      3,
      "TODO", # TODO
      "hdfs-site.xml"
    ),
    gen_param(
      "dfs.datanode.du.reserved",
      "Reserved space in bytes per volume for non Distributed File System (DFS) use.",
      0,
      [SIZE_OF_DISKS * 1024 * 1024 * 0.10 , 1 * 1024 * 1024].max.ceil, # 10% of disk space or atleast 1 GB
      "hdfs-site.xml"
    ),
    gen_param(
      "dfs.datanode.failed.volumes.tolerated",
      "The number of volumes that are allowed to fail before a DataNode stops offering service. By default, any volume failure will cause a DataNode to shutdown.",
      0,
      "less than or equal to half of the number of data directories",
      "hdfs-site.xml"
    ),
    gen_param(
      "dfs.datanode.max.transfer.threads",
      "Specifies the maximum number of threads to use for transferring data in and out of the DataNode.",
      4096,
      "TODO", # TODO
      "hdfs-site.xml"
    )
  ]

  dnh = if @reserved_for_mem_stack <= 1
                    256
                  elsif @reserved_for_mem_stack <= 2
                    512
                  elsif @reserved_for_mem_stack <= 4
                    1024
                  elsif @reserved_for_mem_stack <= 16
                    2048
                  else
                    4096
                  end
  dnng = (dnh * 1/8)

  # TODO not proprely outputting
  datanode_params << gen_param(
    "HADOOP_DATANODE_OPTS",
    "Specify DataNode heap size, garbage collectors for new and old generation, configure GC logging, auit logging. Note: consider the average # of blocks per datanode, and consider a heap size of roughly 1G/500k blocks as a minimum requirement additional heap should be configured for transient data in addition to this base/minimum requirement.",
    "-Xmx1024m",
    "TODO",
    #"-server -XX:ParallelGCThreads=8 -XX:+UseParNewGC -XX:+UseConcMarkSweepGC -XX:-CMSConcurrentMTEnabled -XX:CMSInitiatingOccupancyFraction=70 -XX:+CMSParallelRemarkEnabled -XX:ErrorFile=/var/log/hadoop/$USER/hs_err_pid%p.log -XX:NewSize=#{dnng}M -XX:MaxNewSize=#{dnng}M -Xloggc:/var/log/hadoop/$USER/gc.log-`date +'%Y%m%d%H%M'` -verbose:gc -XX:+PrintGCDetails -XX:+PrintGCTimeStamps -XX:+PrintGCDateStamps -Xms#{dnh}G -Xmx#{dnh}G -Dhadoop.security.logger=INFO,DRFAS -Dhdfs.audit.logger=INFO,DRFAAUDIT ${HADOOP_DATANODE_OPTS}",
    "hadoop-env.sh"
  )


  params = {
    "namenode_params" => namenode_params,
    "datanode_params" => datanode_params
  }

  puts JSON.pretty_generate(params)
end

def yarn_tuning
  containers = [2 * CORES, (1.8 * DISKS.to_f), (@usable_mem.to_i / MIN_CONTAINER_SIZE_MB)].min.ceil
  ram_per_container = [MIN_CONTAINER_SIZE_MB, (@usable_mem.to_i / containers)].max

  resource_manager_params = [
    gen_param(
      "yarn.scheduler.minimum-allocation-mb",
      "The minimum allocation for every container request at the RM, in MBs. Memory requests lower than this won't take effect, and the specified value will get allocated at minimum.",
      1024,
      ram_per_container,
      "yarn-site.xml"
    ),
    gen_param(
      "yarn.scheduler.maximum-allocation-mb",
      "The maximum allocation for every container request at the RM, in MBs. Memory requests higher than this won't take effect, and will get capped to this value.",
      8192,
      containers * ram_per_container,
      "yarn-site.xml"
    )
  ]

  nodemanager_params = [
    gen_param(
      "yarn.nodemanager.resource.memory-mb",
      "Amount of physical memory, in MB, that can be allocated for containers.",
      8192,
      containers * ram_per_container,
      "yarn-site.xml"
    )
  ]

  mapreduce_params = [
    gen_param(
      "yarn.app.mapreduce.am.resource.mb",
      "The amount of memory the MR AppMaster needs.",
      1536,
      # TODO check this Cloudera recommends other value
      ram_per_container,
      "mapred-site.xml"
    ),
    gen_param(
      "yarn.app.mapreduce.am.command-opts",
      "Java opts for the MR App Master processes.",
      "-Xmx1024m",
      # TODO check this Cloudera recommends other value
      "-Xmx#{0.8 * ram_per_container}m",
      "yarn-site.xml"
    ),
    gen_param(
      "mapreduce.map.memory.mb",
      "The amount of memory to request from the scheduler for each map task.",
      1024,
      ram_per_container,
      "mapred-site.xml"
    ),
    gen_param(
      "mapreduce.reduce.memory.mb",
      1024,
      "The amount of memory to request from the scheduler for each reduce task.",
      # TODO check this Cloudera recommends other value
      ram_per_container,
      "mapred-site.xml"
    ),
    gen_param(
      "mapreduce.map.java.opts",
      "JVM options passed to the mapper",
      "",
      "-Xmx#{(0.8 * ram_per_container).to_i}m",
      "mapred-site.xml"
    ),
    gen_param(
      "mapreduce.reduce.java.opts",
      "JVM options passed to the reducer",
      "",
      # TODO check this Cloudera recommends other value
      "-Xmx#{(0.8 * ram_per_container).to_i}m",
      "mapred-site.xml"
    ),
    gen_param(
      "mapreduce.task.io.sort.mb",
      "The total amount of buffer memory to use while sorting files, in megabytes. By default, gives each merge stream 1MB, which should minimize seeks.",
      100,
      [ 0.4 * ram_per_container, 1024 ].min.to_i,
      "mapred-site.xml"
    ),
    gen_param(
      "mapreduce.task.io.sort.factor",
      "The number of streams to merge at once while sorting files. This determines the number of open file handles.",
      10,
      [ 0.4 * ram_per_container, 1024 ].min.to_i / 10,
      "mapred-site.xml"
    ),
    gen_param(
      "mapreduce.reduce.shuffle.parallelcopies",
      "The default number of parallel transfers run by reducer during the copy(shuffle) phase",
      5,
      [Math.log(SLAVES) * 4].max.round,
      "mapred-site.xml"
    )
  ]

  params = {
    "resourcemanager_params" => resource_manager_params,
    "nodemanager_params" => nodemanager_params,
    "mapreduce_params" => mapreduce_params
  }

  puts JSON.pretty_generate(params)
end

# MAIN
hdfs_tuning
yarn_tuning
