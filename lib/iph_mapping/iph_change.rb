module IphMapping
  class IphChange
    include Muffin::SalsifyClient

    attr_reader :org_id, :webhook_name, :styles, :style_by_id, :skus

    def initialize(org_id:, webhook_name:, styles: nil, style_by_id: nil, skus: nil)
      @org_id = org_id
      @webhook_name = webhook_name
      @styles = styles
      @style_by_id = style_by_id
      @skus = skus
    end

    def self.process(org_id, webhook_name, styles)
      new(org_id: org_id, webhook_name: webhook_name, styles: styles).process
    end

    def self.process_skus(org_id, webhook_name, style_by_id, skus)
      new(org_id: org_id, webhook_name: webhook_name, style_by_id: style_by_id, skus: skus).process_skus
    end

    def process
      SalsifyImport.import_products(
        mapped_products,
        salsify,
        import_id,
        PROPERTY_PRODUCT_ID,
        import_filepath
      )
    end

    def process_skus
      SalsifyImport.import_products(
        mapped_products.select { |pr| sku_ids.include?(pr[PROPERTY_PRODUCT_ID]) },
        salsify,
        import_id,
        PROPERTY_PRODUCT_ID,
        import_filepath
      )
    end

    def mapped_products
      @mapped_products ||= IphMapper.map_products(style_by_id, skus_by_style_id)
    end

    def style_by_id
      @style_by_id ||= styles.map do |style|
        [style['salsify:id'], style]
      end.to_h
    end

    def skus_by_style_id
      @skus_by_style_id ||= sku_ids.each_slice(MAX_IDS_PER_CRUD).map do |sku_id_batch|
        salsify.products(sku_id_batch)
      end.flatten.uniq do |sku|
        sku['salsify:id']
      end.group_by do |sku|
        sku[PROPERTY_PARENT_PRODUCT_ID]
      end
    end

    def sku_ids
      @sku_ids ||= begin
        if styles
          styles.each_slice(MAX_IDS_PER_FILTER).map do |style_batch|
            filter.find_children(parent_ids: style_batch.map { |style| style['salsify:id'] })
          end.flatten.map do |partial_sku|
            partial_sku['salsify:id']
          end.uniq
        else
          skus.map { |sku| sku['salsify:id'] }
        end
      end
    end

    def filter
      @filter ||= SalsifyFilter.new(salsify)
    end

    def salsify
      @salsify ||= salsify_client(org_id: org_id)
    end

    def import_id
      @import_id ||= ENV['IPH_MAPPING_IMPORT_ID'] ? ENV['IPH_MAPPING_IMPORT_ID'].to_i : nil
    end

    def import_filepath
      @import_filepath ||= File.join(IMPORT_FILE_LOCATION, import_filename)
    end

    def import_filename
      @import_filename ||= IMPORT_FILE_NAME.gsub('.json', "_#{Time.now.strftime('%Y%m%d_%H%M%S')}.json")
    end

  end
end
