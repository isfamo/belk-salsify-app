require './lib/cfh_integration/demandware'

class CFHOnDemandFullExportJob < Struct.new(:cfh_execution, :sid)
  include FTPClients

  def perform
    puts 'On-Demand Full export job queued...'
    begin
      SalsifyToDemandware.export_on_demand_category_hierarchy(cfh_execution, sid)
      RemoveIrreleventCategories.run(cfh_execution, sid)
      SalsifyToDemandware.roll_up_products(cfh_execution)

      puts 'Generating On-Demand trees...'
      tree_a = SalsifyTree.new(cfh_execution.salsify_sql_nodes, :added)
    rescue SalsifyTree::MissingTreeRoot => error
      puts error
      Bugsnag.notify(error)
    else
      puts 'Generating On-Demand full XML...'

      filename = "./tmp/#{sid}-#{Time.now.to_i}.xml"
      gz_tmp_file = Tempfile.new('gz_tmp_file.xml.gz')
      obj = Demandware::XMLGenerator.new(filename)
      obj.create_from_category_tree(tree_a)
      upload_remote_file_path = File.join(CFHSynchronization::REMOTE_LOCAL_PATH, "Catalog_CFH_#{Time.now.strftime('%Y%m%d-%H%M')}.xml.gz")
      salsify_upload_remote_file_path = File.join(CFHSynchronization::REMOTE_LOCAL_PATH, "Catalog_CFH_ON_DEMAND_#{Time.now.strftime('%Y%m%d-%H%M')}.xml.gz")
      puts 'XML was generated!'

      puts 'Zipping XML'
      Zlib::GzipWriter.open(gz_tmp_file) do |gz|
        gz.write(File.read(filename))
      end

      puts 'Uploading XML'
      salsify_ftp.upload(gz_tmp_file, salsify_upload_remote_file_path)
      gz_tmp_file.open
      belk_ftp.upload(gz_tmp_file, upload_remote_file_path)
    end
  end

end
