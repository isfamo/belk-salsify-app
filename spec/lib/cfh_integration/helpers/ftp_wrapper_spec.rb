describe FTP::Wrapper do
  before(:all) do
    ENV['SALSIFY_FTP_HOST'] = '127.0.0.1'
    ENV['SALSIFY_FTP_USER'] = 'demo'
    ENV['SALSIFY_FTP_PASSWORD'] = 'password'
  end

  context '::initialize(args)' do
    it 'should initialize a ftp wrapper object correctly' do
      obj = FTP::Wrapper.new(client: :salsify)

      expect(obj).to be_an_instance_of(FTP::Wrapper)
      expect(obj.host).to eq('127.0.0.1')
    end
  end

  context '::initialize' do
    before :each do
      ENV['SALSIFY_FTP_HOST'] = '127.0.0.1'
      ENV['SALSIFY_FTP_USER'] = 'demo'
      ENV['SALSIFY_FTP_PASSWORD'] = 'password'
    end

    it 'should not raise an error if env vars are provided' do
      obj = FTP::Wrapper.new(client: :salsify)
      expect(obj).to be_an_instance_of(FTP::Wrapper)
      expect(obj.host).to eq('127.0.0.1')
      expect(obj.user).to eq('demo')
      expect(obj.password).to eq('password')
    end
  end

  xcontext '#upload(args), #download(args)' do
    FILE_NAMES = %w(file.txt file_uploaded.txt file_downloaded.txt)

    before(:each) do
      @obj = FTP::Wrapper.new(client: :salsify)
      FILE_NAMES.each do |fn|
        File.delete(fn) if File.exists?(fn)
      end
    end

    it 'should raise error if local file is missing' do
      expect {
        @obj.upload("file.txt")
      }.to raise_error(FTP::MissingLocalFile)
    end

    it 'should upload and download a file successfully' do
      file_name = "file.txt"
      File.open(file_name, 'wb') do |file|
        file.write("ABCD")
      end

      @obj.upload(file_name)
      File.delete(file_name) if File.exists?(file_name)
      expect(File.exists?(file_name)).to be(false)

      @obj.download(file_name)
      expect(File.exists?(file_name)).to be(true)
      expect(File.open(file_name).read).to eq("ABCD")
    end

    it 'should upload and download a file with different names successfully' do
      file_name = "file.txt"
      File.open(file_name, 'wb') do |file|
        file.write("XYZ")
      end

      @obj.upload(file_name, "file_uploaded.txt")

      @obj.download("file_uploaded.txt", "file_downloaded.txt")
      expect(File.open("file_downloaded.txt").read).to eq("XYZ")
    end

    after(:each) do
      FILE_NAMES.each do |fn|
        File.delete(fn) if File.exists?(fn)
      end
    end
  end
end
