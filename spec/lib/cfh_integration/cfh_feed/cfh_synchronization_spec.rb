describe CFHSynchronization do

  let(:postmark_client) { double('postmark_client') }
  let(:cfh) { CFHSynchronization.new }

  before :each do
    allow(postmark_client).to receive(:deliver).and_return(true)
    allow_any_instance_of(EmailNotifier).to receive(:postmark_client).and_return(postmark_client)
  end

  context self do

    let(:cfh_exec_today) { SalsifyCfhExecution.create! }
    let(:cfh_exec_yesterday) { SalsifyCfhExecution.create! }
    let(:generated_output_file) { 'spec/lib/cfh_integration/cfh_feed/fixtures/generated_cfh.xml' }
    let(:expected_output_file) { 'spec/lib/cfh_integration/cfh_feed/fixtures/expected_cfh.xml' }
    let(:job_status) { double('job_status') }

    before :each do
      allow(job_status).to receive(:update).and_return(nil)
      allow(cfh).to receive(:job_status).and_return(job_status)
      allow(cfh).to receive(:gzip_xml).and_return(nil)
      allow(cfh).to receive(:upload_to_ftp).and_return(nil)
      allow(cfh).to receive(:export_salsify_data).and_return(nil)
      allow(cfh).to receive(:xml_tmp_file).and_return(generated_output_file)
      allow(cfh).to receive(:cfh_exec_today).and_return(cfh_exec_today)
      allow(cfh).to receive(:cfh_exec_yesterday).and_return(cfh_exec_yesterday)
      populate_data
    end

    it 'produces the correctly formatted CFH XML' do
      cfh.generate_cfh_export
      expected_output = Hash.from_xml(File.read(expected_output_file))
      generated_output = Hash.from_xml(File.read(generated_output_file))
      sorted_expected_output = expected_output['catalog']['category_assignment'].sort_by { |cat| cat['product_id'] }
      sorted_generated_output = generated_output['catalog']['category_assignment'].sort_by { |cat| cat['product_id'] }
      expect(sorted_expected_output).to eq sorted_generated_output
    end

    def populate_data
      [ cfh_exec_today.id, cfh_exec_yesterday.id ].each_with_index do |id, index|
        csv = CustomCSV::Wrapper.new('./spec/lib/cfh_integration/cfh_utils/category_hierarchy.csv')
        csv.foreach do |node|
          hash = node.to_h
          SalsifySqlNode.new(parent_sid: hash[:salsifyparent_id], sid: hash[:salsifyid], salsify_cfh_execution_id: id, data: {
            name: hash[:salsifyname],
            list_id: index
          }).save!
          SalsifySqlNode.new(node_type: 'product', parent_sid: hash[:salsifyid], sid: "#{hash[:salsifyid]}_product_#{id}", salsify_cfh_execution_id: id, data: {
            name: "#{hash[:salsifyid]}_product_#{id}",
            list_id: index
          }).save!
        end
      end
    end

  end

  context 'email notifier' do
    it 'import notification email responds without errors' do
      expect(cfh.send_import_notification_email).to eq true
    end

    it 'cfh notification email responds without errors' do
      expect(cfh.send_cfh_notification_email).to eq true
    end

    it 'cfh notification email responds with errors' do
      expect(cfh.send_cfh_notification_email(error: 'ERROR!')).to eq true
    end

    it 'responds to #job_status' do
      expect(cfh.job_status.class).to eq JobStatus
    end

    it 'responds to #finalize_job_status' do
      cfh.finalize_job_status
      expect(JobStatus.find_by(title: 'cfh').status).to eq 'Finished Processing'
    end
  end

end
