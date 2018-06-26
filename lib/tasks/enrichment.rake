namespace :enrichment do
  task generate_target_schema: :environment do
    Enrichment::TargetSchema.generate('pbreault@salsify.com')
  end

  task generate_and_import_target_schema: :environment do
    Enrichment::TargetSchema.generate_and_import('pbreault@salsify.com')
  end

  task set_enrichment_attributes: :environment do
    dictionary = Enrichment::Dictionary.new
    dictionary.set_enrichment_attributes
  end

  task generate_category_import: :environment do
    dictionary = Enrichment::Dictionary.new
    CSV.open('category_import.csv', 'w') do |csv|
      csv << [ 'salsify:id', 'salsify:name', 'salsify:attribute_id', 'salsify:parent_id' ]
      dictionary.categories.uniq.each do |category|
        csv << [ category[:category], category[:name], 'iphCategory', category[:parent] ]
      end
    end
  end

  task convert_categories: :environment do
    dictionary = Enrichment::Dictionary.new
    CSV.open('belk_iph_migration.csv', 'w') do |csv|
      csv << [ 'product_id', 'iphCategory' ]
      Roo::Spreadsheet.open('belk_iph_mapping.xlsx').drop(1).each do |row|
        lookup = dictionary.category_mapping[row.second]
        next unless lookup
        csv << [ row.first, lookup ]
      end
    end
  end
end
