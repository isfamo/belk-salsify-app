# Add your own tasks in files placed in lib/tasks ending in .rake,
# for example lib/tasks/capistrano.rake, and they will automatically be available to Rake.

require_relative 'config/application'

Rails.application.load_tasks

task google: [ :environment ] do
  Enrichment::Dictionary.new.google_sheet.iph_lookup
end

task find_outlier_lists: [ :environment ] do
  Metrics::Lists.find_outlier_lists
end

task count_all_products_on_lists: [ :environment ] do
  Metrics::Lists.count_all_products_on_lists
end

task find_broken_filters: [ :environment ] do
  Metrics::Lists.find_broken_filters
end

task compare_list_metadata_with_lists: [ :environment ] do
  Metrics::Lists.compare_list_metadata_with_lists
end

task generate_health_check_reporting: [ :environment ] do
  Metrics::CategoryHealthCheck.generate_reporting
end

task update_list_filters: [ :environment ] do
  puts 'updating list filters...'
  Maintenance::ListFilters.update
  puts 'finished...'
end

task update_product_import: [ :environment ] do
  puts 'updating import...'
  Maintenance::UpdateProductImport.run
  puts 'finished...'
end

task locate_orphaned_products: [ :environment ] do
  puts 'locating orphaned products...'
  Metrics::LocateOrphanedProducts.run
  puts 'finished...'
end
