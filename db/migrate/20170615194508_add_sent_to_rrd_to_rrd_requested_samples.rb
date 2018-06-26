class AddSentToRrdToRrdRequestedSamples < ActiveRecord::Migration[5.0]
  def change
    add_column :rrd_requested_samples, :sent_to_rrd, :boolean
  end
end
