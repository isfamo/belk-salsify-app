require 'net/sftp'
require 'net/ssh'
require 'net/ssh/proxy/http'
require 'uri'

module RRDonnelley
  class SFTPProxy

    attr_reader :port, :host, :user, :password, :client

    def initialize(host, user, pass)
      @port = 22
      @host = host
      @user = user
      @password = pass
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
    def find_file(ftp_path, filename)
      start do |sftp|
        sftp.dir.foreach(ftp_path) do |entry|
          next if entry.name.start_with?('.') || entry.directory?
          return File.join(ftp_path, entry.name) if entry.name.include?(filename)
        end
      end
    end

    def find_file_with_retry(remote_filepath, input_filepath)
      retries = 0
      begin
        find_file(remote_filepath, input_filepath).tap do |file|
          raise Error unless file
        end
      rescue
        sleep 180
        retry if (retries += 1) < 20
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

    private

    def start &block
      #Net::SSH.start(host, user, { port: port, proxy: proxy } ) do |ssh|
      Net::SSH.start(host, user, { :password => password, :port => port, :proxy => proxy } ) do |ssh|
        ssh.sftp.connect do |sftp|
          yield sftp
        end
      end
    end

    def proxy
      proximo = URI.parse(ENV['PROXIMO_URL'])
      Net::SSH::Proxy::HTTP.new(proximo.hostname, proximo.port, user: proximo.user, password: proximo.password)
    end
  end
end
