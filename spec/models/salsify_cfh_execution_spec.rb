describe SalsifyCfhExecution, type: :model do
  context '::auto_today' do
    it 'should create a valid row - todays date' do
      row = FactoryGirl.create(:salsify_cfh_execution)
      expect(SalsifyCfhExecution.auto_today.count).to eq(1)
    end

    it 'should create a valid row - yesterdays date' do
      row = FactoryGirl.create(:salsify_cfh_execution, created_at: DateTime.yesterday)
      expect(SalsifyCfhExecution.auto_yesterday.count).to eq(1)
    end

    it 'should create a valid row - manual generation' do
      row = FactoryGirl.create(:salsify_cfh_execution, exec_type: "Abc")
      expect(SalsifyCfhExecution.auto_today.count).to eq(0)
    end
  end
end