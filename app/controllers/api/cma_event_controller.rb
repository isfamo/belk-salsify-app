class Api::CMAEventController < ApplicationController
  before_action :salsify_api_session, only: [ :index, :demand ]

  def demand
    begin
      filename = params['filename']
      if validate_filename(filename)
        if file_exists?(filename)
          job = CMAOnDemandExportJob.new(date(filename), filename)
          puts 'queuing job...'
          Delayed::Job.enqueue(job)
        else
          render json: { error: 'Unable to locate FTP file, please check spelling.' }, status: 401
        end
      else
        render json: { error: 'You must provide an FTP filename with correct extension.' }, status: 401
      end
    rescue
      render json: { error: 'An error occured, please contact Salsify.' }, status: 401
    end
  end

  private

  def validate_filename(filename)
    return false unless filename
    File.extname(filename) == '.gz'
  end

  def date(filename)
    Date.parse(filename.scan(/\d/).join(''))
  end

  def file_exists?(filename)
    salsify_ftp.find_file(remote_ir_path, filename).present?
  end

  def remote_ir_path
    ENV['CARS_ENVIRONMENT'] == 'production' ? 'Belk/Prod/Price_IR' : 'Belk/Qa/Price_IR'
  end

  def salsify_ftp
    @salsify_ftp ||= FTP::Wrapper.new(client: :salsify)
  end

end
