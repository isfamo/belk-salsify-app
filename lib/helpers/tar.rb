### Usage Example: ###
#
# io = Tar.new.tar(path: "./Desktop", is_dir: true)   # io is a TAR of files
# io = Tar.new.tar(path: "./Desktop/my_file.xml", is_dir: false)   # io is a TAR of files
# gz = Tar.new.gzip(io)           # gz is a TGZ
#
# io = Tar.new.ungzip(gz)         # io is a TAR
# Tar.new.untar(io, "./untarred") # files are untarred
#

class Tar
  # Creates a tar file in memory recursively
  # from the given path.
  #
  # Returns a StringIO whose underlying String
  # is the contents of the tar file.
  def tar(path:, is_dir: true)
    tarfile = StringIO.new("")
    Gem::Package::TarWriter.new(tarfile) do |tar|
      filepaths = is_dir ? Dir[File.join(path, "**/*")].to_a : [path]
      #binding.pry
      filepaths.each do |filepath|
        mode = File.stat(filepath).mode
        #relative_file = filepath.sub(/^#{Regexp::escape(filepath)}\/?/, '')
        relative_file = filepath.split('/').last

        if File.directory?(filepath)
          tar.mkdir(relative_file, mode)
        else
          tar.add_file(relative_file, mode) do |tf|
            File.open(filepath, "rb") { |f| tf.write(f.read) }
          end
        end
      end
    end

    tarfile.rewind
    tarfile
  end

  # gzips the underlying string in the given StringIO,
  # returning a new StringIO representing the
  # compressed file.
  def gzip(tarfile)
    gz = StringIO.new("")
    z = Zlib::GzipWriter.new(gz)
    z.write tarfile.string
    z.close # this is necessary!

    # z was closed to write the gzip footer, so
    # now we need a new StringIO
    StringIO.new gz.string
  end

  # un-gzips the given IO, returning the
  # decompressed version as a StringIO
  def ungzip(tarfile)
    z = Zlib::GzipReader.new(tarfile)
    unzipped = StringIO.new(z.read)
    z.close
    unzipped
  end

  # untars the given IO into the specified
  # directory
  def untar(io, destination)
    Gem::Package::TarReader.new io do |tar|
      tar.each do |tarfile|
        destination_file = File.join destination, tarfile.full_name

        if tarfile.directory?
          FileUtils.mkdir_p destination_file
        else
          destination_directory = File.dirname(destination_file)
          FileUtils.mkdir_p destination_directory unless File.directory?(destination_directory)
          File.open destination_file, "wb" do |f|
            f.print tarfile.read
          end
        end
      end
    end
  end
end
