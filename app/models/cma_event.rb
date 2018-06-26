class CMAEvent < ApplicationRecord
  scope :active_today_and_in_future, -> (date = Date.today, skus_to_include) {
    where(sku_code: skus_to_include).where.not(record_type: '49').where(
      "(end_date >= ? AND start_date <= ? OR start_date >= ?)",
      DateTime.strptime("#{(date - 1.day).to_s} 0000 #{offset}", '%Y-%m-%d %H%M %z').utc,
      DateTime.strptime("#{date.to_s} 2359 #{offset}", '%Y-%m-%d %H%M %z').utc,
      DateTime.strptime("#{date.to_s} 0000 #{offset}", '%Y-%m-%d %H%M %z').utc,
    )
  }

  scope :bonus_event_codes, -> (date, events) {
    start_date = DateTime.strptime("#{date.to_s} 2359 #{offset}", '%Y-%m-%d %H%M %z').utc
    events.where("adevent LIKE ? AND start_date <= ?", "%BB%", start_date + 1.day)
  }

  scope :active_for_sku, -> (date, events) {
    end_date = DateTime.strptime("#{date.to_s} 0000 #{offset}", '%Y-%m-%d %H%M %z').utc
    start_date = DateTime.strptime("#{date.to_s} 2359 #{offset}", '%Y-%m-%d %H%M %z').utc
    events.select do |event|
      next unless event.end_date
      event.end_date >= end_date && event.start_date <= start_date
    end.compact
  }

  # depricated since active_today_and_in_future and active_for_sku envelop this query
  scope :remaining_active_events, -> (date, skus, skus_to_include) {
    where(sku_code: skus_to_include).where.not(record_type: '49').where.not(sku_code: skus).where(
      "end_date >= ? AND start_date <= ?",
      DateTime.strptime("#{date.to_s} 0000 #{offset}", '%Y-%m-%d %H%M %z').utc,
      DateTime.strptime("#{date.to_s} 2359 #{offset}", '%Y-%m-%d %H%M %z').utc
    )
  }

  scope :actively_priced_skus, -> (date = Date.today) {
    date = DateTime.strptime("#{date.to_s} 2359 #{offset}", '%Y-%m-%d %H%M %z') + 1.day
    # where("record_type = '49' AND start_date <= ?", date).select('DISTINCT ON ("sku_code") *')
    where("record_type = '49'").select('DISTINCT ON ("sku_code") *').select do |event|
      event.start_date.day == date.day && event.start_date.month == date.month
    end
  }

  scope :older_than, -> (number_of) {
    where("end_date < ? OR start_date < ? AND regular_price is NOT NULL", number_of.days.ago, number_of.days.ago)
  }

  TIMEZONE = 'Eastern Time (US & Canada)'

  # Row Format
  # SKUCODE VENDORUPC RECORDTYPE EVENTID ADEVENT
  # STARTDATE STARTTIME
  # ENDDATE ENDTIME
  def self.new_from_cma_row(row)
    raise ArgumentError, 'row should have type CSV::Row' unless row.is_a?(CSV::Row)

    record = CMAEvent.new(
      sku_code: row[:skucode],
      vendor_upc: row[:vendorupc],
      record_type: row[:recordtype],
      event_id: row[:eventid],
      adevent: row[:adevent],
      regular_price: row[:origprice]
    )
    begin
      record.start_date = create_datetime(row[:startdate], row[:starttime])
      record.end_date = create_datetime(row[:enddate], row[:endtime]) if row[:enddate]
    rescue ArgumentError
      record.errors.add(:date, "Invalid date format for #{row}")
    end
    record
  end

  def ended_on?(date = Date.yesterday)
    end_date.between?(
      DateTime.strptime("#{(date - 1).to_s} 0000 #{offset}", '%Y-%m-%d %H%M %z').utc,
      DateTime.strptime("#{date.to_s} 2359 #{offset}", '%Y-%m-%d %H%M %z').utc
    ) if end_date
  end

  def to_hash
    CMAEvent.column_names.map do |column_name|
      [ column_name, self.send(column_name.to_sym) ]
    end.to_h
  end

  ########################################################################
  ################# https://github.com/jamis/bulk_insert #################
  #################       Copyright 2015 Jamis Buck      #################

  # Permission is hereby granted, free of charge, to any person obtaining
  # a copy of this software and associated documentation files (the
  # "Software"), to deal in the Software without restriction, including
  # without limitation the rights to use, copy, modify, merge, publish,
  # distribute, sublicense, and/or sell copies of the Software, and to
  # permit persons to whom the Software is furnished to do so, subject to
  # the following conditions:
  # The above copyright notice and this permission notice shall be
  # included in all copies or substantial portions of the Software.

  # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
  # EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
  # MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
  # NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
  # LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
  # OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
  # WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

  # We needed to support postgresql 9.5 `ON CONFLICT` feature
  # so I decided not to use the gem's pristine version
  def self.bulk_insert(*columns, values: nil, set_size:500)
    columns = default_bulk_columns if columns.empty?
    worker = BulkInsert::Worker.new(connection, table_name, columns, set_size)

    if values.present?
      transaction do
        worker.add_all(values)
        worker.save!
      end
      nil
    elsif block_given?
      transaction do
        yield worker
        worker.save!
      end
      nil
    else
      worker
    end
  end

  # helper method for preparing the columns before a call to :bulk_insert
  def self.default_bulk_columns
    self.column_names - %w(id)
  end
  ########################################################################

  private

  # date format - 20160503
  # time format - 1011

  # Default timezone is ET
  def self.create_datetime(date, time)
    time = time || '0000'

    DateTime.strptime("#{date} #{time} #{offset}", '%Y%m%d %H%M %z')
  end

  def self.offset
    ActiveSupport::TimeZone.new(TIMEZONE).formatted_offset
  end

  def offset
    self.class.offset
  end
end
