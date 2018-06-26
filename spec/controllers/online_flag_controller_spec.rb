RSpec.describe Api::OnlineFlagController, type: :controller do

  let(:true_payload) { File.read('spec/controllers/fixtures/online_flag_true_payload.json') }
  let(:false_payload) { File.read('spec/controllers/fixtures/online_flag_false_payload.json') }
  let(:belk_ftp) { double('belk_ftp') }
  let(:salsify_ftp) { double('belk_ftp') }
  let(:generated_local_xml_filepath) { 'spec/controllers/fixtures/generated.xml'}
  let(:expected_local_xml_filepath) { 'spec/controllers/fixtures/expected.xml'}

  before :each do
    Api::OnlineFlagController.any_instance.stub(:belk_ftp).and_return(belk_ftp)
    Api::OnlineFlagController.any_instance.stub(:salsify_ftp).and_return(salsify_ftp)
    Api::OnlineFlagController.any_instance.stub(:local_xml_filepath).and_return(generated_local_xml_filepath)
    allow(belk_ftp).to receive(:upload).and_return(nil)
    allow(salsify_ftp).to receive(:upload).and_return(nil)
  end

  describe 'POST #create' do
    it 'returns if online-flag is true' do
      post :create, true_payload
      response_body = JSON.parse(response.body)
      expect(response.status).to eq 200
      expect(response_body['success']).to eq 'online_flag set to true... aborting.'
    end

    it 'returns generates XML if online-flag is false' do
      post :create, false_payload
      response_body = JSON.parse(response.body)
      expect(response.status).to eq 200
      expect(response_body['success']).to eq 'XML successfully delivered to Belk.'
    end

    it 'generates the correctly formatted report' do
      generated_xml = Nokogiri::XML(File.read(generated_local_xml_filepath)).to_xml
      expected_xml = Nokogiri::XML(File.read(expected_local_xml_filepath)).to_xml
      expect(generated_xml).to eq expected_xml
    end
  end

end
