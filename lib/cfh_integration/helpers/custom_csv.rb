require 'csv'
require 'active_support'

module CustomCSV
  class Wrapper
    def initialize(file)
      @file = file
      File.exists?(@file) or raise MissingFileError, "csv file is missing"
    end

    def foreach
      CSV.foreach(@file, headers: true, header_converters: :symbol) do |row|
        yield row
      end
    end

    def map
      foreach_without_header.map { |row| yield row }
    end

    def foreach_without_header(encoding: 'UTF-8')
      if block_given?
        CSV.foreach(@file, encoding: encoding) { |row| yield row }
      else
        CSV.foreach(@file, encoding: encoding)
      end
    end
  end

  class MissingFileError < StandardError; end
end
