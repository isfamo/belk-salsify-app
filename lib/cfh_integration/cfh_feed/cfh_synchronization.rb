require './lib/cfh_integration/demandware'

class CFHSynchronization
  include JobStatusHelper
  include FTPClients
  include ErrorUtils

  REMOTE_LOCAL_PATH = '/upload'.freeze

  attr_reader :gz_tmp_file, :upload_remote_file_path, :date

  def initialize
    @gz_tmp_file = Tempfile.new('gz_tmp_file.xml.gz')
    @upload_remote_file_path = File.join(REMOTE_LOCAL_PATH, "Catalog_CFH_#{Time.now.strftime('%Y%m%d-%H%M')}.xml.gz")
    @date = Time.now.in_time_zone(CMAEvent::TIMEZONE).to_date
    job_status.update(title: :cfh)
  end

  def self.run
    new.run
  end

  def self.generate_cfh_export
    new.run(export_only: true)
  end

  def run(export_only: false)
    begin
      job_status.update(activity: 'Listening for file on FTP')
      import_pim_data unless export_only
      generate_cfh_export
      send_cfh_notification_email if ENV.fetch('RAILS_ENV') != 'development'
    rescue => error
      job_status.error = format_error(error)
      send_cfh_notification_email(error: error) if ENV.fetch('RAILS_ENV') != 'development'
      raise error
    ensure
      finalize_job_status
    end
  end

  def import_pim_data
    Stopwatch.time("$CFH SYNC$ PIM import running for today, #{date}") do
      PIMToSalsify.import_pim_feed(date)
    end
    send_import_notification_email
  rescue => error
    send_import_notification_email(error: error)
    puts '$CFH SYNC$ Error encountered during PIM import!'
    puts error
  end

  def send_import_notification_email(error: nil)
    EmailNotifier.notify(mode: :pim_import, error: error)
  end

  def send_cfh_notification_email(error: nil)
    EmailNotifier.notify(mode: :cfh, error: error)
  end

  def generate_cfh_export
    Stopwatch.time("$CFH SYNC$ for today, #{date}") do
      puts "$CFH SYNC$ running with cfh_exec_yesterday: #{cfh_exec_yesterday.inspect} and cfh_exec_today: #{cfh_exec_today.inspect}"
      job_status.update(activity: 'Exporting categories from Salsify')
      export_salsify_data
      job_status.update(activity: 'Computing Delta')
      compute_tree_a
      compute_tree_b
      compute_diff
      job_status.update(activity: 'Generating XML')
      build_xml
      gzip_xml
      job_status.update(activity: 'Uploading XML')
      upload_to_ftp
    end
  end

  def export_salsify_data
    Stopwatch.time('$CFH SYNC$ exporting hierarchy from Salsify') do
      SalsifyToDemandware.export_category_hierarchy(cfh_exec_today)
      SalsifyToDemandware.export_category_products(cfh_exec_today)
      SalsifyToDemandware.roll_up_products(cfh_exec_today)
    end
  end

  def cfh_exec_yesterday
    @cfh_exec_yesterday ||= SalsifyCfhExecution.last_auto
  end

  def cfh_exec_today
    @cfh_exec_today ||= SalsifyCfhExecution.create!
  end

  def xml_tmp_file
    @xml_tmp_file ||= "tmp/xml_categ_#{Date.today.to_s}.xml"
  end

  # yesterday
  def compute_tree_a
    @tree_a ||= Stopwatch.time('$CFH SYNC$ building Tree A') do
      changed_products = SalsifySqlNode.changed_products(:yesterday, cfh_exec_today.id, cfh_exec_yesterday.id)
      tree_nodes = SalsifySqlNode.tree_nodes(changed_products, cfh_exec_yesterday.id)
      SalsifyTree.new(tree_nodes)
    end
  end

  # today
  def compute_tree_b
    @tree_b ||= Stopwatch.time('$CFH SYNC$ building Tree B') do
      changed_products = SalsifySqlNode.changed_products(:today, cfh_exec_today.id, cfh_exec_yesterday.id)
      tree_nodes = SalsifySqlNode.tree_nodes(changed_products, cfh_exec_today.id)
      SalsifyTree.new(tree_nodes)
    end
  end

  def compute_diff
    @diff ||= Stopwatch.time('$CFH SYNC$ computing diff') do
      @tree_b.diff(@tree_a)
    end
  end

  def build_xml
    generator = Demandware::XMLGenerator.new(xml_tmp_file)
    generator.create_from_category_tree(@diff)
  end

  def gzip_xml
    puts '$CFH SYNC$ zipping xml...'
    Zlib::GzipWriter.open(gz_tmp_file) { |gz| gz.write(File.read(xml_tmp_file)) }
  end

  def upload_to_ftp
    puts '$CFH SYNC$ uploading xml...'
    job_status.update(activity: 'Uploading to FTP')
    belk_ftp.upload(gz_tmp_file, upload_remote_file_path)
    gz_tmp_file.open
    salsify_ftp.upload(gz_tmp_file, upload_remote_file_path)
  end

end
