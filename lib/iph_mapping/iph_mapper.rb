module IphMapping
  class IphMapper

    attr_reader :style_by_id, :skus_by_style_id

    def initialize(style_by_id, skus_by_style_id)
      @style_by_id = style_by_id
      @skus_by_style_id = skus_by_style_id
    end

    def self.map_products(style_by_id, skus_by_style_id)
      new(style_by_id, skus_by_style_id).map_products
    end

    def map_products
      mapped_styles = style_by_id.map do |style_id, style|
        map_product(style).merge({
          PROPERTY_LAST_IPH_GXS_MAPPING => style[PROPERTY_IPH_CATEGORY],
          PROPERTY_LAST_IPH_GXS_MAPPING_DATE => timestamp_date,
          PROPERTY_LAST_IPH_GXS_MAPPING_TIME => timestamp_time
        })
      end

      mapped_skus = skus_by_style_id.map do |style_id, skus|
        skus.map do |sku|
          map_product(sku).merge({
            PROPERTY_LAST_IPH_GXS_MAPPING_DATE => timestamp_date,
            PROPERTY_LAST_IPH_GXS_MAPPING_TIME => timestamp_time,
            PROPERTY_SKU_NEEDS_IPH_MAPPING => false
          })
        end
      end.flatten

      mapped_styles + mapped_skus
    end

    def map_product(product)
      # Identify IPH category and its IPH-specific attributes
      parent = product[PROPERTY_PARENT_PRODUCT_ID] ? style_by_id[product[PROPERTY_PARENT_PRODUCT_ID]] : nil
      new_iph_category = product[PROPERTY_IPH_CATEGORY] || (parent ? parent[PROPERTY_IPH_CATEGORY] : nil)
      old_iph_category = product[PROPERTY_LAST_IPH_GXS_MAPPING] || (parent ? parent[PROPERTY_LAST_IPH_GXS_MAPPING] : nil)
      new_iph_attrs = iph_attrs_for_category(new_iph_category)
      old_iph_attrs = iph_attrs_for_category(old_iph_category)

      # Remove attrs specific to old IPH selection but not in new IPH selection
      rm_old_attrs_hash = (old_iph_attrs - new_iph_attrs).map { |iph_attr| [iph_attr, nil] }.to_h

      # Build hash of attrs specific to new IPH selection
      add_new_attrs_hash = iph_mappings.map do |src_attr, config|
        map_attr(product, src_attr, config, new_iph_attrs)
      end.compact.reduce({}, :merge).merge({
        PROPERTY_PRODUCT_ID => product['salsify:id']
      })

      # Merge new onto old attrs
      rm_old_attrs_hash.merge(add_new_attrs_hash)
    end

    # Determine whether we should map for this IPH-specific attribute for this product.
    # Returns either nil or a hash of mapped values for this attribute.
    def map_attr(product, src_attr, config, iph_attrs)

      # Determine which attributes the source attribute maps to for this IPH
      target_attrs = config['maps_to'].select do |target_attr|
        config['iph_dependent'] == false ||
        (target_attr.is_a?(String) && iph_attrs.include?(target_attr)) ||
        (target_attr.is_a?(Hash) && iph_attrs.include?(target_attr['property_id']))
      end

      if !target_attrs.empty? && # has iph-specific attributes to map to, OR isn't iph-dependent
        product[src_attr] && # product has value for source attribute?
        level_match?(product, config['level']) # at correct style/sku level?

        target_attrs.map do |target_attr|
          property_id = target_attr.is_a?(String) ? target_attr : target_attr['property_id']
          value = product[src_attr]

          # Check if any transformations need to be done
          if target_attr.is_a?(Hash) && target_attr['transforms']
            # Apply transforms for this specific target attribute
            value = apply_transforms(product, value, target_attr['transforms'])
          elsif config['transforms']
            # Apply transforms configured for this source attribute
            value = apply_transforms(product, value, config['transforms'])
          end

          [property_id, value]
        end.to_h
      end
    end

    def level_match?(product, level)
      (level == 'style' && product['salsify:parent_id'].nil?) ||
      (level == 'sku' && product['salsify:parent_id'])
    end

    def apply_transforms(product, src_value, transforms)
      results = [src_value].flatten(1).map do |value|
        transforms.each { |transform| value = apply_transform(product, value, transform) }
        value
      end
      results.length > 1 ? results : results.first
    end

    def apply_transform(product, src_value, transform)
      if transform['type'] == 'code'
        gxs_codes[transform['dict']][src_value]
      end
    end

    def iph_mappings
      @iph_mappings ||= config_json['iph_mapping']
    end

    def gxs_codes
      @gxs_codes ||= config_json['gxs_codes']
    end

    def iph_attrs_from_gxs
      @iph_attrs_from_gxs ||= iph_mappings.map { |src_attr, config| config['maps_to'] }.flatten.uniq.sort
    end

    def config_json
      @config_json ||= IphConfig.load_config
    end

    def iph_attrs_for_category(iph_category)
      # Identify if this category has a parent category
      parent_category = nil
      if iph_category && iph_category.include?(' > ')
        parent_category = iph_category.split(' > ')[0..-2].join(' > ')
      end

      # Determine attributes for this category
      attrs_this_category = dictionary_attributes.select do |attribute|
        attribute.categories && attribute.categories.include?(iph_category)
      end.map { |attribute| attribute.name }

      # Return these attributes and any for parent category
      parent_attrs = parent_category ? iph_attrs_for_category(parent_category) : []
      (attrs_this_category + parent_attrs).uniq
    end

    def dictionary_attributes
      @dictionary_attributes ||= begin
        t = Time.now
        puts "#{STAMP} Retrieving data dictionary from Google Drive"
        a = data_dictionary.attributes
        puts "#{STAMP} Retrieved data dictionary in #{((Time.now - t) / 60).round(1)} min"
        a
      end
    end

    def data_dictionary
      @data_dictionary ||= Enrichment::Dictionary.new
    end

    def timestamp_date
      @timestamp_date ||= Time.now.strftime('%Y-%m-%d')
    end

    def timestamp_time
      @timestamp_time ||= Time.now.in_time_zone('America/New_York').strftime('%H%M%S').to_i
    end

  end
end
