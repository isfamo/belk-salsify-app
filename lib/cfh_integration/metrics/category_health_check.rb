module Metrics
  class CategoryHealthCheck
    include Muffin::SalsifyClient

    def self.generate_reporting
      new.generate_reporting
    end

    def generate_reporting
      puts 'generating reporting...'
      generate_category_report
      generate_list_report
      email_reports
      puts 'finished...'
    end

    def email_reports
      HealthCheckEmailNotifier.notify
    end

    def generate_category_report
      CSV.open('lib/cfh_integration/output/category_health_check.csv', 'w') do |csv|
        csv << [ 'Category Name', 'Error' ]
        category_hierarchy.each do |category|
          next if list_names.include?(category)
          csv << [ category.force_encoding('UTF-8'), 'Missing associated list' ]
          next if category_metadata.include?(category)
          csv << [ category.force_encoding('UTF-8'), 'Missing associated category metadata' ]
        end
      end
    end

    def generate_list_report
      CSV.open('lib/cfh_integration/output/list_health_check.csv', 'w') do |csv|
        csv << [ 'List Name', 'Error' ]
        list_names.each do |list|
          next if category_hierarchy.include?(list)
          csv << [ list, 'Missing associated category' ]
          next if category_metadata.include?(list)
          csv << [ list, 'Missing associated category metadata' ]
        end
      end
    end

    def category_hierarchy
      @category_hierarchy ||= SalsifyToDemandware::CategoryHierarchy.trigger_export(salsify_client(org_id: 3562)).map(&:first)
    end

    def category_metadata
      @category_metadata ||= SalsifyToDemandware::CategoryMetadata.trigger_export(salsify_client(org_id: 3562)).map do |category|
        category['product_id']
      end
    end

    def list_names
      @list_names ||= lazily_paginate('product', client: salsify_client(org_id: 3562), resource: :lists).to_a.map(&:name)
    end

  end
end
