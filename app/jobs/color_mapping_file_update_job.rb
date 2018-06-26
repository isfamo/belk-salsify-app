class ColorMappingFileUpdateJob < Struct.new(:params)
  include Muffin::FtpClient

  COLOR_MAPPING_FILE_FTP_PATH = 'Customers/Belk/color_mapping/color_master_mapping.xlsx'.freeze
  COLOR_MAPPING_FILE_LOCAL_PATH = './lib/cars_integration/cache/color_master_mapping.xlsx'.freeze
  COLOR_MAPPING_JSON_LOCAL_PATH = './lib/cars_integration/cache/color_master_mapping_processed.json'.freeze

  # When the color mapping file is updated on
  # Exavault, pull it in and convert to json
  def perform
    puts 'Color code mapping file update job queued...'
    with_salsify_ftp { |ftp| ftp.getbinaryfile(COLOR_MAPPING_FILE_FTP_PATH, COLOR_MAPPING_FILE_LOCAL_PATH) }

    xlsx = Roo::Spreadsheet.open(COLOR_MAPPING_FILE_LOCAL_PATH)
    color_mapping_hash = {}
    headers = nil
    xlsx.sheet(0).each_row_streaming(pad_cells: true) do |row|
      row_vals = row.map { |cell| cell ? cell.value : nil }
      if headers.nil?
        headers = row_vals
        next
      end
      color_mapping_hash[row_vals[0].to_s] = {
        'color_code_begin' => row_vals[1],
        'color_code_end' => row_vals[2],
        'super_color_code' => row_vals[3],
        'super_color_name' => row_vals[4],
        'status_code' => row_vals[9],
        'rule_changed' => row_vals[10]
      }
    end

    File.open(COLOR_MAPPING_JSON_LOCAL_PATH, 'w') do |file|
      file.write(color_mapping_hash.to_json)
    end
  end

  def with_salsify_ftp
    yield Net::FTP.open(
      ENV.fetch('SALSIFY_FTP_HOST'),
      ENV.fetch('SALSIFY_FTP_USERNAME'),
      ENV.fetch('SALSIFY_FTP_PASSWORD')
    )
  end

end
