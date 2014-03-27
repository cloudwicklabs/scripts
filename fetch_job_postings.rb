#!/usr/bin/env ruby

# Author:: Ashrith Mekala (<ashrith@cloudwick.com>)
# Description:: Program to pull dice postings and put them to a specified
#   google spreadsheet
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
require 'net/http'
require 'open-uri'
require 'pp'
require 'pathname'
require 'optparse'
require 'ostruct'
begin
  require 'json'
  require 'parallel'
  require 'google_drive'
rescue
  puts <<-EOS
  Following ruby libraries are required: 'json', 'parallel', 'google_drive'
  Install then using: `gem install json parallel google_drive --no-ri --no-rdoc`
  EOS
end

class GoogleSpreadSheet
  def initialize(un, pwd)
    @session   = get_session(un, pwd)
    @ws_exists = false
  end

  def get_session(username, password)
    GoogleDrive.login(username, password)
  end

  def get_spreadsheet(title)
    @session.spreadsheet_by_title(title)
  end

  def create_spreadsheet(name)
    @session.create_spreadsheet(name)
  end

  def create_worksheet(ws_name, spreadsheet, max_rows, max_cols)
    if spreadsheet.worksheet_by_title(ws_name)
      puts "Worksheet #{ws_name} already exists"
      @ws_exists = true
    else
      puts "Creating worksheet named: #{ws_name} in spreadsheet: #{spreadsheet.title}"
      spreadsheet.add_worksheet(ws_name, max_rows, max_cols)
    end
    return spreadsheet.worksheet_by_title(ws_name)
  end

  # data = { "url" => { :title => '', :company => '', :location => '', :date => '' }, ... }
  def write_to_worksheet(worksheet, data)
    ws_rows = nil
    row_position = 1
    url_position = 4
    if @ws_exists
      # change the row position for new writes
      row_position  = worksheet.num_rows + 1
      ws_rows       = worksheet.rows
      existing_urls = ws_rows.map { |r| r[url_position] }
      new_urls      = data.keys
      post_urls     = new_urls - existing_urls
      # Modify data hash to include only new urls
      data.select! { |url| post_urls.include?(url) }
      if data.empty?
        puts "Hurray! no new data found to add"
      else
        puts "new data being added: #{data.inspect}, from row starting at #{row_position}"
      end
    end
    unless data.empty?
      # write out data fresh
      data.each do |url, cols|
        worksheet[row_position, 1] = cols[:date]
        worksheet[row_position, 2] = cols[:title]
        worksheet[row_position, 3] = cols[:company]
        worksheet[row_position, 4] = cols[:location]
        worksheet[row_position, 5] = cols[:skills]
        worksheet[row_position, 6] = url
        row_position += 1
      end
      worksheet.synchronize
    end
  end

  def upload_from_file_csv(path, name)
    @session.upload_from_file(path, name, :content_type => 'text/csv')
  end
end

class Encryptor
  begin
    require 'io/console' # > 1.9.3
  rescue LoadError
  end
  require 'openssl'
  require 'fileutils'
  require 'base64'

  CIPHER = 'aes-256-cbc' # AES256

  def self.hash(plaintext)
    OpenSSL::Digest::SHA512.new(plaintext).digest
  end

  if STDIN.respond_to?(:noecho)
    def self.read_password(prompt = 'Password: ')
      printf prompt
      STDIN.noecho(&:gets).chomp
    end
  else
    def self.read_password(prompt = 'Password: ')
      `read -s -p "#{prompt}" password; echo $password`.chomp
    end
  end

  # Encrypts or decrypts the data with the password hash as key
  # NOTE: encryption exceptions do not get caught!
  def self.encrypt(data, pwhash)
    c = OpenSSL::Cipher.new CIPHER
    c.encrypt
    c.key = self.hash(pwhash)
    encrypted = c.update(data) << c.final
    Base64.encode64(encrypted).encode('utf-8')
  end

  def self.decrypt(encoded, pwhash)
    c = OpenSSL::Cipher.new CIPHER
    c.decrypt
    c.key = self.hash(pwhash)
    decoded = Base64.decode64(encoded.encode('ascii-8bit'))
    c.update(decoded) << c.final
  end
end

