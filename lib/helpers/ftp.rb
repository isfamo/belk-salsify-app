# Define a wrapper for the Net::FTP ruby class.
# Scope:
# - Increase the flexibility
# - Add encapsulation
require 'net/sftp'
require 'net/ssh'
require 'net/ssh/proxy/http'
require 'uri'

module FTP
  class Wrapper

    attr_reader :port, :host, :user, :password, :client

    ENCRYPTION = [ 'blowfish-cbc', '3des-cbc' ].freeze
    PASSWORD = [ 'password' ].freeze

    def initialize(client: :salsify)
      @client = client
      if client == :salsify
        @port = 22
        @host = ENV.fetch('SALSIFY_FTP_HOST')
        @user = ENV.fetch('SALSIFY_FTP_USER')
        @password = ENV.fetch('SALSIFY_FTP_PASSWORD')
      elsif client == :belk
        @port = ENV.fetch('BELK_FTP_PORT')
        @host = ENV.fetch('BELK_FTP_HOST')
        @user = ENV.fetch('BELK_FTP_USER')
      elsif client == :belk_qa
        @port = ENV.fetch('BELK_FTP_PORT')
        @host = ENV.fetch('BELK_QA_FTP_HOST')
        @user = ENV.fetch('BELK_QA_FTP_USER')
      elsif client == :belk_img
        @host = ENV.fetch('BELK_IMG_FTP_HOST')
        @user = ENV.fetch('BELK_IMG_FTP_USER')
        @password = ENV.fetch('BELK_IMG_FTP_PASSWORD')
      else
        raise 'Unknown client provided!'
      end
    end

    def download(remote_file_name, local_file_name = nil)
      local_file_name ||= remote_file_name
      start do |sftp|
        sftp.download!(remote_file_name, local_file_name)
      end
      return true
    end

    def upload(local_file_name, remote_file_name = nil)
      raise MissingLocalFile, "#{local_file_name} is missing" unless File.exist?(local_file_name)
      remote_file_name ||= local_file_name
      start do |sftp|
        sftp.upload!(local_file_name, remote_file_name)
      end
      return true
    end

    def list(path = '/')
      start do |sftp|
        sftp.dir.foreach(path) do |entry|
          puts entry.longname
        end
      end
    end

    def remove(remote_file_path)
      start do |sftp|
        sftp.remove!(remote_file_path)
      end
    end

    # this returns the first thing it finds that matches
    #   this is slow and inefficient - iterates all files looking for the one match
    #   except that multiples may match, so it takes the first one
    #   see find_files below, there are built in functions that offload that search to the server
    # We may want to update this
    # ESS
    def find_file(ftp_path, filename, date = nil)
      start do |sftp|
        sftp.dir.foreach(ftp_path) do |entry|
          next if entry.name.start_with?('.') || entry.directory?
          if date
            return File.join(ftp_path, entry.name) if entry.name.include?(filename) && entry.name.include?(date)
          else
            return File.join(ftp_path, entry.name) if entry.name.include?(filename)
          end
        end
      end
    end

    def list_files(path)
      start do |sftp|
        files = sftp.dir.entries(path).map do |entry|
          next if entry.name.start_with?('.') || entry.directory?
          entry
        end.compact
        return files
      end
    end

    def find_pim_file(ftp_path)
      start do |sftp|
        found_entry = sftp.dir.entries(ftp_path).delete_if do |entry|
          entry.name.start_with?('.') || entry.directory?
        end.compact.sort_by { |entry| entry.attributes.mtime }.first
        return File.join(ftp_path, found_entry.name) if found_entry
      end
    end

    def find_file_with_retry(remote_filepath, input_filepath)
      with_retry(60) do
        find_file(remote_filepath, input_filepath).tap do |entry|
          raise Error unless entry
        end
      end
    end

    # this returns a list of all files that match
    def find_files(ftp_path, filename)
      files = []
      start do |sftp|
        # this is a more efficient way to handle this (see find_file that does it the slow way)
        sftp.dir.glob(ftp_path, "#{filename}*") do |entry|
          files << File.join(ftp_path, entry.name)
        end
      end
      # we want them in order of oldest date first, and oldest timestamp - this will do that
      files.sort
    end

    def find_files_with_retry(ftp_path, filename)
      with_retry(60) do
        find_files(ftp_path, filename).tap do |files|
          raise Error unless files.present?
        end
      end
    end

    def with_retry(max_retries = 20, sleep_time = 180, &block)
      retries = 0
      begin
        block.call
      rescue
        sleep sleep_time
        retry if (retries += 1) < max_retries
      end
    end

    private

    def start &block
      with_retry(3, 10) do
        if client == :salsify
          Net::SFTP.start(host, user, password: password, port: port, encryption: ENCRYPTION, auth_methods: PASSWORD) do |sftp|
            yield sftp
          end
        else
          Net::SSH.start(host, user, { port: port, proxy: proxy, key_data: [ ENV.fetch('BELK_QA_PRIVATE_KEY') ] } ) do |ssh|
            ssh.sftp.connect do |sftp|
              yield sftp
            end
          end
        end
      end
    end

    def proxy
      proximo = URI.parse(ENV['PROXIMO_URL'])
      Net::SSH::Proxy::HTTP.new(proximo.hostname, proximo.port, user: proximo.user, password: proximo.password)
    end
  end


  class ConfigError < StandardError; end
  class MissingLocalFile < StandardError; end
end
