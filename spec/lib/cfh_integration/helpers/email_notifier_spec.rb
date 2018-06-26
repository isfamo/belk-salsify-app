describe EmailNotifier do

  let(:email_notifier_with_errors) { EmailNotifier.new(mode: :test, error: 'ERROR!') }
  let(:email_notifier_without_errors) { EmailNotifier.new(mode: :test, error: nil) }
  let(:postmark_client) { double('postmark_client') }

  before :each do
    Timecop.freeze(Time.local(2017, 01, 15))
    allow(postmark_client).to receive(:deliver).and_return(true)
    allow_any_instance_of(EmailNotifier).to receive(:postmark_client).and_return(postmark_client)
  end

  describe 'pim import with errors' do
    context self do
      it 'returns the correct #pim_import_subject' do
        expect(email_notifier_with_errors.pim_import_subject).to eq(
          'Errors encountered importing PIM Feed! Please contact Salsify'
        )
      end

      it 'returns the correct #pim_import_body' do
        expect(email_notifier_with_errors.pim_import_body).to eq(
          'Errors encountered importing PIM Feed: ERROR!'
        )
      end

      it 'returns the correct #cfh_body' do
        expect(email_notifier_with_errors.cfh_body).to eq(
          'Errors encountered generating CFH XML: ERROR!'
        )
      end

      it 'returns the correct #cma_feed_subject' do
        expect(email_notifier_with_errors.cma_feed_subject).to eq(
          'Errors encountered on CMA export! Please contact Salsify'
        )
      end

      it 'returns the correct #cma_feed_body' do
        expect(email_notifier_with_errors.cma_feed_body).to eq(
          'Errors encountered in CMA export: ERROR!'
        )
      end

      it 'returns the correct #color_feed_subject' do
        expect(email_notifier_with_errors.color_feed_subject).to eq(
          'Errors encountered in Color Over Key export! Please contact Salsify'
        )
      end

      it 'returns the correct #color_feed_body' do
        expect(email_notifier_with_errors.color_feed_body).to eq(
          'Errors encountered in Color Over Key export: ERROR!'
        )
      end
    end
  end

  describe 'pim import without errors' do
    context self do
      it 'returns the correct #pim_import_subject' do
        expect(email_notifier_without_errors.pim_import_subject).to eq(
          'Salsify import of PIM feed finished successfully at 12:00:00'
        )
      end

      it 'returns the correct #pim_import_body' do
        expect(email_notifier_without_errors.pim_import_body).to eq(
          'Salsify import of PIM feed finished successfully at 12:00:00'
        )
      end

      it 'returns the correct #cfh_subject' do
        expect(email_notifier_without_errors.cfh_subject).to eq(
          'CFH XML feed successfully generated and uploaded to Belk FTP at 12:00:00'
        )
      end

      it 'returns the correct #cfh_body' do
        expect(email_notifier_without_errors.cfh_body).to eq(
          'CFH XML feed successfully generated and uploaded to Belk FTP at 12:00:00'
        )
      end

      it 'returns the correct #cma_feed_subject' do
        expect(email_notifier_without_errors.cma_feed_subject).to eq(
          'CMA XML successfully generated and uploaded to Belk FTP at 12:00:00'
        )
      end

      it 'returns the correct #cma_feed_body' do
        expect(email_notifier_without_errors.cma_feed_body).to eq(
          'CMA XML successfully generated and uploaded to Belk FTP at 12:00:00'
        )
      end

      it 'returns the correct #color_feed_subject' do
        expect(email_notifier_without_errors.color_feed_subject).to eq(
          'Color Over Key export successfully generated and uploaded to Belk FTP at 12:00:00'
        )
      end

      it 'returns the correct #color_feed_body' do
        expect(email_notifier_without_errors.color_feed_body).to eq(
          'Color Over Key export successfully generated and uploaded to Belk FTP at 12:00:00'
        )
      end

    end

    describe '#mode' do
      it 'responds to pim_import' do
        expect(EmailNotifier.notify(mode: :pim_import, error: nil)).to eq true
      end

      it 'responds to cfh' do
        expect(EmailNotifier.notify(mode: :cfh, error: nil)).to eq true
      end

      it 'responds to cma_feed' do
        expect(EmailNotifier.notify(mode: :cma_feed, error: nil)).to eq true
      end

      it 'responds to color_feed' do
        expect(EmailNotifier.notify(mode: :color_feed, error: nil)).to eq true
      end

      it 'doesn\'t respond to test' do
        expect(EmailNotifier.notify(mode: :test, error: nil)).to eq nil
      end

    end
  end

end
