module NewProductWorkflow
  class Recalculate
    include Muffin::SalsifyClient

    STAMP = '$SPLIT_JOIN$'.freeze
    MAX_IDS_PER_CRUD = 100.freeze
    NUM_THREADS_CRUD = 4.freeze

    PROPERTY_ALL_IMAGES = 'All Images'.freeze
    PROPERTY_COLOR_MASTER = 'Color Master?'.freeze
    PROPERTY_NRF_COLOR_CODE = 'nrfColorCode'.freeze

    attr_reader :product_ids

    def initialize(product_ids)
      @product_ids = product_ids
    end

    def self.recalculate(product_ids)
      new(product_ids).recalculate
    end

    def recalculate
      apply_changes(recalculate_all_images.merge(recalculate_color_masters))
    end

    def recalculate_all_images
      style_by_id.map do |style_id, style|
        child_sku_by_id = sku_by_id.select { |id, sku| sku['salsify:parent_id'] == style_id }
        family_by_id = child_sku_by_id.merge({ style_id => style })
        PIMFeed::SalsifyImportFile::AddImagesToStyle.run(family_by_id)
        update_hash = { PROPERTY_ALL_IMAGES => family_by_id[style_id][PROPERTY_ALL_IMAGES] }
        [style_id, update_hash]
      end.to_h
    end

    def recalculate_color_masters
      change_by_id = {}

      # For each affected style...
      style_by_id.each do |style_id, style|

        # Find all child skus
        sku_ids = sku_ids_by_parent_id[style_id]
        next unless sku_ids

        # Group by NRF color code
        skus_by_color = sku_ids.map do |sku_id|
          sku_by_id[sku_id]
        end.group_by do |sku|
          sku[PROPERTY_NRF_COLOR_CODE]
        end

        # Adjust skus so each color has one color master
        skus_by_color.select do |color_code, skus|
          color_masters = skus.select { |sku| sku[PROPERTY_COLOR_MASTER] }
          if color_masters.empty?
            # Color has no color master, pick one
            change_by_id[skus.first['salsify:id']] ||= {}
            change_by_id[skus.first['salsify:id']][PROPERTY_COLOR_MASTER] = true
          elsif color_masters.length > 1
            # Color has multiple color masters, make all but one non-master
            color_masters[1..-1].each do |sku|
              change_by_id[sku['salsify:id']] ||= {}
              change_by_id[sku['salsify:id']][PROPERTY_COLOR_MASTER] = nil
            end
          end
        end
      end
      change_by_id
    end

    def apply_changes(change_by_id)
      puts "#{STAMP} Starting CRUD updates for #{change_by_id.length} products, using #{NUM_THREADS_CRUD} parallel threads"
      Parallel.each(change_by_id, in_threads: NUM_THREADS_CRUD) do |product_id, change_hash|
        client.update_product(product_id, change_hash)
      end
    end

    def style_by_id
      @style_by_id ||= provided_style_by_id.merge(absent_style_by_id)
    end

    def sku_by_id
      @sku_by_id ||= all_sku_ids.each_slice(MAX_IDS_PER_CRUD).map do |sku_id_batch|
        client.products(sku_id_batch)
      end.flatten.map { |sku| [sku['salsify:id'], sku] }.to_h
    end

    def sku_ids_by_parent_id
      @sku_ids_by_parent_id ||= sku_by_id.values.group_by do |sku|
        sku['salsify:parent_id']
      end.map do |style_id, skus|
        [style_id, skus.map { |sku| sku['salsify:id'] }]
      end.to_h
    end

    def all_sku_ids
      @all_sku_ids ||= filter.find_children(
        parent_ids: (provided_style_by_id.keys + absent_style_ids).compact.uniq
      ).map { |sku| sku['salsify:id'] }
    end

    def provided_product_by_id
      @provided_product_by_id ||= product_ids.each_slice(MAX_IDS_PER_CRUD).map do |product_id_batch|
        client.products(product_id_batch)
      end.flatten.map { |product| [product['salsify:id'], product] }.to_h
    end

    def provided_style_by_id
      @provided_style_by_id ||= provided_product_by_id.select do |id, product|
        product['salsify:parent_id'].nil?
      end
    end

    def provided_sku_by_id
      @provided_sku_by_id ||= provided_product_by_id.select do |id, product|
        product['salsify:parent_id']
      end
    end

    def absent_style_ids
      @absent_style_ids ||= (provided_sku_by_id.map { |id, sku| sku['salsify:parent_id'] }.uniq - provided_style_by_id.keys)
    end

    def absent_style_by_id
      @absent_style_by_id ||= absent_style_ids.each_slice(MAX_IDS_PER_CRUD).map do |id_batch|
        client.products(id_batch)
      end.flatten.map { |product| [product['salsify:id'], product] }.to_h
    end

    def client
      @client ||= salsify_client(org_id: ENV.fetch('CARS_ORG_ID').to_i)
    end

    def filter
      @filter ||= SalsifyFilter.new(client)
    end

  end
end
