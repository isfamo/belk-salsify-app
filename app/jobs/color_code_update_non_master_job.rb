class ColorCodeUpdateNonMasterJob < Struct.new(:products)
  include Muffin::SalsifyClient

  COLOR_MAPPING_JSON_LOCAL_PATH = './lib/cars_integration/cache/color_master_mapping_processed.json'.freeze
  COLOR_UPDATE_IMPORT_FILE_PATH = './tmp/cache/sku_color_update.csv'.freeze

  PROPERTY_COLOR_CODE = 'nrfColorCode'.freeze
  PROPERTY_REFINEMENT_COLOR = 'refinementColor'.freeze
  PROPERTY_COLOR_MASTER = 'Color Master?'.freeze

  MAX_TRIES = 3.freeze
  SLEEP_INTERVAL = 3.freeze

  def perform
    puts "$COLOR$ Color code non master update job queued for product IDs: #{updated_products.map { |product| product['salsify:id'] }.join(', ')}"
    init_dirs
    tries = 0

    begin
      updated_products.each do |updated_product|
        next unless updated_product[PROPERTY_COLOR_CODE] && updated_product[PROPERTY_COLOR_MASTER] != true
        parent_id = updated_product['salsify:parent_id']
        update_hash = {}

        # Determine info for the new color
        new_color_code_int = updated_product[PROPERTY_COLOR_CODE].to_i
        color_info_pair = color_mapping_hash.find do |color_id, color_hash|
          color_hash['color_code_begin'].to_i <= new_color_code_int &&
          color_hash['color_code_end'].to_i >= new_color_code_int
        end
        if color_info_pair
          # first is color id, second is hash
          color_info = color_info_pair.last

          # Update refinementColor on updated sku
          update_hash[PROPERTY_REFINEMENT_COLOR] = color_info['super_color_name']
        end

        # If there's NOT already a color master for this sku's new color...
        if skus_by_color_code_by_parent_id[parent_id]
          unless skus_by_color_code_by_parent_id[parent_id].any? { |color_code, sku_by_id|
            color_code == updated_product[PROPERTY_COLOR_CODE] &&
            sku_by_id.values.any? { |sku|
              sku[PROPERTY_COLOR_MASTER] == true
            }
          }
            # ...make this sku the color master for its new color code
            update_hash[PROPERTY_COLOR_MASTER] = true
          end
        end

        client.update_product(updated_product['salsify:id'], update_hash) unless update_hash.empty?

        # Now that it has settled itself down and a Color Master has been decided, go through its original color group and
        #   if they don't have a master, pick one.
        # Same code as above, but for the old color
        audits = audits_for_product(product_id: updated_product['salsify:id'], property_ids: [PROPERTY_COLOR_CODE], max_audits_per_property: 1)
        next unless audits[0] && audits[0]['modifications'] && audits[0]['modifications'][0] && audits[0]['modifications'][0]['old_values'] && audits[0]['modifications'][0]['old_values'][0] && audits[0]['modifications'][0]['old_values'][0]['name']
        old_color_value = audits[0]['modifications'][0]['old_values'][0]['name']
        siblings = client.product_relatives(parent_id)['children'].map { |sku| sku['id'] }
        old_color_siblings = []
        siblings.each do |sibling|
          if sibling[PROPERTY_COLOR_CODE] ==  old_color_value
            if sibling[PROPERTY_COLOR_MASTER] ==  true
              old_color_siblings = []
              break
            else
              old_color_siblings << sibling['salsify:id']
            end
          end
        end
        client.update_product(old_color_siblings.first, { PROPERTY_COLOR_MASTER => true }) if old_color_siblings.length > 0
      end
      puts "$COLOR$ Done with non master color update job"
    rescue Errno::ECONNRESET, RestClient::InternalServerError, RestClient::ServiceUnavailable => e
      tries += 1
      if tries < MAX_TRIES
        sleep SLEEP_INTERVAL
        retry
      else
        puts "$COLOR$ ERROR while running color code update non master job, failed #{MAX_TRIES} times, error: #{e.message}\n#{e.backtrace.join("\n")}"
        raise e
      end
    end
  end

  # Code taken from cs-flotsam
  def audits_for_product(product_id:, property_ids:, max_audits_per_property:, latest_date: nil, earliest_date: nil)
    the_audits = []
    property_id_audit_counts = Hash.new(0)
    lazily_paginate(product_id, resource: :product_audits, include_modifications: true, per_page: 75).lazy.each_with_index do |response, index|
      puts "Looking through page #{index+1} of #{response.audits.count} audits"
      response.audits.each do |audit|
        audit_date = DateTime.parse(audit.created_at)

        next unless audit.type == 'modification'

        # audits are returned most recent first
        return the_audits if earliest_date && audit_date < earliest_date

        # skip until we're in the right range
        next if latest_date && audit_date > latest_date

        relevant_modifications = property_ids.nil? ? audit.modifications : audit.modifications.select { |modification| property_ids.include?(modification.property&.id) }
        if relevant_modifications.present?
          the_audits << audit
          relevant_modifications.each { |modification| property_id_audit_counts[modification.property&.id] += 1 }
          # We're done if we've hit our max for every property
          return the_audits if max_audits_per_property && property_ids && property_ids.all? { |property_id| property_id_audit_counts[property_id] >= max_audits_per_property }
        end
      end
    end
    the_audits
  end

  def init_dirs
    Dir.mkdir('./tmp') unless File.exists?('./tmp')
    Dir.mkdir('./tmp/cache') unless File.exists?('./tmp/cache')
  end

  def color_mapping_hash
    @color_mapping_hash ||= JSON.parse(File.read(COLOR_MAPPING_JSON_LOCAL_PATH))
  end

  def updated_products
    @updated_products ||= products.map { |param| param.to_unsafe_h }
  end

  def parent_ids
    @parent_ids ||= updated_products.map { |product| product['salsify:parent_id'] }.compact.uniq
  end

  def sku_ids_by_parent_id
    @sku_ids_by_parent_id ||= parent_ids.map do |parent_id|
      [parent_id, client.product_relatives(parent_id)['children'].map { |sku| sku['id'] }]
    end.to_h
  end

  def sku_by_id
    @sku_by_id ||= sku_ids_by_parent_id.values.flatten.uniq.compact.each_slice(100).map do |sku_id_batch|
      client.products(sku_id_batch)
    end.flatten.reject do |sku|
      sku.empty?
    end.map do |sku|
      [sku['salsify:id'], sku]
    end.to_h
  end

  def skus_by_color_code_by_parent_id
    @skus_by_color_code_by_parent_id ||= begin
      result = {}
      sku_by_id.each do |sku_id, sku|
        result[sku['salsify:parent_id']] = {} unless result[sku['salsify:parent_id']]
        result[sku['salsify:parent_id']][sku[PROPERTY_COLOR_CODE]] = {} unless result[sku['salsify:parent_id']][sku[PROPERTY_COLOR_CODE]]
        result[sku['salsify:parent_id']][sku[PROPERTY_COLOR_CODE]][sku_id] = sku
      end
      result
    end
  end

  def client
    @client ||= salsify_client(org_id: ENV.fetch('CARS_ORG_ID'))
  end

end
