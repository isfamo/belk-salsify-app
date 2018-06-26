module RRDonnelley
  class ImportSampleReqs
    include Muffin::SalsifyClient

    # Parse Belk's sample request export xlsx file and create
    # RrdRequestedSample records for pending sample requests.
    # Sample xlsx file at: lib/rrd_integration/cache/MigrationDataForSamples.xlsx

    KEY_PRODUCT_ID = 'ProductID'.freeze
    KEY_SAMPLE_ID = 'sampleID'.freeze
    KEY_VENDOR_NUM = 'Vendor#'.freeze
    KEY_STYLE_NUM = 'VendorStyle#'.freeze
    KEY_SAMPLE_TYPE = 'type'.freeze
    KEY_COLOR_CODE = 'colorCode'.freeze
    KEY_COLOR_NAME = 'colorName'.freeze
    KEY_RETURN_REQD = 'returnRequested'.freeze
    KEY_SILHOUETTE_REQD = 'silhouetteRequired'.freeze
    KEY_CARRIER = 'carrier'.freeze
    KEY_SHIPPING_ACCT_NUM = 'shippingAccountNumber'.freeze
    KEY_RETURN_INSTRUCTIONS = 'returnInstructions'.freeze
    KEY_PHOTO_INSTRUCTIONS = 'photoInstructions'.freeze
    KEY_RETURN_SAMPLE_TO = 'Return_Sample_To'.freeze

    attr_reader :filepath

    def initialize(filepath)
      @filepath = filepath
    end

    def self.import_foreign_sample_reqs(filepath)
      new(filepath).import_foreign_sample_reqs
    end

    def self.update_products_for_sample_reqs
      new(nil).update_products_for_sample_reqs
    end

    def import_foreign_sample_reqs
      sample_hashes = parse_excel_file_into_hashes
      generate_sample_reqs_from_hashes(sample_hashes)
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
        results[row_vals[1]] = row_vals.each_with_index.map do |cell, index|
          [headers[index], cell]
        end.to_h
      end
      results
    end

    def generate_sample_reqs_from_hashes(sample_hashes)
      existing_reqs = []
      new_reqs = []
      sample_hashes.each do |sample_id, sample_hash|
        existing_sample_req = RrdRequestedSample.find_by(
          product_id: sample_hash[KEY_PRODUCT_ID],
          color_id: sample_hash[KEY_COLOR_CODE]
        )
        if existing_sample_req
          existing_reqs << existing_sample_req
        else
          req = RrdRequestedSample.new(
            id: sample_id,
            product_id: sample_hash[KEY_PRODUCT_ID],
            color_id: sample_hash[KEY_COLOR_CODE],
            color_name: sample_hash[KEY_COLOR_NAME],
            of_or_sl: nil,
            on_hand_or_from_vendor: nil,
            sample_type: sample_hash[KEY_SAMPLE_TYPE],
            turn_in_date: nil,
            must_be_returned: sample_hash[KEY_RETURN_REQD],
            return_to: sample_hash[KEY_RETURN_SAMPLE_TO],
            return_notes: sample_hash[KEY_RETURN_INSTRUCTIONS],
            silhouette_required: sample_hash[KEY_SILHOUETTE_REQD] ? sample_hash[KEY_SILHOUETTE_REQD].strip == 'Y' : nil,
            instructions: sample_hash[KEY_PHOTO_INSTRUCTIONS],
            completed_at: nil,
            sent_to_rrd: false
          )
          req.save!
          new_reqs << req
        end
      end
    end

    def update_products_for_sample_reqs
      sample_reqs = RrdRequestedSample.where('created_at < ?', 2.days.ago).reject { |req| req.completed_at != nil }
      puts "# sample reqs = #{sample_reqs.length}"
      count = 0
      sample_reqs.each do |req|
        begin
          puts "#{count}/#{sample_reqs.length} - Parent ID = #{req.product_id}, Color = #{req.color_id}"
          sku_ids = client.product_relatives(req.product_id)['children'].map { |sku| sku['id'] }
          if sku_ids.empty?
            if req.color_id == '000'
              client.update_product(req.product_id, {
                'ImageAssetSource' => 'Sample Management',
                'Sample Sent to RRD' => true,
                'Sample Request from Old System' => true
              })
            end
          else
            skus = sku_ids.flatten.uniq.each_slice(100).map do |sku_id_batch|
              client.products(sku_id_batch)
            end.flatten.reject do |sku|
              sku.empty?
            end
            skus.select do |sku|
              sku['nrfColorCode'] == req.color_id &&
              [true, 'true', 'Yes'].include?(sku['Color Master?'])
            end.each do |sku|
              client.update_product(sku['salsify:id'], {
                'ImageAssetSource' => 'Sample Management',
                'Sample Sent to RRD' => true,
                'Sample Request from Old System' => true
              })
            end
          end
          count += 1
        rescue RestClient::ResourceNotFound => e
          puts "Product #{req.product_id} not found"
        end
      end
    end

    def client
      @client ||= salsify_client(org_id: ENV.fetch('CARS_ORG_ID'))
    end

  end
end
