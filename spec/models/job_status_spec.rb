describe JobStatus, type: :model do

  let(:job) { create(:completed_job) }
  let(:completed_job) { create(:completed_job) }
  let(:in_progress_job) { create(:in_progress_job) }
  let(:expected_attributes) {
    {
      title: 'cma',
      status: 'complete',
      activity: 'Listening to FTP',
      formatted_start_time: '01/14 11:50:00',
      formatted_end_time: '01/15 12:00:00',
      run_time: '10 minutes',
      error: 'None'
    }
  }

  before :each do
    Timecop.freeze(Time.local(2017, 01, 15))
  end

  context 'jobs' do
    it 'creates a vaild job' do
      expect(job).to be_kind_of JobStatus
      expect(completed_job).to be_kind_of JobStatus
      expect(in_progress_job).to be_kind_of JobStatus
    end

    it 'responds to #attributes' do
      expect(job.attributes).to eq expected_attributes
    end

  end

end
