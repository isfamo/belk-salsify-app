module Enrichment
  class TargetSchema
    include Muffin::SalsifyAdminClient
    include Muffin::S3Client

    FILE_LOCATION = 'lib/enrichment_integration/cache/target_schema.json'

    attr_reader :dictionary
    attr_accessor :schema

    def initialize(user_email)
      @user_email = user_email
      @schema = Amadeus::TargetSchema::Schema.new
      @dictionary = Dictionary.new
      if ENV['CARS_ENVIRONMENT'] == 'production'
        @target_schema_internal_id = '2128'
        @schema_name = 'belk_enrichment_prod.json'
      else
        @target_schema_internal_id = '1278'
        @schema_name = 'belk_enrichment_qa.json'
      end
    end

    def self.generate_and_import(user_email)
      new(user_email).generate_and_import
    end

    def self.generate(user_email)
      new(user_email).generate
    end

    def generate_and_import
      puts '$ENRICHMENT SCHEMA$ refreshing target schema...'
      generate
      import
      notify_user
      puts '$ENRICHMENT SCHEMA$ target schema refresh complete...'
    end

    def generate
      append_fields
      append_parent_validation
      serialize
    end

    def append_fields
      puts '$ENRICHMENT SCHEMA$ appending fields to target schema...'
      dictionary.attributes.each do |attribute|
        schema.add_field(Field.generate(attribute, category_tree, non_assignable_categories))
      end
    end

    def non_assignable_categories
      dictionary.non_assignable_categories
    end

    def category_tree
      @category_tree ||= dictionary.category_tree
    end

    def append_parent_validation
      schema.parent_id_field_ids = [ 'iphCategory' ]
      schema.parent_product_type = 'Style'
      schema.child_product_type = 'SKU'
    end

    def serialize
      puts '$ENRICHMENT SCHEMA$ serializing target schema...'
      File.open(FILE_LOCATION, 'w') { |file| file.write(schema.serialize) }
    end

    def import
      puts '$ENRICHMENT SCHEMA$ importing target schema...'
      @import_response = Amadeus::TargetSchema::Schema.import_target_schema(
        client: salsify_admin_client,
        file_url: s3_url,
        target_schema_id: @target_schema_internal_id,
        org_id: ENV.fetch('CARS_ORG_ID'),
        dry_run: false
      )
    end

    def s3_object
      @s3_object ||= s3_resource.bucket(ENV.fetch('AWS_BUCKET_NAME')).object(
        File.join('customers', 'converted_target_schemas', @schema_name)
      )
    end

    def s3_url
      s3_object.put(body: schema.serialize)
      s3_object.presigned_url(:get, expires_in: 3600, response_content_disposition: 'attachment')
    end

    def notify_user
      EmailNotifier.notify(user_email: @user_email, import: @import_response)
    end

  end

  class Field < Amadeus::TargetSchema::Field

    IPH_CATEGORY = 'iphCategory'.freeze
    DEPT = 'Dept#'.freeze
    CLASS = 'Class#'.freeze
    APPLICABLE_SCOPE_FIELDS = {
      'omniSizeDesc' => [ :dept, :nrf_size_code ],
      'refinementSize' => [ :dept, :nrf_size_code ],
      'Refinement SubSize' => [ :dept, :nrf_size_code ],
      'refinementColor' => [ :nrf_color_code ],
      'omniChannelColorDescription' => [ :nrf_color_code ],
      'OmniChannel Brand' => [ :vendor_number ],
      IPH_CATEGORY => [ :dept, :class ]
    }
    FIELD_MAP = {
      dept: 'Dept#',
      class: 'Class#',
      vendor_number: 'vendorNumber',
      nrf_size_code: 'nrfSizeCode',
      nrf_color_code: 'nrfColorCode'
    }.freeze

    attr_reader :attribute, :category_tree, :non_assignable_categories

    def initialize(attribute, category_tree, non_assignable_categories)
      @attribute = attribute
      @category_tree = category_tree
      @non_assignable_categories = non_assignable_categories
      super()
    end

    def self.generate(attribute, category_tree, non_assignable_categories)
      new(attribute, category_tree, non_assignable_categories).generate
    end

    def generate
      self.external_id = attribute.id
      self.name = attribute.name
      self.data_type = attribute.data_type
      self.field_group_external_id = attribute.attribute_group
      self.classifier = true if attribute.id == IPH_CATEGORY
      attribute.multivalue? ? set_max_num_constaint(3) : set_max_num_constaint
      add_field_values_and_applicable_scopes
      set_product_type
      add_hierarchical_iph_values if attribute.id == IPH_CATEGORY
      self
    end

    def set_product_type
      applicable_scopes.product_type = attribute.role == 'sku' ? 'child' : 'parent'
    end

    def add_field_values_and_applicable_scopes
      if attribute.category_specific
        add_category_dependencies
        add_required_category_dependencies
        add_category_field_values
      else
        add_field_values
      end
    end

    def add_category_dependencies
      scope = find_or_create_applicable_scope(IPH_CATEGORY)
      add_applicable_scope_values(scope, attribute.categories)
    end

    def add_required_category_dependencies
      return unless attribute.required_categories?
      requirement = Amadeus::TargetSchema::MinNumValues.new
      requirement.floor = 1
      scope = requirement.find_or_create_applicable_scope(IPH_CATEGORY)
      add_applicable_scope_values(scope, attribute.required_categories)
      add_requirement(requirement)
    end

    def add_applicable_scope_values(scope, categories)
      categories.each do |category|
        scope.add_value(category)
        fetch_child_nodes(category).each { |_category| scope.add_value(_category) }
      end
    end

    def fetch_child_nodes(category)
      category_tree[category]
    end

    def add_category_field_values
      return unless self.data_type == 'enumerated'
      attribute.category_specific_values.each do |category_values|
        values = category_values[:values].split('|').map(&:strip).uniq
        values.each do |value|
          next unless value.present?
          field_value = get_field_value(value) || Amadeus::TargetSchema::FieldValue.new
          field_value.external_id = field_value.name = value
          scope = field_value.find_or_create_applicable_scope(IPH_CATEGORY)
          scope.add_value(category_values[:category])
          append_lookup_values(field_value)
          add_field_value(field_value)
        end
      end
    end

    def add_field_values
      return unless self.data_type == 'enumerated'
      attribute.values.uniq { |value| value['salsify:id'] }.each do |value|
        next unless value['salsify:id'].present?
        field_value = Amadeus::TargetSchema::FieldValue.new
        field_value.external_id = value['salsify:id']
        field_value.name = value['salsify:name']
        field_value.parent_id = value['salsify:parent_id']
        if external_id == IPH_CATEGORY && non_assignable_categories.include?(value['salsify:id'])
          field_value.assignable = false
        end
        append_lookup_values(field_value)
        add_field_value(field_value)
      end
    end

    def append_lookup_values(field_value)
      return unless attribute.lookup_values.present?
      applicable_scope_fields = APPLICABLE_SCOPE_FIELDS[external_id]
      applicable_scopes = attribute.applicable_scopes(applicable_scope_fields, field_value.external_id)
      return unless applicable_scopes.first.present?
      applicable_scopes.each do |values|
        values.each do |field, value|
          if [ 'omniSizeDesc', 'refinementSize' ].include?(external_id)
            field_value.applicable_scopes.grouping_conditional ||= true
            scope = field_value.create_applicable_scope(FIELD_MAP[field])
            scope.grouping_key = values.to_s
            scope.add_value(value)
          else
            scope = field_value.find_or_create_applicable_scope(FIELD_MAP[field])
            scope.add_value(value)
          end
        end
      end
    end

    def add_hierarchical_iph_values
      field_values.each do |_, field_value|
        scope = field_value.get_applicable_scope_for(IPH_CATEGORY)
        next if scope
        categories = category_tree[field_value.external_id]
        next unless categories.present?
        categories.each do |category|
          category_field = get_field_value(category)
          next unless category_field
          [ DEPT, CLASS ].each do |field|
            scope = field_value.find_or_create_applicable_scope(field)
            values = category_field.get_applicable_scope_values_for(field)
            values.each { |value| scope.add_value(value) }
          end
        end
      end
    end

    def set_max_num_constaint(value = 1)
      requirement = Amadeus::TargetSchema::MaxNumValues.new
      requirement.ceiling = value
      add_requirement(requirement)
    end

  end
end
