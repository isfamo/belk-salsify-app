require './lib/cfh_integration/demandware'

class OfflineCFHFeed
  include JobStatusHelper
  include FTPClients
  include Muffin::SalsifyClient
  include ErrorUtils

  ORG_ID = 3562

  attr_reader :cfh_execution, :xml_tmp_file, :gz_tmp_file, :upload_remote_file_path

  def initialize
    @cfh_execution = SalsifyCfhExecution.manual_today.create
    @xml_tmp_file = "tmp/offline_xml_categ_#{Date.today.to_s}.xml"
    @gz_tmp_file = Tempfile.new('gz_tmp_file.xml.gz')
    @upload_remote_file_path = File.join(
      CFHSynchronization::REMOTE_LOCAL_PATH, "Catalog_CFH_#{Time.now.strftime('%Y%m%d-%H%M')}.xml.gz"
    )
    job_status.update(title: 'offline')
  end

  def self.run
    new.run
  end

  def run
    begin
      populate_categories
      populate_products
      set_product_groupings
      append_products_to_shop_all_node
      remove_duplicate_products
      remove_offline_nodes
      serialize_xml
      gzip_xml
      upload_to_ftp
    rescue => error
      job_status.error = format_error(error)
      send_notification_email(error: error) if ENV.fetch('RAILS_ENV') != 'development'
      raise error
    ensure
      finalize_job_status
    end
  end

  def serialize_xml
    job_status.update(activity: 'Generating XML')
    tree = SalsifyTree.new(cfh_execution.salsify_sql_nodes.all, :added)
    Demandware::XMLGenerator.new(xml_tmp_file).create_from_category_tree(tree)
  end

  def remove_duplicate_products
    cfh_execution.salsify_sql_nodes.products.group_by(&:sid).each do |_, products|
      next unless products.count > 1
      products.first.destroy
    end
  end

  def gzip_xml
    Zlib::GzipWriter.open(gz_tmp_file) { |gz| gz.write(File.read(xml_tmp_file)) }
  end

  def upload_to_ftp
    job_status.update(activity: 'Uploading to FTP')
    belk_ftp.upload(gz_tmp_file, upload_remote_file_path)
    gz_tmp_file.open
    salsify_ftp.upload(gz_tmp_file, upload_remote_file_path)
  end

  def populate_products
    SalsifyToDemandware.export_offline_catagory_products(cfh_execution, offline_lists)
  end

  def offline_lists
    lazily_paginate('product', client: salsify_client(org_id: ORG_ID), resource: :lists).map do |list|
      Hashie::Mash.new(id: list.id, name: list.name)
    end.delete_if { |list| !offline_list_names.include?(list.name) }
  end

  def offline_list_names
    offline_nodes.pluck(:sid)
  end

  def set_product_groupings
    cfh_execution.salsify_sql_nodes.products.each do |product|
      product.data['grouping_condition'] = 'Exclude'
      product.save
    end
  end

  def populate_categories
    job_status.update(activity: 'Exporting categories from Salsify')
    SalsifyToDemandware.export_category_hierarchy(cfh_execution)
    cfh_execution.salsify_sql_nodes.delete(*nodes_to_delete)
  end

  def append_products_to_shop_all_node
    cfh_execution.salsify_sql_nodes.products.each { |product| product.update(parent_sid: 'shop-all-shop-all') }
  end

  def remove_offline_nodes
    cfh_execution.salsify_sql_nodes.delete(*offline_nodes)
  end

  def nodes_to_delete
    cfh_execution.salsify_sql_nodes.categories - (shop_all_categories + offline_nodes)
  end

  def offline_nodes
    cfh_execution.salsify_sql_nodes.select { |node| node.data['grouping_condition'] == 'Only' }
  end

  def shop_all_categories
    cfh_execution.salsify_sql_nodes.select { |node| node.sid.include?('shop-all') || node.sid.include?('root') }
  end

  def send_notification_email(error: nil)
    EmailNotifier.notify(mode: :offline, error: error)
  end

end
