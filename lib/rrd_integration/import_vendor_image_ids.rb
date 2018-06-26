module RRDonnelley
  class ImportVendorImageIds

    # Parse Belk's vendor image export xlsx file and create
    # RrdImageId records for pending vendor image approvals.
    # Sample xlsx file at: lib/rrd_integration/cache/MigrationDataForVPI.xlsx

    KEY_PRODUCT_ID = 'PARENT_PRODUCT_ID'.freeze
    KEY_IMAGE_ID = 'IMAGE_ID'.freeze
    KEY_COLOR_CODE = 'COLOR_CODE'.freeze
    KEY_SHOT_TYPE = 'SHOT_TYPE'.freeze
    KEY_IMAGE_NAME = 'IMAGE_NAME'.freeze
    COLUMN_ID_IMAGE_ID = 3.freeze

    attr_reader :filepath

    def initialize(filepath)
      @filepath = filepath
    end

    def self.import_foreign_image_ids(filepath)
      new(filepath).import_foreign_image_ids
    end

    def import_foreign_image_ids
      image_hashes_by_id = parse_excel_file_into_hashes
      generate_image_ids_from_hashes(image_hashes_by_id)
    end

    def parse_excel_file_into_hashes
      xlsx = Roo::Spreadsheet.open(filepath)
      headers = nil
      results = {}
      xlsx.sheet(0).each_row_streaming(pad_cells: true) do |row|
        row_vals = row.map { |cell| cell ? cell.value : nil }
        if headers.nil?
          headers = row_vals
          next
        end
        results[row_vals[COLUMN_ID_IMAGE_ID].to_i] = row_vals.each_with_index.map do |cell, index|
          [headers[index], cell]
        end.to_h
      end
      results
    end

    def generate_image_ids_from_hashes(image_hashes_by_id)
      existing_image_ids = []
      new_image_ids = []
      image_hashes_by_id.each do |image_id, image_hash|
        existing_image_id = RrdImageId.find_by(id: image_id)
        if existing_image_id
          existing_image_ids << existing_image_id
        else
          new_image_id = RrdImageId.new(
            id: image_id,
            product_id: image_hash[KEY_PRODUCT_ID],
            color_code: image_hash[KEY_COLOR_CODE],
            shot_type: image_hash[KEY_SHOT_TYPE],
            image_name: image_hash[KEY_IMAGE_NAME],
            approved: false
          )
          new_image_id.save!
          new_image_ids << new_image_id
        end
      end
    end

  end
end
