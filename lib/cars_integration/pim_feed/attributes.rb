module PIMFeed
  class Attributes

    def xml_map
      @xml_map ||= global_attributes.merge(category_attributes).merge(workflows)
    end

    def salsify_map
      @salsify_map ||= xml_map.map do |_, attribute|
        [ attribute['Salsify ID'], attribute ]
      end.compact.to_h
    end

    def attribute_name(attribute)
      salsify_map.fetch(attribute, {}).fetch('Salsify Display Name', attribute)
    end

    def attribute_group(attribute)
      salsify_map.fetch(attribute, {}).fetch('Attribute Group', nil)
    end

    def data_type(attribute)
      return 'string' unless attribute
      type = xml_map.fetch(attribute, {}).fetch('Type', nil) || salsify_map.fetch(attribute, {}).fetch('Type', nil)
      case
      when type.nil?
        'string'
      when enumerated?(type)
        'enumerated'
      when type == 'Integer'
        'number'
      when type == 'html'
        'html'
      when type == 'boolean'
        'boolean'
      else
        'string'
      end
    end

    def enumerated?(type)
      type == 'enumerated' || type.downcase.include?('drop') || type.downcase.include?('radio')
    end

    def format_values(product)
      product.each do |attribute, value|
        next unless value || value == false
        product[attribute] = case data_type(attribute)
        when 'enumerated'
          if [ true, false ].include?(value)
            value.to_s
          else
            value
          end
        when 'number'
          value.to_s.match('\.') ? Float(value) : Integer(value) rescue value.to_s
        else
          value
        end
      end
    end

    private

    def global_attributes
      worksheet.sheet('Global Attributes').each(headers: true, clean: true).drop(1).map do |row|
        [ row['XML Name'], row.except('Editable(Y/N)', 'Mandatory(Y/N)') ]
      end.compact.to_h
    end

    def category_attributes
      worksheet.sheet('Attribute Field Names').each(headers: true, clean: true).drop(1).map do |row|
        [
          row['XML Name'],
          row.except('IS_DISPLAYABLE', 'IS_EDITABLE', 'IS_MANDATORY', 'HTML_DISPLAY_DESC', 'MAX_OCCURANCE')
        ]
      end.compact.to_h
    end

    def workflows
      Hash.new { |h,k| h[k] = { 'Picklist Values' => Set.new } }.tap do |hash|
        worksheet.sheet('Workflow Status').each(headers: true, clean: true).drop(1).each do |row|
          hash[row['Attribute']]['XML Name'] ||= row['Attribute']
          hash[row['Attribute']]['Salsify Display Name'] ||= row['Attribute']
          hash[row['Attribute']]['Attribute Group'] ||= 'Workflow Properties'
          hash[row['Attribute']]['Type'] ||= 'enumerated'
          hash[row['Attribute']]['Picklist Values'] << row['Status']
        end
      end
    end

    def worksheet
      @worksheet ||= Roo::Spreadsheet.open(file_location)
    end

    def file_location
      if ENV['CARS_ENVIRONMENT'] == 'production'
        'lib/cars_integration/cache/attribute_map.xlsx'
      else
        'lib/cars_integration/cache/qa_attribute_map.xlsx'
      end
    end

  end
end
