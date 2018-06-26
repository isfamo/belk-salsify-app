module Enrichment
  class Dictionary
    include Muffin::SalsifyClient

    YES = 'yes'.freeze

    LOOKUP_ATTRIBUTES_MAPPING = {
      'omniChannelColorDescription' => :color_data,
      'refinementColor' => :color_data,
      'omniSizeDesc' => :size_data,
      'refinementSize' => :size_data,
      'Refinement SubSize' => :size_data,
      'iphCategory' => :dept_iph_data,
      'OmniChannel Brand' => :brand_data
    }.freeze
    LOOKUP_ATTRIBUTES = LOOKUP_ATTRIBUTES_MAPPING.keys.freeze

    def initialize
      salsify_client(org_id: ENV.fetch('CARS_ORG_ID'))
    end

    def google_sheet
      @google_sheet ||= GoogleSheet.new
    end

    def dept_iph(dept, klass)
      validate(google_sheet.iph_lookup.try(:[], dept).try(:[], klass))
    end

    def omni_size(dept, nrf_size_code)
      validate(sizes.try(:[], dept).try(:[], nrf_size_code).try(:[], :omni_size))
    end

    def refinement_size(dept, nrf_size_code)
      validate(sizes.try(:[], dept).try(:[], nrf_size_code).try(:[], :refinement_size))
    end

    def refinement_sub_size(dept, nrf_size_code)
      validate(sizes.try(:[], dept).try(:[], nrf_size_code).try(:[], :refinement_sub_size))
    end

    def omni_color(nrf_color_code)
      validate(colors.try(:[], nrf_color_code).try(:[], :omni_color))
    end

    def refinement_color(nrf_color_code)
      validate(colors.try(:[], nrf_color_code).try(:[], :refinement_color))
    end

    def omni_brand(vendor_number)
      validate(google_sheet.brand_lookup.try(:[], vendor_number).try(:[], :omni_brand_name))
    end

    def iph_attrs
      google_sheet.iph_attrs
    end

    def validate(result)
      return unless result
      if result.is_a?(Array)
        result.first if result.uniq.count <= 1
      else
        result
      end
    end

    def colors
      google_sheet.color_lookup
    end

    def sizes
      google_sheet.size_lookup
    end

    def non_assignable_categories
      @non_assignable_categories ||= google_sheet.non_selectable_categories_data.map do |category|
        category[:category]
      end
    end

    def attributes
      enrichment_attributes.each do |attribute|
        categorical_metadata = google_sheet.attributes[attribute['salsify:id']]
        if categorical_metadata
          attribute[:category_specific] = true
          attribute[:categories] = categorical_metadata.map { |metadata| metadata[:category] }
          attribute[:required_categories] = categorical_metadata.map do |metadata|
            metadata[:category] if metadata[:mandatory].try(:downcase) == YES
          end.compact.uniq
          attribute[:category_specific_values] = categorical_metadata.map do |metadata|
            { category: metadata[:category], values: metadata[:attribute_values] }
          end
        else
          attribute[:values] = attribute_values[attribute['salsify:id']] || attribute_values[attribute['salsify:id']]
          if LOOKUP_ATTRIBUTES_MAPPING[attribute['salsify:id']]
            attribute[:lookup_values] = google_sheet.send(LOOKUP_ATTRIBUTES_MAPPING[attribute['salsify:id']])
          end
        end
      end.map { |attribute| Attribute.new(attribute) }
    end

    def category_mapping
      @category_mapping ||= categories.map do |category|
        [ category[:mapping], category[:id] ]
      end.to_h
    end

    def enrichment_attributes
      attribute_export.select { |attribute| attribute['belk:enrichment_attribute'].try(:downcase) == 'true' }
    end

    def attribute_values
      @attribute_values ||= format_attribute_values(attribute_value_export(format: :xlsx)).group_by do |row|
        row['salsify:attribute_id']
      end
    end

    def format_attribute_values(export)
      export.map do |row|
        if row['salsify:attribute_id'] == 'nrfColorCode'
          row['salsify:id'] = row['salsify:name'] = '%03d' % row['salsify:id'].to_i
        end
        row
      end
    end

    def category_tree
      categories.map do |category|
        [ category[:id], fetch_categories(category[:id]) ]
      end.to_h
    end

    def fetch_categories(category)
      categories.map do |_category|
        next unless _category[:id].include?("#{category} > ") && !_category[:id].include?("> #{category} > ")
        _category[:id]
      end.compact
    end

    def categories
      @categories ||= google_sheet.categories
    end

    class Attribute

      TRUE = 'true'.freeze

      attr_reader :metadata

      def initialize(metadata)
        @metadata = metadata
      end

      def name
        metadata['salsify:name']
      end

      def id
        metadata['salsify:id']
      end

      def data_type
        type = metadata['salsify:data_type']
        type == 'rich_text' ? 'string' : type
      end

      def attribute_group
        metadata['salsify:attribute_group']
      end

      def multivalue?
        metadata['belk:multivalue'].try(:downcase) == TRUE
      end

      def categories
        metadata[:categories]
      end

      def required_categories?
        required_categories.present?
      end

      def required_categories
        metadata[:required_categories]
      end

      def category_specific
        metadata[:category_specific]
      end

      def values
        metadata[:values] || []
      end

      def applicable_scopes(fields, enumerated_value)
        lookup_values.select do |value|
          value[id].is_a?(Array) ? value[id].include?(enumerated_value) : value[id] == enumerated_value
        end.map { |value| value.slice(*fields) }
      end

      def lookup_values
        metadata[:lookup_values]
      end

      def category_specific_values
        metadata[:category_specific_values]
      end

      def role
        metadata['belk:role'].try(:downcase)
      end

    end

    class GoogleSheet
      include Muffin::GoogleSheetClient

      QA_SHEET_ID = '1hE_eLuvrIYSLqUb0LUqqXFVfNYVg_Wi-Oqz_JhiY0k8'.freeze
      PROD_SHEET_ID = '1cAUIEEp8OKrn_xjOx5fUyo9sv618Qg933Abx4hARXDU'.freeze
      ATTRIBUTE_MAPPING = {
        eis_hier_iph_name: 'iphCategory',
        omni_color: 'omniChannelColorDescription',
        refinement_color: 'refinementColor',
        facet_size_1: 'refinementSize',
        facet_size_2: 'refinementSize',
        facet_size_3: 'refinementSize',
        facet_sub_size_1: 'Refinement SubSize',
        facet_sub_size_2: 'Refinement SubSize',
        facet_sub_size_3: 'Refinement SubSize',
        omni_size_desc: 'omniSizeDesc',
        omni_brand_name: 'OmniChannel Brand'
      }.freeze

      def attributes
        @attributes ||= category_data.group_by { |row| row[:attribute] }
      end

      def categories
        @categories ||= begin
          assembled_categories = category_data.map do |row|
            [ row[:category], row[:category_mapping] ]
          end.map do |category, mapping|
            build_category(category, mapping)
          end.uniq
        end
        assembled_categories.map do |category|
          if category[:parent].present? && !assembled_categories.find { |cat| cat[:parent] == category[:parent] }
            build_category(category[:parent])
          end
        end.compact + assembled_categories
      end

      def build_category(category, mapping)
        {
          id: category,
          name: category.include?(' > ') ? category.split(' > ').last : category,
          parent: category.split(' > ').reverse.drop(1).reverse.join(' > '),
          mapping: mapping
        }
      end

      def iph_lookup
        @iph_lookup ||= dept_iph_data.each_with_object({}) do |row, hash|
          hash[row[:dept]] ||= {}
          hash[row[:dept]][row[:class]] ||= []
          hash[row[:dept]][row[:class]] << row[:eis_hier_iph_name].try(:strip)
        end
      end

      def size_lookup
        @size_lookup ||= size_data.each_with_object({}) do |row, hash|
          hash[row[:dept]] ||= {}
          hash[row[:dept]][row[:nrf_size_code]] ||= { omni_size: [], refinement_size: [], refinement_sub_size: []}
          hash[row[:dept]][row[:nrf_size_code]][:omni_size] << row[:omni_size_desc].try(:strip)
          hash[row[:dept]][row[:nrf_size_code]][:refinement_size] << [ row[:facet_size_1], row[:facet_size_2], row[:facet_size_3] ].compact.reject(&:empty?)
          hash[row[:dept]][row[:nrf_size_code]][:refinement_sub_size] << [ row[:facet_sub_size_1], row[:facet_sub_size_2], row[:facet_sub_size_3] ].compact.reject(&:empty?)
        end
      end

      def color_lookup
        @color_lookup ||= color_data.map do |row|
          [
            row[:nrf_color_code],
            {
              omni_color: row[:omni_color].try(:strip),
              refinement_color: row[:refinement_color].try(:strip)
            }
          ]
        end.to_h
      end

      def brand_lookup
        @brand_lookup ||= brand_data.each_with_object({}) do |row, hash|
          hash[row[:vendor_number]] ||= { omni_brand_name: [] }
          hash[row[:vendor_number]][:omni_brand_name] << row[:omni_brand_name].try(:strip)
        end
      end

      def sheet_id
        @sheet_id ||= ENV['CARS_ENVIRONMENT'] == 'production' ? PROD_SHEET_ID : QA_SHEET_ID
      end

      def category_data
        sheet_data(sheet_id, 'IPH!A:Z').each { |row| row[:category_specific] = 'true' }
      end

      def non_selectable_categories_data
        sheet_data(sheet_id, 'NonSelectableCategories!A:Z')
      end

      def dept_iph_data
        @dept_iph_data ||= add_attribute_specific_columns(sheet_data(sheet_id, 'DeptIPHLookup!A:Z'))
      end

      def size_data
        @size_data ||= add_attribute_specific_columns(sheet_data(sheet_id, 'OmniSizeLookup!A:Z'))
      end

      def color_data
        @color_data ||= add_attribute_specific_columns(sheet_data(sheet_id, 'OmniColorFamilyLookup!A:Z'))
      end

      def brand_data
        @brand_data ||= add_attribute_specific_columns(sheet_data(sheet_id, 'OmniBrandLookup!A:Z'))
      end

      def iph_attrs
        @iph_attrs ||= sheet_data(sheet_id, 'IPH!A:Z')
      end

      def add_attribute_specific_columns(data)
        data.each do |row|
          row.keys.each do |column|
            next unless ATTRIBUTE_MAPPING[column]
            next unless row[column].present?
            row[ATTRIBUTE_MAPPING[column]] ||= []
            row[ATTRIBUTE_MAPPING[column]] << row[column].try(:strip)
          end
        end
      end

    end

  end
end
