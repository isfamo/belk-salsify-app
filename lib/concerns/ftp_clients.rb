module FTPClients
  extend self

  def belk_ftp
    @belk_ftp ||= FTP::Wrapper.new(client: :belk)
  end

  def belk_qa_ftp
    @belk_qa_ftp ||= FTP::Wrapper.new(client: :belk_qa)
  end

  def salsify_ftp
    @salsify_ftp ||= FTP::Wrapper.new(client: :salsify)
  end

end
