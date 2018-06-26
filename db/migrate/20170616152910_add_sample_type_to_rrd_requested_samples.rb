class AddSampleTypeToRrdRequestedSamples < ActiveRecord::Migration[5.0]
  def change
    add_column :rrd_requested_samples, :sample_type, :string
  end
end
