class Api::OnlineFlagController < ApplicationController
  protect_from_forgery with: :null_session
  include RequestBodyHandler

  def create
    if inactive_categories.present?
      generate_xml
      gzip_xml
      belk_ftp.upload(gz_tmp_file, upload_remote_filepath)
      gz_tmp_file.open
      salsify_ftp.upload(gz_tmp_file, upload_remote_filepath)
      render json: { success: 'XML successfully delivered to Belk.' }, status: 200
    else
      render json: { success: 'online_flag set to true... aborting.' }, status: 200
    end
  end

  private

  def upload_remote_filepath
    @upload_remote_filepath ||= File.join(ProcessCMAFeed::REMOTE_UPLOAD_PATH, "Catalog_CFH_#{Time.now.strftime('%Y%m%d-%H%M')}.xml.gz")
  end

  def local_xml_filepath
    @local_xml_filepath ||= File.join(ProcessCMAFeed::EXTRACT_DIR, "cfh-online-flag-#{date.strftime('%Y%m%d')}.xml")
  end

  def gz_tmp_file
    @gz_tmp_file ||= Tempfile.new('gz_tmp_file.xml.gz')
  end

  def gzip_xml
    Zlib::GzipWriter.open(gz_tmp_file) do |gz|
      gz.write(File.read(local_xml_filepath))
    end
  end

  def generate_xml
    xml = Demandware::XMLGenerator.new(local_xml_filepath, date)
    xml.create_online_flag_categories(inactive_categories)
  end

  def date
    @date ||= Date.today
  end

  def belk_ftp
    @belk_ftp ||= FTP::Wrapper.new(client: :belk)
  end

  def salsify_ftp
    @salsify_ftp ||= FTP::Wrapper.new(client: :salsify)
  end

  def inactive_categories
    @inactive_categories ||= categories.select { |product| !product['online-flag'] }
  end

  def categories
    request_body.products
  end

end
