module Demandware

  # Extend DwFeed class, but override certain methods to limit the product selection to "THE LIMITED" products.
  # Also override certain methods to change how we construct the product xml, which properties we pull from, etc.
  class DwLimitedFeed < DwFeed

    NUM_LIMITED_COPY_LINES = 5.freeze

    def stamp
      '$DW FEED LIMITED$'
    end

    def final_master_override!(xml_hash, product_hash)
      xml_hash['product']['display-name'] = { 'xml-value' => product_hash[PROPERTY_LIMITED_COPY_PRODUCT_NAME] }
      xml_hash['product']['long-description'] = { 'xml-value' => product_hash[PROPERTY_LIMITED_COPY_PRODUCT_TEXT] }
      add_limited_custom_attrs!(xml_hash, product_hash)
    end

    def add_limited_custom_attrs!(xml_hash, product_hash)
      xml_hash['product']['custom-attributes'] ||= {}
      xml_hash['product']['custom-attributes']['custom-attribute'] ||= []

      add_limited_copy_data!(xml_hash, product_hash)
    end

    def add_limited_copy_data!(xml_hash, product_hash)
      {
        'copyCare' => PROPERTY_LIMITED_CARE,
        'copyExclusive' => PROPERTY_LIMITED_EXCLUSIVE,
        'copyImportDomestic' => PROPERTY_LIMITED_IMPORT_DOMESTIC,
        'copyMaterial' => PROPERTY_LIMITED_MATERIAL,
        'copyCountryOfOrigin' => PROPERTY_LIMITED_COUNTRY_OF_ORIGIN,
        'copyCAProp65Compliant' => PROPERTY_LIMITED_CA_PROP_65
      }.each do |key, value|
        create_or_update_custom_attr!(xml_hash, product_hash, key, product_hash[value])
      end
    end

    def create_or_update_custom_attr!(xml_hash, product_hash, attr_key, attr_value)
      existing_attr = xml_hash['product']['custom-attributes']['custom-attribute'].find do |attr_hash|
        attr_hash['xml-attribute:attribute-id'] == (attr_key ? attr_key.gsub(' ', '_') : attr_key)
      end
      attr_value = attr_value.map { |v| { 'xml-value' => v } } if attr_value.is_a?(Array)

      if existing_attr && attr_value.is_a?(Array)
        existing_attr.delete('xml-value')
        existing_attr['value'] = attr_value
      elsif existing_attr
        existing_attr.delete('value')
        existing_attr['xml-value'] = attr_value
      else
        xml_hash['product']['custom-attributes']['custom-attribute'] << {
          'xml-attribute:attribute-id' => (attr_key ? attr_key.gsub(' ', '_') : attr_key),
          key => attr_value
        }
      end
    end

    def long_color_code_for_sku(sku_hash, parent_type, parent)
      if parent_type == SALSIFY_TYPE_GROUP_CPG &&
        (['627', 627].include?(parent[PROPERTY_DEPT_NUMBER]) ||
        ['109', 109].include?(parent[PROPERTY_DEMAND_CTR]) ||
        ['5820', '5824', 5820, 5824].include?(parent[PROPERTY_CLASS_NUMBER]))
        "#{sku_hash[PROPERTY_NRF_COLOR_CODE]}#{parent[PROPERTY_GROUP_ORIN]}"
      else
        "#{sku_hash[PROPERTY_NRF_COLOR_CODE]}#{product_families[sku_hash['salsify:parent_id']][PROPERTY_GROUP_ORIN]}"
      end
    rescue Exception => e
      puts "#{stamp} ERROR while determining long color code for sku #{sku_hash['salsify:id']}"
      raise e
    end

    def updated_grouping_products
      @updated_grouping_products ||= updated_products.select do |product_id, product|
        product['salsify:parent_id'].nil? &&
        product[PROPERTY_GROUPING_TYPE] &&
        (
          (
            # CPG group good for limited if any of its child styles has omni brand limited
            GROUPING_TYPES_CPG.include?(product[PROPERTY_GROUPING_TYPE]) &&
            [product[PROPERTY_CHILD_STYLES_OF_GROUP]].flatten.compact.any? { |child_style_id|
              product_families[child_style_id] &&
              product_families[child_style_id][PROPERTY_OMNI_CHANNEL_BRAND] == OMNI_BRAND_LIMITED
            }
          ) ||
          (
            # SCG/SSG groups don't go in the limited feed as of now
            GROUPING_TYPES_SCG_SSG.include?(product[PROPERTY_GROUPING_TYPE]) &&
            false
          ) ||
          (
            # Collection group good for limited if it has omni brand limited
            GROUPING_TYPES_COLLECTION.include?(product[PROPERTY_GROUPING_TYPE]) &&
            product[PROPERTY_OMNI_CHANNEL_BRAND] == OMNI_BRAND_LIMITED
          )
        )
      end
    end

    def updated_base_products
      @updated_base_products ||= updated_products.select do |product_id, product|
        product['salsify:parent_id'].nil? &&
        product[PROPERTY_GROUPING_TYPE].nil? &&
        product[PROPERTY_OMNI_CHANNEL_BRAND] == OMNI_BRAND_LIMITED
      end
    end

    def updated_skus
      @updated_skus ||= updated_products.select do |product_id, product|
        product['salsify:parent_id'] &&
        product_families[product['salsify:parent_id']] &&
        product_families[product['salsify:parent_id']][PROPERTY_OMNI_CHANNEL_BRAND] == OMNI_BRAND_LIMITED
      end
    end

    def parse_main_urls_by_sku_id(sku_by_id)
      sku_by_id.map do |sku_id, sku|
        [
          sku_id,
          parse_urls_by_shot_type(sku, ['scene7 images', 'mainimage url']).select { |shot_type, url|
            next unless shot_type
            shot_type.start_with?('TLC')
          }.compact.values
        ]
      end.to_h
    end

    def parse_swatch_urls_by_sku_id(sku_by_id)
      sku_by_id.map do |sku_id, sku|
        [
          sku_id,
          parse_urls_by_shot_type(sku, ['scene7 images', 'swatchimage url']).select { |shot_type, url|
            next unless shot_type
            shot_type.start_with?('TLC')
          }.compact.values
        ]
      end.to_h
    end

    def image_groups_for_collection(collection_hash)
      [
        {
          'xml-attribute:view-type' => 'imageURL',
          'image' => parse_urls_by_shot_type(
            collection_hash,
            ['scene7 images', 'mainimage url']
          ).select { |shot_type, url|
            next unless shot_type
            shot_type.start_with?('TLC')
          }.compact.map { |shot_type, url|
            { 'xml-attribute:path' => scene7_url(url) }
          }
        },
        {
          'xml-attribute:view-type' => 'swatch',
          'image' => parse_urls_by_shot_type(
            collection_hash,
            ['scene7 images', 'swatchimage url']
          ).select { |shot_type, url|
            next unless shot_type
            shot_type.start_with?('TLC')
          }.compact.map { |shot_type, url|
            { 'xml-attribute:path' => scene7_url(url) }
          }
        },
      ].flatten
    end

    def dw_configured_attributes
      @dw_configured_attributes ||= begin
        wait_for_org_attributes
        attributes.select do |attribute|
          attribute[DW_META_SOURCE_LEVEL] &&
          attribute[DW_META_XML_LEVEL] &&
          attribute[DW_META_XML_PATH] &&
          (attribute[DW_META_FEED].nil? || attribute[DW_META_FEED].include?('limited'))
        end.map { |att|
          att.map { |key, val| [key.to_s, val.is_a?(Array) ? val.map { |v| v.to_s } : val.to_s] }.to_h
        }
      end
    end

    def is_style_complete?(style)
      if style[PROPERTY_GROUPING_TYPE] != GROUPING_TYPES_RCG
        style[PROPERTY_COPY_APPROVAL_STATE] == true
      else
        style[PROPERTY_COPY_APPROVAL_STATE] == true && style[PROPERTY_SCENE7_IMAGE_TLCA]
      end
    end

    def is_sku_complete?(sku:, color_master: nil)
      if sku[PROPERTY_GROUPING_TYPE] != GROUPING_TYPES_RCG
        scene7_url = (color_master ? color_master[PROPERTY_SCENE7_IMAGE_TLCA] : sku[PROPERTY_SCENE7_IMAGE_TLCA])
        scene7_url.is_a?(String) &&
        !scene7_url.empty? &&
        (sku[PROPERTY_OMNI_COLOR_DESC] || sku[PROPERTY_VENDOR_COLOR_DESC]) &&
        (sku[PROPERTY_OMNI_SIZE_DESC] || sku[PROPERTY_VENDOR_SIZE_DESC])
      else
        sku[PROPERTY_COPY_APPROVAL_STATE] && sku[PROPERTY_SCENE7_IMAGE_TLCA]
      end
    end

    def write_xml_files_and_zip(xml_strings)
      puts "#{stamp} Writing #{xml_strings.length} xml files"
      recursive_init_dir(LOCAL_PATH_DW_FEED_XMLS_DW)
      recursive_init_dir(LOCAL_PATH_DW_FEED_ZIPS_DW)
      FileUtils.rm_rf(Dir.glob("#{LOCAL_PATH_DW_FEED_XMLS_DW}/#{xml_file_prefix_belk}*"))

      count = 100
      xml_filepaths = xml_strings.each_with_index.map do |xml_string, index|
        filepath = File.join(LOCAL_PATH_DW_FEED_XMLS_DW, xml_file_name_belk(count + index))
        File.open(filepath, 'w') { |file| file.write(xml_string) }
        filepath
      end
      # Format timestamp as 20170908_182500 in EST

      result = { dw: [], cfh: [] }
      xml_filepaths.map do |xml_filepath|
        xml_file_name = xml_filepath.split('/').last
        dw_zip_path = File.join(LOCAL_PATH_DW_FEED_ZIPS_DW, xml_file_name.gsub('.xml', '.xml.gz'))
        Zlib::GzipWriter.open(dw_zip_path) do |gz|
          gz.mtime = File.mtime(xml_filepath)
          gz.orig_name = xml_file_name
          gz.write(IO.binread(xml_filepath))
        end
        result[:dw] << dw_zip_path
      end
      result
    end

    def filter_dw_zips(filepaths)
      filepaths.select { |path| path.split('/').last.start_with?('LTD') }
    end

    def xml_mode
      XML_MODE_LIMITED
    end

    def xml_file_prefix_belk
      'LTD_Catalog_Salsify_Delta_'
    end

    def feed_done_email_subject
      "Finished Belk #{mode == :prod ? 'PROD' : 'QA'} Demandware LIMITED catalog export"
    end

    def feed_done_email_body(filepaths)
      "<p>Finished generation of LIMITED Belk Demandware XML feed.</p>" +
      "<p>Environment: #{ENV.fetch('CARS_ENVIRONMENT')}</p>" +
      "<p>Processed modified products in timeframe: #{since_datetime.in_time_zone('America/New_York').to_s} => #{to_datetime.in_time_zone('America/New_York').to_s}</p>" +
      "<p>Processed recorded file names:</p>" +
      "<ul>" +
      (recorded_products_local_filepaths.sort.map { |path| "<li>#{path.split('/').last}</li>" }.join('')) +
      "</ul><br/>" +
      "<p># Files generated: #{filepaths.length}</p>" +
      "<p>Generated file names:</p>" +
      "<ul>" +
      (filepaths.map { |path| "<li>#{path.split('/').last}</li>" }.join("")) +
      "</ul><br/>" +
      "<p># Total Updated Products: #{updated_products.length}</p>" +
      "<p># Updated Styles: #{updated_base_products.length}</p>" +
      "<p># Updated Skus: #{updated_skus.length}</p>" +
      "<p># Updated Groupings: #{updated_grouping_products.length}</p>" +
      "<p>Total Time to Generate Feed: #{((Time.now - t_start) / 60).round(1)} minutes"
    end

    def error_report_email_subject
      "Belk #{mode == :prod ? 'PROD' : 'QA'} Demandware LIMITED catalog export ERROR"
    end

    def error_report_email_body(e)
      "<p>An error occurred while generating Belk Demandware LIMITED catalog XML feed.</p>" +
      "<p>Error: #{e.message}</p>" +
      "<p>Error Stack Trace:</p>" +
      "#{e.backtrace.join('<br/>')}"
    end

    def set_job_status_failed(error)
      JobStatus.where(title: 'dwre_limited').last.update_attributes!(
        activity: "Failed to generate xml for range: #{since_datetime.strftime('%Y-%m-%d %H:%M:%S %Z')} to #{to_datetime.strftime('%Y-%m-%d %H:%M:%S %Z')}, sent email alert",
        error: error.message
      )
    end

    def publish_pending_import_id
      @publish_pending_import_id ||= ENV.fetch('DW_IMPORT_ID_PUBLISH_PENDING_LIMITED').to_i
    end

    def sent_to_dw_import_id
      @sent_to_dw_import_id ||= ENV.fetch('DW_IMPORT_ID_SENT_TO_DW_LIMITED').to_i
    end

    def filename_publish_pending_import
      @filename_publish_pending_import ||= FILENAME_PUBLISH_PENDING_IMPORT_LTD
    end

    def sent_to_dw_import_filename
      @sent_to_dw_import_filename ||= FILENAME_SENT_TO_DW_IMPORT_LTD
    end

  end

end