class ProcessPostings
  def initialize(base_url, search_string, age, pages_to_traverse, page_search)
    @traverse_depth     = pages_to_traverse.to_i
    @base_url           = base_url
    @search_string      = search_string
    @page_search_string = page_search
    @age                = age
    @processed_data     = Hash.new
    @mutex              = Mutex.new
    @processed          = 0
  end

  def process_request(base_url, params = {})
    uri       = URI.parse(base_url)
    uri.query = URI.encode_www_form(params) unless params.nil?
    printf "Processing page request (#{uri})\n"
    response = Net::HTTP.get_response(uri)
    if response.code == '301' || response.code == '302'
      response = Net::HTTP.get_response(URI.parse(response.header['location']))
    end
    return response
  rescue URI::InvalidURIError
    $stderr.printf "Failed parsing URL: #{base_url}\n"
    return nil
  end

  def process_response(response)
    json = JSON.parse(response.body)
    total_docs = json['count']
    last_doc_in_page = json['lastDocument']
    printf "Processing postings: #{last_doc_in_page} | Total postings: #{total_docs} | Total processed: #{@processed}\n"
    result = json['resultItemList']
    Parallel.each(result, :in_threads => 50) do |rs|
      @mutex.synchronize { @processed += 1 }
      response_internal = process_request(rs['detailUrl'])
      if keep_posting?(response_internal)
        @mutex.synchronize {
          @processed_data[rs['detailUrl']] = {
            :title => rs['jobTitle'],
            :company => rs['company'],
            :location => rs['location'],
            :date => rs['date'],
            :skills => pull_skills(response_internal) || nil,
          }
        }
      end
    end
    return if total_docs.to_i == last_doc_in_page.to_i
  end

  # figure out if the posting is to be kept based on 'Tax Term: *CON_CORP*'
  def keep_posting?(response)
    return false if response.nil?
    status = true
    if @page_search_string
      @page_search_string.each do |ps|
        unless response.body =~ Regexp.new(ps)
          status = false
        end
      end
    end
    return status
  end

  def pull_skills(response)
    skills = response.body.scan(Regexp.new('^\s+<dt.*>Skills:<\/dt>\s+<dd.*>(.*)<\/dd>')).first
    if skills.is_a?(Array)
      return skills.join(',').gsub('&nbsp;', '')
    else
      'N/A'
    end
  end

  def run
    @traverse_depth.times do |page|
      response = process_request(
        @base_url,
        params = {
          :text => @search_string,
          :age  => @age,
          :page => page + 1,
          :sort => 1
        }
      )
      process_response(response)
    end
    return @processed_data
  end
end

if __FILE__ == $0
  options  = OpenStruct.new
  # defaults
  options.encrypt = false
  options.age_of_postings = 1
  options.traverse_depth  = 1
  options.page_search_string = []
  req_options = %w(search_string spreadsheet_name google_username google_password password_hash)

  optparse = OptionParser.new do |opts|
    opts.banner = "Usage: #{$PROGRAM_NAME} [options]"

    opts.on('-s', '--search STRING', "Specify a search string like a keyword on which to filter job postings. For example: 'java' or 'ruby'.") do |s|
      options.search_string = s
    end

    opts.on('-a', '--age-of-postings [DAYS]', Numeric, "Specifies how many days back postings to fetch.") do |a|
      options.age_of_postings = a
    end

    opts.on('-d', '--traverse-depth [DEPTH]', Numeric, "How many pages to traverse (each page contains 50 postings)") do |t|
      options.traverse_depth = t
    end

    opts.on('-r', '--page-search [STRING]', "Specify a search term to traverse to job posting and do a regex search") do |r|
      options.page_search_string << r
    end

    opts.on('-n', '--spreadsheet-name NAME', 'Name of the spreadsheet to use in google drive') do |s|
      options.spreadsheet_name = s
    end

    opts.on('-u', '--username USERNAME', 'Username of the google account who to access the drive as') do |u|
      options.google_username = u
    end

    opts.on('-p', '--password ENCRYPTED', 'Encrypted password of the google account who to access the drive as, to encrypt use `--encrypt`') do |p|
      options.google_password = p
    end

    opts.on('-e', '--encrypt', 'Wether to encrypt the password') do |e|
      options.encrypt = true
    end

    opts.on('-h', '--hash PASSWORD_HASH', 'If the password is encrypted then provide salt hash') do |e|
      options.password_hash = e
    end

    opts.on('--help', 'Show this message') do
      puts opts
      exit
    end
  end

  begin
    optparse.parse!
    if options.encrypt
      pwd_to_encrypt = Encryptor.read_password("Enter your google drive password to encrypt: ")
      puts
      printf "Enter the password salt: "
      pwd_salt = gets.chomp
      puts
      # encrypt the password and print out encrypted password
      encrypted_password = Encryptor.encrypt(pwd_to_encrypt, pwd_salt)
      puts "Encypted password: #{encrypted_password}"
      puts "Salt: #{pwd_salt}"
      exit 0
    else
      req_options.each do |req|
        raise OptionParser::MissingArgument, req if options.send(req).nil?
      end
    end
  rescue OptionParser::InvalidOption, OptionParser::MissingArgument
    puts $!.to_s
    puts optparse
    exit
  end

  pwd_decrypted = Encryptor.decrypt(options.google_password, options.password_hash)
  google = GoogleSpreadSheet.new(options.google_username, pwd_decrypted)
  spreadsheet = google.get_spreadsheet(options.spreadsheet_name)
  unless spreadsheet
    puts "Failed to fetch specified spreadsheet, make sure #{options.google_username} has access to the spreadsheet specified"
    exit 1
  end

  data = ProcessPostings.new(
    "http://service.dice.com/api/rest/jobsearch/v1/simple.json",
    options.search_string,
    options.age_of_postings,
    options.traverse_depth,
    options.page_search_string
  ).run

  worksheet = google.create_worksheet(Date.today.strftime('%A, %b %d'), spreadsheet, data.length, 10)
  google.write_to_worksheet(worksheet, data)
end
