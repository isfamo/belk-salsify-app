module Demandware

  class SalsifyHelper
    include Muffin::SalsifyClient

    def initialize

    end

    def salsify
      @salsify ||= salsify_client(org_id: ENV.fetch('CARS_ORG_ID'))
    end

    def count_products_matching_filter(filter_hash: nil, filter_string: nil)
      salsify.products_filtered_by(filter_hash, filter: filter_string, per_page: 1, page: 1)['meta']['total_entries']
    end

    def filter_products(filter_hash: nil, filter_string: nil, selections: nil, per_page: 100, page: 1, log_n_pages: nil)
      if selections
        result = salsify.products_filtered_by(filter_hash, filter: filter_string, selections: selections, per_page: per_page, page: page)
      else
        result = salsify.products_filtered_by(filter_hash, filter: filter_string, per_page: per_page, page: page)
      end
      products = result['products']
      if result['meta']['total_entries'] > (result['meta']['current_page'] * result['meta']['per_page'])
        puts "$DW$ Filtering products, page #{page}/#{(result['meta']['total_entries'] / per_page.to_f).ceil}" if log_n_pages && page % log_n_pages == 0
        products + filter_products(filter_hash: filter_hash, filter_string: filter_string, selections: selections, per_page: per_page, page: (page + 1), log_n_pages: log_n_pages)
      else
        products
      end
    end

    # Helper method for constructing export configuration hash
    def export_config(entity_type: 'product', export_format: 'json', filter: nil, properties: nil, compress: nil, product_type: nil)
      config = {
        'configuration': {
          'entity_type': entity_type,
          'format': export_format,
          'include_all_columns': properties.nil?
        }
      }
      config[:configuration][:compress] = compress unless compress.nil?
      config[:configuration][:product_type] = product_type if product_type
      config[:configuration][:filter] = filter if filter
      config[:configuration][:properties] = "'#{properties.join('\',\'')}'" if properties
      config
    end

    # Run an ephemeral export given an export configuration hash
    def run_export(config)
      run_response = salsify.create_export_run(config)
      completed_response = Salsify::Utils::Export.wait_until_complete(salsify, run_response)
      RestClient::Request.execute(method: :get, url: completed_response.url, timeout: 600)
    end

    # Parse products out of json export string into a hash keyed on product id
    def parse_product_by_id_from_json_export(json_export_string)
      Oj.load(json_export_string).find do |hash|
        hash['products']
      end['products'].map do |product_hash|
        [product_hash['salsify:id'], product_hash]
      end.to_h
    end

    def parse_product_by_id_from_csv_export(csv_export_string)
      headers = nil
      CSV.new(csv_export_string.body).to_a.map do |row|
        if headers.nil?
          headers = row
          next
        end
        hash = {}
        headers.each_with_index do |header, index|
          next unless row[index]
          value = clean_csv_val(row[index])
          if hash[header] && hash[header].is_a?(Array)
            hash[header] << value
          elsif hash[header]
            hash[header] = [hash[header], value].flatten
          else
            hash[header] = value
          end
        end
        hash
      end.compact.map do |row_h|
        row_h['salsify:id'] = row_h.delete(PROPERTY_PRODUCT_ID)
        row_h['salsify:parent_id'] = row_h.delete(PROPERTY_PARENT_PRODUCT)
        [row_h['salsify:id'], row_h.reject { |k, v| v.nil? || (v.is_a?(Array) && v.empty?) || (v.is_a?(Hash) && v.empty?) }]
      end.to_h
    end

    def clean_csv_val(value)
      if value == 'Yes'
        true
      elsif value == 'No'
        false
      else
        value
      end
    end

    def export_attributes
      CSV.parse(
        run_export(
          export_config(
            entity_type: 'attribute',
            export_format: 'csv'
          )
        ),
        headers: true
      ).map do |row|
        row_hash = {}
        row.each do |cell_array|
          property = cell_array.first
          value = cell_array.last
          next unless value
          current_val = row_hash[property]
          if current_val
            row_hash[property] = [current_val, value].flatten
          else
            row_hash[property] = value
          end
        end
        row_hash
      end
    end

    def run_csv_import(filepath:, import_id:, wait_until_complete: true)
      Salsify::Utils::Import.start_import_with_new_file(
        salsify,
        import_id,
        filepath,
        wait_until_complete: wait_until_complete
      )
    end

  end

end
