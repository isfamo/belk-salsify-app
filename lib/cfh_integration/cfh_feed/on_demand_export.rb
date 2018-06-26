require './lib/cfh_integration/demandware'

class OnDemandExport
  include FTPClients

  REMOTE_LOCAL_PATH = '/upload'.freeze

  attr_reader :cfh_exec_today, :cfh_exec_yesterday, :xml_tmp_file, :gz_tmp_file,
    :upload_remote_file_path

  def initialize(cfh_exec_today, cfh_exec_yesterday)
    @cfh_exec_today = cfh_exec_today
    @cfh_exec_yesterday = cfh_exec_yesterday
    @xml_tmp_file = "tmp/xml_categ_#{Date.today.to_s}.xml"
    @gz_tmp_file = Tempfile.new('gz_tmp_file.xml.gz')
    @upload_remote_file_path = File.join(REMOTE_LOCAL_PATH, "Catalog_CFH_#{Time.now.strftime('%Y%m%d-%H%M')}.xml.gz")
  end

  def self.run(cfh_exec_today, cfh_exec_yesterday = nil)
    new(cfh_exec_today, cfh_exec_yesterday).run
  end

  def run
    cfh_exec_yesterday ? run_in_delta_mode : run_in_full_mode
  end

  def run_in_full_mode
    puts '$CFH ON DEMAND$ running in full mode...'
    cfh_xml.create_from_category_tree(tree_a)
    gzip_xml
    upload_to_ftp
  end

  def run_in_delta_mode
    puts '$CFH ON DEMAND$ running in delta mode...'
    cfh_xml.create_from_category_tree(tree_diff)
    gzip_xml
    upload_to_ftp
  end

  def upload_to_ftp
    puts '$CFH ON DEMAND$ uploading XML to salsify...'
    salsify_ftp.upload(gz_tmp_file, upload_remote_file_path)
    gz_tmp_file.open
    puts "$CFH ON DEMAND$ uploading file #{upload_remote_file_path} to belk..."
    belk_ftp.upload(gz_tmp_file, upload_remote_file_path)
  end

  def gzip_xml
    puts '$CFH ON DEMAND$ zipping XML...'
    Zlib::GzipWriter.open(gz_tmp_file) { |gz| gz.write(File.read(xml_tmp_file)) }
  end

  def cfh_xml
    @cfh_xml ||= Demandware::XMLGenerator.new(xml_tmp_file)
  end

  def tree_a
    puts '$CFH ON DEMAND$ creating Tree A...'
    changed_products = SalsifySqlNode.changed_products(:today, cfh_exec_today.id, cfh_exec_yesterday.id)
    tree_nodes = SalsifySqlNode.tree_nodes(changed_products, cfh_exec_today.id)
    SalsifyTree.new(tree_nodes)
  end

  def tree_b
    puts '$CFH ON DEMAND$ creating Tree B...'
    changed_products = SalsifySqlNode.changed_products(:yesterday, cfh_exec_today.id, cfh_exec_yesterday.id)
    tree_nodes = SalsifySqlNode.tree_nodes(changed_products, cfh_exec_yesterday.id)
    SalsifyTree.new(tree_nodes)
  end

  def tree_diff
    puts '$CFH ON DEMAND$ computing diffs...'
    tree_a.diff(tree_b)
  end

end
