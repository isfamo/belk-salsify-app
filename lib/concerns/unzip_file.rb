module UnzipFile
  extend self

  EXTRACT_DIR = 'tmp'.freeze

  def unzip_file(tar: true, multiple_files: false)
    if tar
      tar_extract = Gem::Package::TarReader.new(Zlib::GzipReader.open(input_filepath))
      tar_extract.rewind # The extract has to be rewinded after every iteration
      extracted_files = tar_extract.map do |entry|
        entry_name = entry.full_name.gsub('PaxHeader/', '')
        puts "Extracting #{entry_name}..."
        destination = File.join(EXTRACT_DIR, entry_name)
        File.open(destination, 'wb') { |destination_file| destination_file.print(entry.read) }
        destination
      end
      multiple_files ? @extracted_files = extracted_files.sort : @extracted_file = extracted_files.first
      tar_extract.close
    else
      @extracted_file = begin
        destination = File.join(EXTRACT_DIR, File.basename(input_filepath.gsub('.gz', '')))
        File.open(destination, 'wb') { |destination_file| destination_file.print(Zlib::GzipReader.open(input_filepath).read) }
        destination
      end
    end
  end

end
